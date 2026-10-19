# quick-traefik-demos

A Traefik workshop in five chapters, run from one Git repo. Chapter 1 shows a request passing through Traefik on k3d and on a VM. Chapters 2 to 4 stay on k3d. Chapter 5 turns what k3d runs into Traefik's own YAML files and shows what works on the VM.

| Where | Traefik config as | Runs on |
|---|---|---|
| k3d | Kubernetes objects (Ingress, IngressRoute, Gateway API), plus the file provider in the same Traefik | a k3d cluster with Flux |
| VM | Traefik's own YAML files, hot-reloaded | a Linux VM (Lima locally), no Kubernetes |

Every request goes through the same four steps:
**Entrypoint** (the port) → **Router** (matches the request) → **Middleware** (changes it) → **Service** (the backend).
The workshop deck walks through them with the real files from this repo: https://laughingbiscuit.github.io/quick-traefik-demos/

## Layout

```
chapters/NN-name/k8s/    what Flux applies on k3d (from chapter N on)
chapters/NN-name/vm/     hand-written file-provider config for the VM, and the tests that pass on it (chapter 1 only)
chapters/NN-name/tests/  hurl tests: they run on k3d, and on the VM after `export` (*.k8s.hurl: k3d only)
chapters/05-to-the-vm/   crd2file.sh and export.sh
platform/k8s/            the install on k3d: Flux stack with Traefik Hub and whoami
platform/vm/             the install on the VM: static config, provisioning script
shared/                  Docker Compose services the chapters share
```

`platform/` is the install; `chapters/` is what you show.

## Run it

You need Docker, `k3d`, `kubectl`, `flux`, `limactl`, `git`, `curl`, `hurl`, `jq` and `yq`, and an online Traefik Hub gateway token: `cp .env.example .env`, then fill in `HUB_TOKEN`.

```bash
./demo.sh up          # Gitea, the shared services, then k3d (http://localhost:8080) and the VM (http://localhost:8000), on chapter 1
./demo.sh chapter 3   # turn chapters 1 to 3 on in k3d (`all` for every one; the later ones are turned off)
./demo.sh test        # run the tests of the chapters that are on, and smoke-test the shared services
./demo.sh export      # chapter 5: run k3d's config on the VM, and show what works there
./demo.sh vm-reset    # undo export: the VM goes back to its own hand-written config
./demo.sh clean       # delete it all; run before `up` to rebuild
```

Changed a file? `./demo.sh sync` pushes this working tree to Gitea (no commit needed). Both demos poll Git every 10 seconds, so the change is live within about 20, with no restart: that is the point to show.

The dashboard is **http://localhost:8082/dashboard/** (keep the trailing slash). It belongs to the k3d Traefik and is unauthenticated: lab only. The VM has no dashboard.

## The chapters

| Chapter | Try it | You should see |
|---|---|---|
| 1 `01-passthrough` | `curl -si localhost:8080/passthrough`, then add `?route=ingressroute`, `?route=httproute` or `?route=file` | whoami's answer and an `X-Demo-Route` header naming the route that answered: `ingress`, `ingressroute`, `httproute` or `file`. They are four providers in one Traefik (`@kubernetes`, `@kubernetescrd`, `@kubernetesgateway`, `@file`), merged in one dashboard, k3d's. The VM answers `?route=file` on port `8000`, from a hand-written file |
| 2 `02-proxy` (k3d only) | `curl --cacert certs/ca.pem https://api.traefik-hub.test/` (with `*.traefik-hub.test` going to `127.0.0.1`, or add `--resolve api.traefik-hub.test:443:127.0.0.1`) | whoami over HTTPS with a certificate that Traefik got from step-ca for exactly `api.traefik-hub.test`: see it with `openssl s_client -connect localhost:443 -servername api.traefik-hub.test`. Traefik renews it by itself in its last 6 hours, checking every 10 minutes. Plain `http://api.traefik-hub.test/` on `:80` gets a 301 to HTTPS, as on a real site. It needs `:80` and `:443` free on your machine |
| 3 `03-api-gateway` | `curl -i localhost:8080/basic-auth`, then `-u demo:Password123` | `401` without the login, whoami with it |
| 4 `04-api-management` | | a placeholder: API management is k3d only (Traefik Hub's API objects) |
| 5 `05-to-the-vm` | `./demo.sh export` | the VM now runs what k3d runs. The table `export` prints shows which tests pass on the VM and which don't (see below) |

**One Traefik, many providers.** Each provider watches its own source and translates it into Traefik's dynamic configuration; they run at the same time, and every object carries its provider's name (`whoami@file`, `whoami@kubernetescrd`), so nothing collides. The k3d Traefik runs four providers at once (Ingress, IngressRoute, Gateway API and the file provider, switched on in `platform/k8s/00-traefik-hub.yaml`), so its dashboard is the merged view. The VM is another Traefik with one provider (file), and no dashboard: a Traefik's dashboard shows that one instance, not several.

**HTTPS (chapter 2, k3d only):** Traefik terminates TLS on `websecure`, `8443` on your machine, and gets every certificate itself from step-ca over ACME: nothing is pre-issued, so a working HTTPS request proves ACME worked. `./demo.sh shared` only saves step-ca's root certificate to `certs/ca.pem` (gitignored): trust it or pass it, `curl --cacert certs/ca.pem https://api.traefik-hub.test/`. A local DNS entry sending `api.traefik-hub.test` to `127.0.0.1` makes the name resolve; the tests use `--resolve`, so CI needs none. Until the first certificate arrives, a TLS client gets a handshake error, not Traefik's self-signed certificate: chapter 2 turns on `sniStrict` for that. step-ca keeps its CA until `clean`.

**Chapter 5, k3d to the VM:** `./demo.sh export` reads the k3d Traefik's `/api/rawdata` (Traefik has already translated every object) with `chapters/05-to-the-vm/crd2file.sh`, points the services at the VM's whoami, and installs the result on the VM, replacing its hand-written files and stopping its Git sync until `vm-reset`. It is a shortcut for the demo, not a way to run the VM. Only **dynamic** config comes across: routers, middlewares, services. **Static** config (entrypoints, certificate resolvers, providers, the licence) is the install: the VM has its own in `platform/vm/traefik-static.yaml`, and a route that needs something from k3d's static config loads but can't work (chapter 2 needs the `websecure` entrypoint and the `step` resolver). Run `export` again after changing chapters. The generated file lands in `chapters/05-to-the-vm/generated/` (gitignored: it can hold secrets).

## Add to a chapter

1. `chapters/NN-<name>/k8s/<name>.yaml`, listed in that chapter's `k8s/kustomization.yaml` (a new chapter needs one, and `./demo.sh chapter` finds it).
2. `chapters/NN-<name>/tests/<name>.hurl`. It runs on k3d and, after `export`, on the VM. If it can only work on k3d, name it `<name>.k8s.hurl` and start it with a `# Kubernetes only: <why>` line: `export` prints that line in its table.
3. A backend it needs (Redis, Keycloak, ...) goes in `shared/compose.yaml`: both reach it through the host. A backend of its own goes in `platform/k8s/`, or on the VM as a systemd unit in `platform/vm/vm-provision.sh` (see `whoami`).
4. Hand-written VM config, if the chapter has any, goes in `chapters/NN-<name>/vm/`, with a `.hurl` next to it that the hand-written config passes.

## Shared services

Docker Compose runs Gitea and the dependencies the chapters share, on the host (`shared/compose.yaml`). **Every login is `demo` / `Password123`**: Gitea, Keycloak (and its console), chapter 3 (basic auth), step-ca's provisioner password and Vault's token. (`guest` in Keycloak has the same password but no `admin` role.) The VM reaches them at `host.lima.internal:<port>`, k8s at `host.k3d.internal:<port>`, you at `localhost:<port>`. They configure themselves headlessly on start.

| Service | Port | What it is for | Login |
|---|---|---|---|
| Grafana LGTM | `3001` (Grafana), `4317`/`4318` (OTLP) | metrics, logs and traces in one place | none |
| Redis | `6379` | distributed rate limiting, shared state | none |
| Keycloak | `8180` | OIDC. Realm `demo`, client `traefik` (secret `Password123`), users `demo` (role `admin`) and `guest` (no role) | `demo` / `Password123`, for the realm and the console |
| step-ca | `9000` (HTTPS) | PKI and ACME: root and intermediate CA, and the ACME directory at `/acme/acme/directory` that Traefik gets its certificates from (see Gotchas for the challenge ports) | provisioner `admin`, password `Password123` |
| Vault | `8200` | secrets management: KV at `secret/` | token `Password123` |
| OPA | none | `shared/opa/authz.rego`: gateways evaluate it themselves, `./demo.sh test` checks it with `opa test` | |
| Ollama | `11434` | local LLM for the AI Gateway. Pulls `qwen2.5:0.5b`; set `OLLAMA_MODEL` to change it | none |
| Toxiproxy | `8474` (API) | latency and failures in front of Redis (`6380`) and the demo API (`9111`, `9112`). Proxies: `shared/toxiproxy/toxiproxy.json` | none |
| Gitea MCP | `8081` | MCP tools for the Gitea repo and issues, at `POST /mcp`. The caller brings the token: `Authorization: Bearer <Gitea access token>` | none |

The demo API (`api-v1` and `api-v2`, whoami named per version, on `9101` and `9102`) and a traffic generator that sends `/passthrough?route=file` (the one route both answer) to both gateways run too: `K8S_WEIGHT=80 URL_PATH=/other ./demo.sh shared` changes where the traffic goes.

`./demo.sh smoke` checks all of them (the traffic generator needs both gateways up). `./demo.sh shared` starts or updates them on their own, and `clean` removes them.

## How it works

- **VM:** every 10 seconds `gitops-sync` pulls Git, copies every chapter's `vm/*.yaml` into the folder Traefik watches (hot-reloaded, no restart), and installs `platform/vm/traefik-static.yaml` (static: Traefik restarts only when it changes). Traefik Hub and the `whoami` backend (port `9500`) are plain binaries from GitHub releases under systemd, with no Docker on the VM. `platform/vm/vm-provision.sh` does all of it on any Linux VM: run it as root with `GITOPS_REPO` and `HUB_TOKEN`. `export` stops this sync, `vm-reset` starts it again.
- **k3d:** Flux applies `platform/k8s/` (Traefik Hub, whoami) first, then one Kustomization per chapter (`chapter-01-passthrough`, ...) that depends on it, because the chapters need the CRDs that Traefik's install brings. `./demo.sh chapter N` creates the ones up to N and deletes the rest. The Traefik dashboard and API are exposed on `:8082` (the `traefik` entrypoint: `ingressRoute.dashboard` and `ports.traefik.expose` in the Helm values): chapter 5 reads `/api/rawdata` there.
- **CI** (`.github/workflows/ci.yml`) builds both demos, turns every chapter on, runs every test, then runs `export` and tests the VM on that config, on each push. It needs the token as a repository secret `HUB_TOKEN`. The Ubuntu runner plays the VM: it runs `vm-provision.sh` directly instead of Lima (`VM_LOCAL=1` makes `demo.sh` use sudo for the VM steps).

## Gotchas

- **Online token only, for now.** An offline licence makes Hub on the VM exit with "offline mode configuration mismatch" (it needs `hub.offline: true`). The air-gapped setup will be its own chapter with its own token variable.
- Both demos use the same licence, so they show up as one gateway. Use a token per gateway before demoing API Management.
- `./demo.sh k8s` uses its own kubeconfig for `k8s-demo`; your own `kubectl` uses your current context, so check it mid-demo.
- **ACME (step-ca) and the challenge ports.** The directory is `https://<host>:9000/acme/acme/directory`, and the URLs in it follow the host the client used: `host.k3d.internal` from the cluster, `host.lima.internal` from the VM, `localhost` from your machine. Clients must trust the root (`certs/ca.pem`, or `https://localhost:9000/roots.pem`). The catch is validation: step-ca connects to the domain on port 80 (http-01) or 443 (tls-alpn-01), and the ACME standard allows no other port. So **the k8s cluster owns the host's `:80` and `:443`** (alongside `:8080`/`:8443`), and step-ca resolves exactly one name, `api.traefik-hub.test`, to the host: that is the domain of chapter 2. There is no pre-issued certificate on purpose: Traefik skips ACME for any name that a certificate it already holds covers, so one would hide the demo. The VM can't do ACME at the same time (it would need its own `:80`/`:443`), so it has no TLS, and `:80`/`:443` must be free on your machine. Verified with lego, and with Traefik itself in chapter 2: HTTP-01 issues a certificate from step-ca.
- Keycloak puts `http://localhost:8180` in every token as the issuer, whichever host the client dialled; the VM and the cluster still fetch keys through the host.
- Everything in `shared/` is lab-only: no passwords on Redis, Vault in dev mode (in memory: a restart loses its secrets), ports open on every interface.
- Gitea is `localhost:3000`. Every password in this repo is `Password123`: fine for a lab, nowhere else.
- **The deck:** `./docs.sh` builds `docs/deck.md.m4` into `_site/index.html` (needs `m4`, `yq`, `pandoc` and [mdp2html](https://github.com/laughingbiscuit/mdp2html)). `.github/workflows/pages.yml` does the same on every push to `main` and publishes it to GitHub Pages.

## Disclaimer

This repository and its contents are not an official product.
