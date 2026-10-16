# quick-traefik-demos

GitOps demos of Traefik Hub configuration. The same scenarios run two ways:

| Demo | Traefik config as | Runs on | Synced by |
|---|---|---|---|
| `file-provider/` | Traefik's own YAML (file provider) | a Lima VM (any Linux VM works the same way) | a systemd timer pulling Git every 10s |
| `k8s-providers/` | Kubernetes objects (CRDs; Gateway API later) | a k3d cluster | Flux, every 10s |

Both pull from one repo on a local Gitea, so every change in a demo is a plain `git push`.

## Prerequisites

- Docker, `k3d`, `kubectl`, `flux`, `limactl`, `git`, `curl`, `hurl`
- Your Traefik Hub gateway token in `.env`: `cp .env.example .env`, then fill in `HUB_TOKEN`. `.env` is gitignored, and the scripts never print the token. (An exported `HUB_TOKEN` also works when there is no `.env`.)

## Run it

```bash
./bootstrap-git.sh               # Gitea on :3000, this repo pushed to it as the `gitea` remote
./k8s-providers/k3s-bootstrap.sh  # k3d + Flux + Hub        -> http://localhost:8080
./file-provider/lima-bootstrap.sh # Lima VM + Docker + Hub  -> http://localhost:8000 (dashboard :8001)
```

Run either demo or both. Each takes a few minutes the first time. To rebuild, run `./cleanup.sh` first: a bootstrap stops if its cluster or VM already exists.

## Demo a scenario

You demo in this repo. The demos watch the Gitea copy (remote `gitea`, branch `main`), so a change only takes effect once you push it there with `./sync-git.sh`. Each demo has a list of what is switched on:

- `file-provider/scenarios/enabled.txt`
- `k8s-providers/scenarios/kustomization.yaml`

Uncomment a scenario, then push your working tree to Gitea:

```bash
./sync-git.sh
```

Within about 10 seconds both demos have it. Comment the line out and run it again to remove it.

| Scenario | Try it | You should see |
|---|---|---|
| `00-whoami` | `curl localhost:8080/` | whoami's response (base route, always on) |
| `01-rate-limit` | `for i in $(seq 10); do curl -s -o /dev/null -w '%{http_code} ' localhost:8080/rate-limit; done` | four `200`s, then `429`s |
| `02-caching` | `curl -sI localhost:8080/cache \| grep -i x-cache-status` (twice) | `MISS`, then `HIT` |

Use port `8000` instead of `8080` for the VM demo.

Your changes live in this repo, so `cleanup.sh` never deletes them. It only removes the `gitea` remote and the Gitea container; `bootstrap-git.sh` pushes your working tree to a fresh Gitea.

## Tests

`tests/` has one Hurl file per scenario, named like the scenario (`02-caching.yaml` ↔ `02-caching.hurl`). `test.sh` runs the tests you name against every demo that is running, and exits non-zero if one fails:

```bash
./test.sh tests/00-whoami.hurl tests/01-rate-limit.hurl
```

It retries for up to 20 seconds, so you can run it straight after a push; a genuine failure takes those 20 seconds to report.

## CI

`.github/workflows/ci.yml` runs on every push to GitHub: it builds everything, enables every scenario with a commit pushed to Gitea, and runs every test on both demos. Add your Hub token as a repository secret called `HUB_TOKEN`.

Lima isn't practical on GitHub's hosted runners (the Apple Silicon macOS runners can't run nested VMs), so in CI the Ubuntu runner itself is the VM: the workflow runs `file-provider/vm-provision.sh` on it directly, the same script Lima runs.

## Layout

```
quick-traefik-demos/
├── bootstrap-git.sh          # Gitea, and pushes this repo to it
├── sync-git.sh               # push the working tree to Gitea (no commit needed)
├── test.sh                   # run tests against whichever demos are running
├── cleanup.sh                # remove everything the demos created
├── .github/workflows/ci.yml  # GitHub Actions: build, enable everything, test
├── tests/                    # one Hurl file per scenario, shared by both demos
├── file-provider/
│   ├── lima-bootstrap.sh     # create the Lima VM, run vm-provision.sh on it
│   ├── vm-provision.sh       # any Linux VM: Traefik under systemd, Docker, the Git sync timer
│   └── scenarios/            # what the file-provider demo syncs
│       ├── enabled.txt       # which scenarios Traefik loads
│       ├── static/               # Traefik static config in parts; enabled.txt picks which load
│       ├── stack/compose.yaml   # Docker dependencies: whoami as a stand-in for Redis, Keycloak, ...)
│       └── 00-whoami.yaml, 01-rate-limit.yaml, 02-caching.yaml
└── k8s-providers/
    ├── k3s-bootstrap.sh      # create the k3d cluster, install Flux
    └── scenarios/            # what Flux syncs
        ├── kustomization.yaml   # which scenarios Flux applies
        ├── stack/               # what runs in the cluster: Traefik Hub, whoami
        │   └── kustomization.yaml   # which components Flux installs
        └── 00-whoami.yaml, 01-rate-limit.yaml, 02-caching.yaml
```

`stack/` is what the demo runs on. The numbered files are the Traefik configuration on show.

## Adding things

- **A scenario:** add `03-<name>.yaml` to both `scenarios/` folders (file-provider YAML on one side, CRDs on the other) and `tests/03-<name>.hurl`, and list it.
- **A component** (Keycloak, Redis, ...): add it to `stack/compose.yaml` on the VM (publish its port on 127.0.0.1 for Traefik to reach), or add a manifest to `stack/` and list it in `stack/kustomization.yaml` on Kubernetes.
- **Switching a component off:** comment it out and push, in `stack/compose.yaml` on the VM (`compose up --remove-orphans` removes its container) or in `stack/kustomization.yaml` on Kubernetes (Flux prunes it). The `demo` namespace has its own file, `00-demo-namespace.yaml`: deleting a namespace deletes everything in it, including the scenarios, so keep it on.

## How it works

- **k8s-providers:** Flux has two Kustomizations. `stack` installs Hub through a HelmRelease; the bootstrap waits until it is healthy before creating `scenarios`, which applies whatever `kustomization.yaml` lists. They are split because the scenarios use Traefik's CRDs, which only exist once Hub is installed.
- **file-provider:** every 10s `gitops-sync` on the VM pulls the repo, copies the files listed in `enabled.txt` into the folder Traefik watches, joins the parts listed in `static/enabled.txt` into Traefik's static config, and runs `docker compose up` on `stack/compose.yaml`. Traefik runs as a binary under systemd and hot-reloads the dynamic files; a systemd path unit restarts it when the joined static config changes. Parts are concatenated, so each top-level key (`entryPoints`, `api`, ...) must live in one part only. Compose only runs the dependencies.
- **Other VM platforms:** `vm-provision.sh` is the portable part. Run it as root with `GITOPS_REPO` and `HUB_TOKEN` set, for example from cloud-init. It installs Docker with Docker's install script if it's missing, and copies the Traefik binary out of the Hub image.

## Gotchas

- Both demos share one Hub licence, so they appear as the same gateway. That is fine for these scenarios; use a separate token per gateway before demoing API Management.
- Other tools can switch your current kubectl context at any time. The bootstrap doesn't depend on it (it uses a kubeconfig for `k8s-demo` only), but your own `kubectl` commands do, so check `kubectl config current-context` mid-demo.
- Gitea runs on `localhost:3000` with user `demo` / `Passw0rd!`. That is fine for a lab, but don't reuse it anywhere else.

## Cleanup

```bash
./cleanup.sh
```

It deletes the `k8s-demo` cluster, the `fp-demo` VM, the `gitea` container with its data volume, and your local `gitea` git remote, and nothing else. The next build starts from scratch.

## Disclaimer

This repository and its contents are not an official product.
