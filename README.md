# quick-traefik-demos

Small GitOps demos of how Traefik works. Each scenario runs two ways from one Git repo:

| Demo | Traefik config as | Runs on |
|---|---|---|
| `file-provider/` | Traefik's own YAML files, hot-reloaded | a Linux VM (Lima locally), no Kubernetes |
| `k8s-providers/` | Kubernetes objects: Ingress, IngressRoute, Gateway API | a k3d cluster with Flux |

Every request goes through the same four steps:
**Entrypoint** (the port) → **Router** (matches the request) → **Middleware** (changes it) → **Service** (the backend).
The workshop deck walks through them with the real files from this repo: https://laughingbiscuit.github.io/quick-traefik-demos/

## Run it

You need Docker, `k3d`, `kubectl`, `flux`, `limactl`, `git`, `curl` and `hurl`, and an online Traefik Hub gateway token: `cp .env.example .env`, then fill in `HUB_TOKEN`.

```bash
./demo.sh up      # Gitea, the shared services, then k8s on http://localhost:8080 and the VM on http://localhost:8000
./demo.sh test    # run every test against both demos, and smoke-test the shared services
./demo.sh clean   # delete it all; run before `up` to rebuild
```

## Demo a scenario

Switch scenarios on or off in `file-provider/scenarios/enabled.txt` and `k8s-providers/scenarios/kustomization.yaml`, then:

```bash
./demo.sh sync    # push this working tree to Gitea (no commit needed)
```

Both demos poll Git every 10 seconds, so the change is live within about 20, with no restart: that is the point to show.

| Scenario | Try it | You should see |
|---|---|---|
| `00-passthrough` | `curl -i localhost:8080/passthrough` | whoami's answer and an `X-Route` header naming the route. On Kubernetes there are three versions: Ingress (`X-Route: ingress`), IngressRoute (`?route=ingressroute`) and Gateway API (`?route=httproute`). On the VM one file router answers all three (`X-Route: file`) |
| `00-security-acme` (Kubernetes only) | `curl --cacert certs/ca.pem https://whoami.acme.test/` (with `*.test` going to `127.0.0.1`, or add `--resolve whoami.acme.test:443:127.0.0.1`) | whoami over HTTPS with a certificate that Traefik got from step-ca for exactly `whoami.acme.test`: see it with `openssl s_client -connect localhost:443 -servername whoami.acme.test`. Traefik renews it by itself in its last 6 hours, checking every 10 minutes. It needs `:80` and `:443` free on your machine, and the VM can't do it |

Use port `8000` for the VM. The VM's dashboard is at http://localhost:8001/dashboard/.

**HTTPS:** both gateways terminate TLS on `websecure`: `8443` for k8s, `8444` for the VM. The certificate is a wildcard from step-ca (`*.test`, `demo.test`, `*.demo.test`: curl refuses a one-dot wildcard, so use `whoami.demo.test`). `./demo.sh shared` issues it into `certs/` (gitignored); `k8s` and `vm` install it like the licence, as a Secret and through `vm-provision.sh`, never through Git. Trust `certs/ca.pem` or pass it: `curl --cacert certs/ca.pem https://whoami.demo.test:8443/`. A local DNS entry sending `*.test` to `127.0.0.1` makes the names resolve; the tests use `--resolve`, so CI needs none. Nothing routes on `websecure` yet, so you get Traefik's 404, with the right certificate. It lasts 24 hours, longer than a demo, and nothing renews it: for a certificate that renews itself, see `00-security-acme`. step-ca keeps its CA until `clean`.

## Add a scenario

1. `file-provider/scenarios/01-<name>.yaml` and `k8s-providers/scenarios/01-<name>*.yaml`, listed in `enabled.txt` / `kustomization.yaml`.
2. `tests/01-<name>.hurl`. It runs against both demos, so where they answer differently, accept either (see `X-Route` in `tests/00-passthrough.hurl`).
3. A backend it needs (Redis, Keycloak, ...) goes in `shared/compose.yaml`: both demos reach it through the host. A backend of its own goes in `k8s-providers/stack/`, or on the VM as a systemd unit in `file-provider/vm-provision.sh` (see `whoami`).

`stack/` and `file-provider/traefik-static.yaml` are the install; `scenarios/` is what you show.

## Shared services

Docker Compose runs Gitea and the dependencies the scenarios share, on the host (`shared/compose.yaml`). **Every login is `demo` / `Password123`**: Gitea, Keycloak (and its console), the `00-security-basicauth` scenario, step-ca's provisioner password and Vault's token. (`guest` in Keycloak has the same password but no `admin` role.) The VM reaches them at `host.lima.internal:<port>`, k8s at `host.k3d.internal:<port>`, you at `localhost:<port>`. They configure themselves headlessly on start.

| Service | Port | What it is for | Login |
|---|---|---|---|
| Grafana LGTM | `3001` (Grafana), `4317`/`4318` (OTLP) | metrics, logs and traces in one place | none |
| Redis | `6379` | distributed rate limiting, shared state | none |
| Keycloak | `8180` | OIDC. Realm `demo`, client `traefik` (secret `Password123`), users `demo` (role `admin`) and `guest` (no role) | `demo` / `Password123`, for the realm and the console |
| step-ca | `9000` (HTTPS) | PKI and ACME: root and intermediate CA, ACME directory at `/acme/acme/directory`, and the gateways' wildcard certificate (see Gotchas for the challenge ports) | provisioner `admin`, password `Password123` |
| Vault | `8200` | secrets management: KV at `secret/` | token `Password123` |
| OPA | none | `shared/opa/authz.rego`: gateways evaluate it themselves, `./demo.sh test` checks it with `opa test` | |
| Ollama | `11434` | local LLM for the AI Gateway. Pulls `qwen2.5:0.5b`; set `OLLAMA_MODEL` to change it | none |
| Toxiproxy | `8474` (API) | latency and failures in front of Redis (`6380`) and the demo API (`9111`, `9112`). Proxies: `shared/toxiproxy/toxiproxy.json` | none |
| Gitea MCP | `8081` | MCP tools for the Gitea repo and issues, at `POST /mcp`. The caller brings the token: `Authorization: Bearer <Gitea access token>` | none |

The demo API (`api-v1` and `api-v2`, whoami named per version, on `9101` and `9102`) and a traffic generator that sends `/passthrough` to both gateways run too: `K8S_WEIGHT=80 URL_PATH=/other ./demo.sh shared` changes where the traffic goes.

`./demo.sh smoke` checks all of them (the traffic generator needs both gateways up). `./demo.sh shared` starts or updates them on their own, and `clean` removes them.

## How it works

- **VM:** every 10 seconds `gitops-sync` pulls Git, copies `dashboard.yaml` and the enabled scenarios into the folder Traefik watches (hot-reloaded, no restart), and installs `traefik-static.yaml` (static: Traefik restarts only when it changes). Traefik Hub and the `whoami` backend (port `9500`) are plain binaries from GitHub releases under systemd, with no Docker on the VM. `file-provider/vm-provision.sh` does all of it on any Linux VM: run it as root with `GITOPS_REPO`, `HUB_TOKEN`, `TLS_CERT` and `TLS_KEY`.
- **Kubernetes:** Flux applies `k8s-providers/stack/` (Traefik Hub, whoami), then `k8s-providers/scenarios/`. They are separate because the scenarios need the CRDs that Traefik's install brings.
- **CI** (`.github/workflows/ci.yml`) builds both demos, enables every scenario and runs every test, on each push. It needs the token as a repository secret `HUB_TOKEN`. The Ubuntu runner plays the VM: it runs `vm-provision.sh` directly instead of Lima.

## Gotchas

- **Online token only, for now.** An offline licence makes Hub on the VM exit with "offline mode configuration mismatch" (it needs `hub.offline: true`). The air-gapped setup will be its own scenario with its own token variable.
- Both demos use the same licence, so they show up as one gateway. Use a token per gateway before demoing API Management.
- `./demo.sh k8s` uses its own kubeconfig for `k8s-demo`; your own `kubectl` uses your current context, so check it mid-demo.
- **ACME (step-ca) and the challenge ports.** The directory is `https://<host>:9000/acme/acme/directory`, and the URLs in it follow the host the client used: `host.k3d.internal` from the cluster, `host.lima.internal` from the VM, `localhost` from your machine. Clients must trust the root (`certs/ca.pem`, or `https://localhost:9000/roots.pem`). The catch is validation: step-ca connects to the domain on port 80 (http-01) or 443 (tls-alpn-01), and the ACME standard allows no other port. So **the k8s cluster owns the host's `:80` and `:443`** (alongside `:8080`/`:8443`), and step-ca resolves exactly one name, `whoami.acme.test`, to the host: that is the domain of `00-security-acme`. It sits outside the wildcard on purpose, because Traefik skips ACME for any name that a certificate it already holds covers (its default one is `*.demo.test`). The VM gateway can't do ACME at the same time (it would need its own `:80`/`:443`), and `:80`/`:443` must be free on your machine. Verified with lego, and with Traefik itself in `00-security-acme`: HTTP-01 issues a certificate from step-ca.
- Keycloak puts `http://localhost:8180` in every token as the issuer, whichever host the client dialled; the VM and the cluster still fetch keys through the host.
- Everything in `shared/` is lab-only: no passwords on Redis, Vault in dev mode (in memory: a restart loses its secrets), ports open on every interface.
- Gitea is `localhost:3000`. Every password in this repo is `Password123`: fine for a lab, nowhere else.
- **The deck:** `./docs.sh` builds `docs/deck.md.m4` into `_site/index.html` (needs `m4`, `yq`, `pandoc` and [mdp2html](https://github.com/laughingbiscuit/mdp2html)). `.github/workflows/pages.yml` does the same on every push to `main` and publishes it to GitHub Pages.

## Disclaimer

This repository and its contents are not an official product.
