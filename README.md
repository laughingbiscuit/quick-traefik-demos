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
./demo.sh up      # Gitea, then k8s on http://localhost:8080 and the VM on http://localhost:8000
./demo.sh test    # run every test against both demos
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

Use port `8000` for the VM. The VM's dashboard is at http://localhost:8001/dashboard/.

## Add a scenario

1. `file-provider/scenarios/01-<name>.yaml` and `k8s-providers/scenarios/01-<name>*.yaml`, listed in `enabled.txt` / `kustomization.yaml`.
2. `tests/01-<name>.hurl`. It runs against both demos, so where they answer differently, accept either (see `X-Route` in `tests/00-passthrough.hurl`).
3. A backend it needs (Redis, Keycloak, ...) goes in `file-provider/stack/compose.yaml` and `k8s-providers/stack/`.

`stack/` and `file-provider/traefik-static.yaml` are the install; `scenarios/` is what you show.

## How it works

- **VM:** every 10 seconds `gitops-sync` pulls Git, copies `dashboard.yaml` and the enabled scenarios into the folder Traefik watches (hot-reloaded, no restart), installs `traefik-static.yaml` (static: Traefik restarts only when it changes) and runs `docker compose up` for the backends. Traefik itself is a plain binary under systemd. `file-provider/vm-provision.sh` does all of it on any Linux VM: run it as root with `GITOPS_REPO` and `HUB_TOKEN`.
- **Kubernetes:** Flux applies `k8s-providers/stack/` (Traefik Hub, whoami), then `k8s-providers/scenarios/`. They are separate because the scenarios need the CRDs that Traefik's install brings.
- **CI** (`.github/workflows/ci.yml`) builds both demos, enables every scenario and runs every test, on each push. It needs the token as a repository secret `HUB_TOKEN`. The Ubuntu runner plays the VM: it runs `vm-provision.sh` directly instead of Lima.

## Gotchas

- **Online token only, for now.** An offline licence makes Hub on the VM exit with "offline mode configuration mismatch" (it needs `hub.offline: true`). The air-gapped setup will be its own scenario with its own token variable.
- Both demos use the same licence, so they show up as one gateway. Use a token per gateway before demoing API Management.
- `./demo.sh k8s` uses its own kubeconfig for `k8s-demo`; your own `kubectl` uses your current context, so check it mid-demo.
- Gitea is `localhost:3000`, user `demo` / `Passw0rd!`: fine for a lab, nowhere else.
- **The deck:** `./docs.sh` builds `docs/deck.md.m4` into `_site/index.html` (needs `m4`, `yq`, `pandoc` and [mdp2html](https://github.com/laughingbiscuit/mdp2html)). `.github/workflows/pages.yml` does the same on every push to `main` and publishes it to GitHub Pages.

## Disclaimer

This repository and its contents are not an official product.
