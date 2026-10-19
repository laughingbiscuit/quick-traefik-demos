# quick-traefik-demos

A Traefik workshop in chapters, run from one Git repo. Chapter 1 shows a request passing through Traefik on k3d and on a VM. The later chapters stay on k3d. A sanity check, `./demo.sh export`, turns everything k3d runs into Traefik's own YAML files and shows what works on a VM alone.

| Where | Traefik config as | Runs on |
|---|---|---|
| k3d | Kubernetes objects (Ingress, IngressRoute, Gateway API), plus the file provider in the same Traefik | a k3d cluster with Flux |
| VM | Traefik's own YAML files, hot-reloaded | a Linux VM (Lima locally), no Kubernetes |

Every request goes through the same four steps:
**Entrypoint** (the port) → **Router** (matches the request) → **Middleware** (changes it) → **Service** (the backend).
The workshop deck walks through them with the real files from this repo: https://laughingbiscuit.github.io/quick-traefik-demos/

## Layout

```
chapters/NN-name/        one directory per chapter: slides, manifests (or the VM's file-provider YAML) and a test, nothing else
chapters/lib.sh          helpers for a chapter's test.sh
platform/k8s/            the install on k3d: Flux stack with Traefik Hub and whoami
platform/vm/             the install on the VM: static config, provisioning script, and `export.sh` (the sanity check)
shared/                  Docker Compose services the chapters share
```

`platform/` is the install; `chapters/` is what you show.

## Run it

You need Docker, `k3d`, `kubectl`, `flux`, `limactl`, `git`, `curl`, `hurl`, `jq` and `yq`, and an online Traefik Hub gateway token: `cp .env.example .env`, then fill in `HUB_TOKEN`.

```bash
./demo.sh up          # Gitea, the shared services, then k3d (http://localhost:8080) and the VM (http://localhost:8000), on chapter 1
./demo.sh chapter 3   # turn chapters 1 to 3 on in k3d (`all` for every one; the later ones are turned off)
./demo.sh test        # turn the chapters on one at a time, test each while it is the newest on, and smoke-test the shared services
./demo.sh export      # sanity check: run what k3d runs on the VM too, and show what works there
./demo.sh vm-reset    # undo export: the VM goes back to its own hand-written config
./demo.sh clean       # delete it all; run before `up` to rebuild
```

Changed a file? `./demo.sh sync` pushes this working tree to Gitea (no commit needed). Both demos poll Git every 10 seconds, so the change is live within about 20, with no restart: that is the point to show.

The dashboard is **http://localhost:8082/dashboard/** (keep the trailing slash). It belongs to the k3d Traefik and is unauthenticated: lab only. The VM has no dashboard.

## The chapters

| Chapter | Try it | You should see |
|---|---|---|
| 1 `01-passthrough` | `curl -si localhost:8080/passthrough`, then add `?route=ingressroute` or `?route=httproute` | whoami's answer and an `X-Demo-Route` header naming the route that answered: `ingress`, `ingressroute`, `httproute` or `file`. They are four providers in one Traefik (`@kubernetes`, `@kubernetescrd`, `@kubernetesgateway`, `@file`), merged in one dashboard, k3d's. The VM answers `?route=file` on port `8000`, from a hand-written file |
| 2 `02-providers` (k3d only) | `curl -si localhost:8080/passthrough`, then add `?route=ingressroute`, `?route=httproute` or `?route=file`. Open `http://localhost:8082/dashboard/` | The same URL answered by four providers in one Traefik: Ingress, IngressRoute, Gateway API and a file (`X-Demo-Route`: `ingress`, `ingressroute`, `httproute`, `file`), told apart in the dashboard as `@kubernetes`, `@kubernetescrd`, `@kubernetesgateway` and `@file` |
| 3 `03-file-provider` (the VM) | `curl -si 'localhost:8000/passthrough?route=file'` | whoami answering on the VM, with no Kubernetes: Traefik reads one file and reloads it when it changes, with no restart. Static config (entrypoints, providers) is `platform/vm/traefik-static.yaml` |
| 4 `04-proxy` (k3d only) | `curl --cacert certs/ca.pem https://api.traefik-hub.test/` | whoami over HTTPS, with a certificate that Traefik got from step-ca for exactly `api.traefik-hub.test`: see it with `openssl s_client -connect localhost:443 -servername api.traefik-hub.test`. Plain `http://api.traefik-hub.test/` on `:80` gets a 301 to HTTPS, as on a real site. More below |
| 5 `05-api-gateway` | `curl -i localhost:8080/basic-auth`, then `-u demo:Password123` | `401` without the login, whoami with it |
| 6 `06-access-control` (k3d only) | `T=$(curl -s -u partner-a:Password123 -d grant_type=client_credentials localhost:8180/realms/demo/protocol/openid-connect/token \| jq -r .access_token)`, then `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" localhost:8080/orders` and `/payments`. Try `partner-b` and `internal` too | Three OAuth2 clients with equally broad tokens, and the gateway telling them apart: Partner A gets Orders (200) and Payments (403), Partner B the reverse, `internal` both. No token or a bad one is a 401; a good token from a client with no subscription is a 403. It needs API management (switched on in `platform/k8s`) |
| 7 `07-access-control-change` (k3d only) | `./demo.sh chapter 6`, then `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" localhost:8080/payments` with Partner A's token `T` (as in chapter 6); then `./demo.sh chapter 7` and call it again | 403 at chapter 6. Chapter 7 adds one `ManagedSubscription` for Partner A (`chapters/07-access-control-change/manifests.yaml`), which Flux applies, and a second or two later it is 200: same token, nothing changed in Keycloak. `./demo.sh chapter 6` takes it away again |
| 8 `08-token-exchange` (k3d only) | `TOKEN=$(curl -s -d grant_type=password -d client_id=demo-app -d username=demo -d password=Password123 localhost:8180/realms/demo/protocol/openid-connect/token \| jq -r .access_token)`, then `curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/token-exchange` | whoami's answer, with an `Authorization` header that is **not** your token: Traefik traded it at Keycloak (RFC 8693) for one made for the backend (`aud: demo-backend`, `azp: gateway`, same user, no email or roles). Without a token, or with one Keycloak won't exchange, you get a 401. It uses Traefik Hub's `oAuthTokenExchange` middleware, which is early access |
| 9 `09-access-control-users` (k3d only) | `T=$(curl -s -d grant_type=password -d client_id=demo-app -d username=guest -d password=Password123 localhost:8180/realms/demo/protocol/openid-connect/token \| jq -r .access_token)`, then `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" localhost:8080/catalog` and `/admin`. Try `demo` too | People instead of machines, through one application. `demo` (role `admin`) gets Catalog and Admin (200); `guest` gets Catalog (200) and Admin (403). What a person may call comes from the claims in their token (a role), checked by the subscription |
| 10 `10-access-control-oidc` (k3d only) | open `http://localhost:8080/portal` in a browser, and sign in as `demo` or `guest` (password `Password123`) | The gateway runs the login, which is OAuth2's authorization code flow (with PKCE), with OpenID Connect on top for who signed in (ID token, discovery): no session means a redirect to Keycloak. After sign-in the page is told who you are (`X-User`) and gets your access token as a bearer token. The app then calls `/profile` with it: 200 for `demo`, 403 for `guest`. The login and the API are two routes, because on one route the API check runs before the login |

**One Traefik, many providers.** Each provider watches its own source and translates it into Traefik's dynamic configuration; they run at the same time, and every object carries its provider's name (`whoami@file`, `whoami@kubernetescrd`), so nothing collides. The k3d Traefik runs four providers at once (Ingress, IngressRoute, Gateway API and the file provider, switched on in `platform/k8s/00-traefik-hub.yaml`), so its dashboard is the merged view. The VM is another Traefik with one provider (file), and no dashboard: a Traefik's dashboard shows that one instance, not several.

**Chapter 4 in more detail (HTTPS, k3d only):** Traefik terminates TLS on `websecure` (`8443` on your machine) and gets its certificate over ACME from step-ca, then renews it by itself in its last 6 hours, checking every 10 minutes. `./demo.sh shared` only saves step-ca's root certificate to `certs/ca.pem` (gitignored): trust it or pass it with `--cacert`. For the name to resolve, send `*.traefik-hub.test` to `127.0.0.1` in your local DNS, or use `--resolve api.traefik-hub.test:443:127.0.0.1`; the tests use `--resolve`, so CI needs no DNS. Until the first certificate arrives, a TLS client gets a handshake error, not Traefik's self-signed certificate: the chapter turns on `sniStrict` for that.

**Sanity check, everything on a VM alone:** `./demo.sh export` reads the k3d Traefik's `/api/rawdata` (Traefik has already translated every object) with [crd2file](https://github.com/laughingbiscuit/crd2file) (a pinned release, downloaded once and checked against its SHA-256: `CRD2FILE=/path/to/crd2file.sh` uses your own copy), points the services at the VM's whoami, and installs the result on the VM, replacing its hand-written files and stopping its Git sync until `vm-reset`. It is not a migration path (nobody moves from Kubernetes to a VM): it is how to demo every chapter on a VM without writing each one twice, and a check that what worked on k3d runs on a VM. Only **dynamic** config comes across: routers, middlewares, services. **Static** config (entrypoints, certificate resolvers, providers, the licence) is the install: the VM has its own in `platform/vm/traefik-static.yaml`, and a route that needs something from k3d's static config loads but can't work (chapter 2 needs the `websecure` entrypoint and the `step` resolver). Run `export` again after changing chapters. The generated file lands in `platform/vm/generated/` (gitignored: it can hold secrets).

## Add a chapter

A chapter is a directory with at most three files. The number orders the chapters, and `./demo.sh chapter N` turns on 1 to N:

```
chapters/11-rate-limit/
  slides.md          the chapter's slides, for the deck
  manifests.yaml     the Kubernetes objects Flux applies on k3d (all of them, one file)
  test.hurl          the proof, in the order of the slides   (or test.sh: see below)
```

A chapter about the VM has `file-provider.yaml` instead of `manifests.yaml`: Traefik's own YAML, which the VM runs. A chapter
that needs more than this is two chapters: `./docs.sh` fails if one holds any other file. (A `kustomization.yaml` is the one
exception: allowed, and Flux makes one itself when it is missing.)

1. **Where a test runs.** The `test.hurl` of a chapter with `manifests.yaml` (or with no manifests) runs on k3d, and on the VM
   after `export` unless its first lines say `# Kubernetes only: <why>`: `export` prints that reason in its table. The test of
   a chapter with `file-provider.yaml` runs against the VM.
2. **Chapters build on each other.** `./demo.sh test` turns the chapters on one at a time and runs each chapter's test while it is
   the newest one on, so a chapter can change what an earlier one showed: 07 adds the access that 06 shows denied, as a manifest
   Flux applies. Turning a chapter off makes Flux remove what it added.
3. **When it needs a script.** `test.sh` is for what a hurl file cannot do, like keeping two sessions apart (chapter 10). It runs on
   k3d only, after the hurl test, and says why on its second line (`# Kubernetes only: <why>`). Put hurl in it with
   `hurl_inline <label> <<'HURL'` (see `chapters/lib.sh`).
4. Chapters run together, so give your routes their own path prefix or host: two with the same rule collide.
5. A backend it needs (Redis, Keycloak, ...) goes in `shared/compose.yaml`: both reach it through the host. A backend of its own
   goes in the chapter's manifests, or in `platform/` if several chapters share it. On the VM it is a systemd unit in
   `platform/vm/vm-provision.sh` (see `whoami`).
6. Slides show the chapter's real files with `m4_esyscmd` / `m4_include` (see `chapters/06-access-control/slides.md`), with the
   file's path written above the block: `./docs.sh` fails if a slide names a file that does not exist. Paths are from the repo
   root. Begin `slides.md` with a `---` line, and keep it free of "chapter N" and of references to other chapters' slides: the deck
   is assembled per customer, so every chapter's slides must stand alone.

## Shared services

Docker Compose runs Gitea and the dependencies the chapters share, on the host (`shared/compose.yaml`). **Every login is `demo` / `Password123`**: Gitea, Keycloak (and its console), chapter 3 (basic auth), step-ca's provisioner password and Vault's token. (`guest` in Keycloak has the same password but no `admin` role.) The VM reaches them at `host.lima.internal:<port>`, k8s at `host.k3d.internal:<port>`, you at `localhost:<port>`. They configure themselves headlessly on start.

| Service | Port | What it is for | Login |
|---|---|---|---|
| Grafana LGTM | `3001` (Grafana), `4317`/`4318` (OTLP) | metrics, logs and traces in one place | none |
| Redis | `6379` | distributed rate limiting, shared state | none |
| Keycloak | `8180` | OIDC. Realm `demo`, users `demo` (role `admin`) and `guest` (no role). Clients: `traefik` (secret `Password123`); for token exchange, `demo-app` (public, signs users in with a password grant), `gateway` (secret `Password123`, token exchange switched on) and `demo-backend` (only an audience). For API access control, service-account clients `partner-a`, `partner-b`, `internal` and `partner-short-lived` (tokens last 2 seconds), all with secret `Password123`, and the same broad `all-services` scope: they stand in for a customer's identity provider. Also on HTTPS, `8543`, with a certificate made at start | `demo` / `Password123`, for the realm and the console |
| step-ca | `9000` (HTTPS) | PKI and ACME: root and intermediate CA, and the ACME directory at `/acme/acme/directory` that Traefik gets its certificates from (see Gotchas for the challenge ports). Its CA lasts until `clean` | provisioner `admin`, password `Password123` |
| Vault | `8200` | secrets management: KV at `secret/` | token `Password123` |
| OPA | none | `shared/opa/authz.rego`: gateways evaluate it themselves, `./demo.sh test` checks it with `opa test` | |
| Ollama | `11434` | local LLM for the AI Gateway. No model is pulled yet: a chapter that needs one runs `docker compose -p shared -f shared/compose.yaml exec ollama ollama pull <model>` | none |
| Toxiproxy | `8474` (API) | latency and failures in front of Redis (`6380`) and the demo API (`9111`, `9112`). Proxies: `shared/toxiproxy/toxiproxy.json` | none |
| Gitea MCP | `8081` | MCP tools for the Gitea repo and issues, at `POST /mcp`. The caller brings the token: `Authorization: Bearer <Gitea access token>` | none |

The demo API (`api-v1` and `api-v2`, whoami named per version, on `9101` and `9102`) and a traffic generator that sends `/passthrough?route=file` (the one route both answer) to both gateways run too: `K8S_WEIGHT=80 URL_PATH=/other ./demo.sh shared` changes where the traffic goes.

`./demo.sh smoke` checks all of them (the traffic generator needs both gateways up). `./demo.sh shared` starts or updates them on their own, and `clean` removes them.

## How it works

- **VM:** every 10 seconds `gitops-sync` pulls Git, copies every chapter's `file-provider.yaml` into the folder Traefik watches (hot-reloaded, no restart), and installs `platform/vm/traefik-static.yaml` (static: Traefik restarts only when it changes). Traefik Hub and the `whoami` backend (port `9500`) are plain binaries from GitHub releases under systemd, with no Docker on the VM. `platform/vm/vm-provision.sh` does all of it on any Linux VM: run it as root with `GITOPS_REPO` and `HUB_TOKEN`. `export` stops this sync, `vm-reset` starts it again.
- **k3d:** Flux applies `platform/k8s/` (Traefik Hub, whoami) first, then one Kustomization per chapter (`chapter-01-passthrough`, ...) that depends on it, because the chapters need the CRDs that Traefik's install brings. `./demo.sh chapter N` creates the ones up to N and deletes the rest. The Traefik dashboard and API are exposed on `:8082` (the `traefik` entrypoint: `ingressRoute.dashboard` and `ports.traefik.expose` in the Helm values): `./demo.sh export` reads `/api/rawdata` there.
- **CI** (`.github/workflows/ci.yml`) builds both demos, turns every chapter on, runs every test, then runs `export` and tests the VM on that config, on each push. It needs the token as a repository secret `HUB_TOKEN`. The Ubuntu runner plays the VM: it runs `vm-provision.sh` directly instead of Lima (`VM_LOCAL=1` makes `demo.sh` use sudo for the VM steps).

## Gotchas

- **Online token only, for now.** An offline licence makes Hub on the VM exit with "offline mode configuration mismatch" (it needs `hub.offline: true`). The air-gapped setup will be its own chapter with its own token variable.
- Both demos use the same licence, so they show up as one gateway. Use a token per gateway before demoing API Management.
- `./demo.sh k8s` uses its own kubeconfig for `k8s-demo`; your own `kubectl` uses your current context, so check it mid-demo.
- **ACME (step-ca) and the challenge ports.** The directory is `https://<host>:9000/acme/acme/directory`, and the URLs in it follow the host the client used: `host.k3d.internal` from the cluster, `host.lima.internal` from the VM, `localhost` from your machine. Clients must trust the root (`certs/ca.pem`, or `https://localhost:9000/roots.pem`). The catch is validation: step-ca connects to the domain on port 80 (http-01) or 443 (tls-alpn-01), and the ACME standard allows no other port. So **the k3d cluster owns the host's `:80` and `:443`** (alongside `:8080`/`:8443`), they must be free on your machine, and step-ca resolves exactly one name, `api.traefik-hub.test`, to the host. The VM can't do ACME at the same time (it would need its own `:80`/`:443`), so it has no TLS. No certificate is pre-issued, on purpose: Traefik skips ACME for any name that a certificate it already holds covers, so one would hide the demo, and a working HTTPS request proves ACME worked.
- Keycloak puts `http://localhost:8180` in every token as the issuer, whichever host the client dialled; the VM and the cluster still fetch keys through the host.
- Keycloak reads `shared/keycloak/*-realm.json` only on a fresh start. After editing one, recreate the container: `docker compose -p shared -f shared/compose.yaml up -d --force-recreate keycloak`. This realm lists its own `clientScopes`, so Keycloak's built-in ones (`profile`, `email`, `roles`) are not created: a client that needs such a claim carries its own mapper (see `demo-app`).
- **API access control (chapters 6, 7, 9 and 10) uses Hub's API management objects, which need the internet and an HTTPS key source.** Hub registers each `API` with the Hub platform when it is applied, so the webhook fails offline. It also fetches a token issuer's keys over HTTPS only (plain `http://` is refused when you apply the `APIAuth`), so Keycloak serves HTTPS with a self-signed certificate made on every start, and the `APIAuth` skips verifying it: lab only, an issuer in production has a certificate Hub trusts. Operation-level access (GET versus POST) needs an OpenAPI document for the API, which the whoami backends do not serve. The OIDC login (chapter 10) needs `trustedIssuer` because the gateway reaches Keycloak at `host.k3d.internal` while tokens and the browser say `localhost`.
- Everything in `shared/` is lab-only: no passwords on Redis, Vault in dev mode (in memory: a restart loses its secrets), ports open on every interface.
- Gitea is `localhost:3000`. Every password in this repo is `Password123`: fine for a lab, nowhere else.
- **The deck:** `./docs.sh` builds `docs/deck.md.m4` plus every chapter's `slides.md`, in order, into `_site/index.html`. For one customer, name the chapters you want, in the order you want: `./docs.sh api-gateway passthrough` (a directory name like `03-api-gateway` works too). Needs `m4`, `yq`, `pandoc` and [mdp2html](https://github.com/laughingbiscuit/mdp2html). `.github/workflows/pages.yml` builds the full deck on every push to `main` and publishes it to GitHub Pages.

## Disclaimer

This repository and its contents are not an official product.
