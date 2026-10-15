# quick-traefik-demos

GitOps demos of Traefik Hub configuration. The same scenarios run two ways:

| Demo | Traefik config as | Runs on | Synced by |
|---|---|---|---|
| `file-provider/` | Traefik's own YAML (file provider) | a VM: Lima here; SUSE, Nutanix or VMware the same way | a systemd timer pulling Git every 10s |
| `k8s-providers/` | Kubernetes objects (CRDs; Gateway API later) | a k3d cluster | Flux, every 10s |

Both pull from one repo on a local Gitea, so every change in a demo is a plain `git push`.

## Prerequisites

- Docker, `k3d`, `kubectl`, `flux`, `limactl`, `git`, `curl`, `hurl`
- Your Traefik Hub gateway token in `.env`: `cp .env.example .env`, then fill in `HUB_TOKEN`. `.env` is gitignored, and the scripts never print the token. (An exported `HUB_TOKEN` also works when there is no `.env`.)

## Run it

```bash
./bootstrap-git.sh               # Gitea on :3000, and its repo cloned into gitops-demo-repo/
./k8s-providers/bootstrap.sh     # k3d + Flux + Hub        -> http://localhost:8080
./file-provider/bootstrap.sh     # Lima VM + Docker + Hub  -> http://localhost:8000 (dashboard :8001)
```

Run either demo or both. Each takes a few minutes the first time. To rebuild, run `./cleanup.sh` first: a bootstrap stops if its cluster or VM already exists.

## Demo a scenario

You demo in `gitops-demo-repo/`, a clone of the Gitea repo. Each demo has a list of what is switched on:

- `gitops-demo-repo/file-provider/enabled.txt`
- `gitops-demo-repo/k8s-providers/kustomization.yaml`

Uncomment a scenario, then push it like any Git change:

```bash
cd gitops-demo-repo
git commit -am "Enable caching" && git push
```

Within about 10 seconds both demos have it. Comment the line out and push again to remove it.

| Scenario | Try it | You should see |
|---|---|---|
| `00-whoami` | `curl localhost:8080/` | whoami's response (base route, always on) |
| `01-rate-limit` | `for i in $(seq 10); do curl -s -o /dev/null -w '%{http_code} ' localhost:8080/rate-limit; done` | four `200`s, then `429`s |
| `02-caching` | `curl -sI localhost:8080/cache \| grep -i x-cache-status` (twice) | `MISS`, then `HIT` |

Use port `8000` instead of `8080` for the VM demo.

`gitops-demo-repo/` is a throwaway working copy: `bootstrap-git.sh` seeds it from the `scenarios/` folders in this repo, and `cleanup.sh` deletes it. To keep a change, make it in `scenarios/` too.

## Tests

`tests/` has one Hurl file per scenario, named like the scenario (`02-caching.yaml` ↔ `02-caching.hurl`). `test.sh` runs the tests you name against every demo that is running, and exits non-zero if one fails:

```bash
./test.sh tests/00-whoami.hurl tests/01-rate-limit.hurl
```

It retries for up to 20 seconds, so you can run it straight after a push; a genuine failure takes those 20 seconds to report.

## CI

`.github/workflows/ci.yml` runs on every push to GitHub: it builds everything, enables every scenario with a commit in `gitops-demo-repo/`, and runs every test on both demos. Add your Hub token as a repository secret called `HUB_TOKEN`.

Lima isn't practical on GitHub's hosted runners (the Apple Silicon macOS runners can't run nested VMs), so in CI the Ubuntu runner itself is the VM: the workflow runs `file-provider/provision.sh` on it directly, the same script Lima runs.

## Layout

```
quick-traefik-demos/
├── bootstrap-git.sh          # Gitea + the gitops-demo-repo/ working copy
├── test.sh                   # run tests against whichever demos are running
├── cleanup.sh                # remove everything the demos created
├── .github/workflows/ci.yml  # GitHub Actions: build, enable everything, test
├── tests/                    # one Hurl file per scenario, shared by both demos
├── file-provider/
│   ├── bootstrap.sh          # create the Lima VM, run provision.sh on it
│   ├── provision.sh          # any Linux VM: Docker + the Git sync timer
│   └── scenarios/            # template for gitops-demo-repo/file-provider/
│       ├── enabled.txt       # which scenarios Traefik loads
│       ├── stack/compose.yaml   # what runs on the VM: Traefik Hub, whoami
│       └── 00-whoami.yaml, 01-rate-limit.yaml, 02-caching.yaml
└── k8s-providers/
    ├── bootstrap.sh          # create the k3d cluster, install Flux
    └── scenarios/            # template for gitops-demo-repo/k8s-providers/
        ├── kustomization.yaml   # which scenarios Flux applies
        ├── stack/               # what runs in the cluster: Traefik Hub, whoami
        │   └── kustomization.yaml   # which components Flux installs
        └── 00-whoami.yaml, 01-rate-limit.yaml, 02-caching.yaml
```

`stack/` is what the demo runs on. The numbered files are the Traefik configuration on show.

## Adding things

- **A scenario:** add `03-<name>.yaml` to both `scenarios/` folders (file-provider YAML on one side, CRDs on the other) and `tests/03-<name>.hurl`, and list it.
- **A component** (Keycloak, Redis, ...): add it to `stack/compose.yaml` on the VM, or add a manifest to `stack/` and list it in `stack/kustomization.yaml` on Kubernetes.
- **Switching a component off:** comment it out and push, in `stack/compose.yaml` on the VM (`compose up --remove-orphans` removes its container) or in `stack/kustomization.yaml` on Kubernetes (Flux prunes it). The `demo` namespace has its own file, `00-demo-namespace.yaml`: deleting a namespace deletes everything in it, including the scenarios, so keep it on.

## How it works

- **k8s-providers:** Flux has two Kustomizations. `stack` installs Hub through a HelmRelease; the bootstrap waits until it is healthy before creating `scenarios`, which applies whatever `kustomization.yaml` lists. They are split because the scenarios use Traefik's CRDs, which only exist once Hub is installed.
- **file-provider:** every 10s `gitops-sync` on the VM pulls the repo, copies the files listed in `enabled.txt` into the folder Traefik watches, and runs `docker compose up` on `stack/compose.yaml`. Traefik hot-reloads the files; compose only recreates containers whose definition changed. Traefik's static config is kept as flags in `compose.yaml`, so changing it restarts Traefik automatically.
- **Other VM platforms:** `provision.sh` is the portable part. Run it as root with `GITOPS_REPO` and `HUB_TOKEN` set, for example from cloud-init. It uses `zypper` on SUSE and Docker's install script elsewhere. The `z` on Traefik's volume in `compose.yaml` lets it read its config on SELinux hosts such as SUSE.

## Gotchas

- Both demos share one Hub licence, so they appear as the same gateway. That is fine for these scenarios; use a separate token per gateway before demoing API Management.
- Other tools can switch your current kubectl context at any time. The bootstrap doesn't depend on it (it uses a kubeconfig for `k8s-demo` only), but your own `kubectl` commands do, so check `kubectl config current-context` mid-demo.
- Gitea runs on `localhost:3000` with user `demo` / `Passw0rd!`. That is fine for a lab, but don't reuse it anywhere else.

## Cleanup

```bash
./cleanup.sh
```

It deletes the `k8s-demo` cluster, the `fp-demo` VM, the `gitea` container with its data volume, and the `gitops-demo-repo/` working copy, and nothing else. The next build starts from scratch.

## Disclaimer

This repository and its contents are not an official product.
