#!/bin/sh
# One entry point for the whole workshop (chapters/ has the content, platform/ the installs):
#   ./demo.sh up        Gitea and the shared services, then k3d (:8080, HTTPS :8443, dashboard :8082) and the VM (:8000, no dashboard), on chapter 1
#   ./demo.sh chapter N turn chapters 1..N on in k3d (`all` for every one), and the later ones off
#   ./demo.sh sync      push this working tree to Gitea: k3d and the VM pick it up within ~20s
#   ./demo.sh export    sanity check: turn what k3d runs into file-provider YAML, run that on the VM, and show what works there
#   ./demo.sh vm-reset  undo `export`: the VM goes back to its own hand-written config
#   ./demo.sh test      run the tests of the enabled chapters (or the files you name), plus the shared services' smoke tests
#   ./demo.sh smoke     just the smoke tests of the shared services
#   ./demo.sh clean     delete everything the demos created (your changes stay in this repo)
#   ./demo.sh rebuild   clean, up, every chapter, test and export in one: a from-scratch check that everything works
# `up` runs the steps `git`, `shared`, `k8s` and `vm`, which you can also run one at a time.
# VM_LOCAL=1 means this machine is the VM (CI): `export` and `test` then use sudo instead of Lima.
set -e
cd "$(dirname "$0")"
[ -f .env ] && . ./.env

# --- Where things are ---------------------------------------------------------------------------------------------
K3D=k8s-demo                                # the k3d cluster; its kubeconfig context is k3d-$K3D
K3D_HTTP=8080 K3D_HTTPS=8443 K3D_API=8082   # on your machine: web, websecure, and the dashboard and API (see platform/k8s)
VM=fp-demo                                  # the Lima VM
VM_HTTP=8000 VM_PING=8001                   # on your machine: demo traffic, and /ping (the VM has no dashboard)
VM_BACKEND=http://localhost:9500            # whoami as the VM sees it: what `export` points the services at
GITEA=http://demo:Password123@localhost:3000/demo/gitops.git
if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"; else COMPOSE=docker-compose; fi   # Homebrew's docker has no plugin
SHARED="$COMPOSE -p shared -f shared/compose.yaml"

# --- Small helpers ------------------------------------------------------------------------------------------------
wait_for() {   # <seconds> <url> <hint>: poll until the URL answers, or give up
  i=0
  until curl -skf -o /dev/null "$2"; do
    i=$((i+2)); [ $i -lt "$1" ] || { echo "No answer from $2 after $1s: $3"; exit 1; }
    sleep 2
  done
}

kube() { KUBECONFIG=$(k3d kubeconfig write $K3D) && export KUBECONFIG; }   # immune to other tools switching context

vm_sudo() {   # run as root on the VM: the Lima VM, or this machine with VM_LOCAL=1
  if [ -n "${VM_LOCAL:-}" ]; then sudo "$@"; else limactl shell $VM sudo "$@"; fi
}

need_ca() { [ -f certs/ca.pem ] || { echo "No certs/ca.pem: run ./demo.sh shared first"; exit 1; }; }

need_token() { : "${HUB_TOKEN:?set HUB_TOKEN in .env (copy .env.example)}"; }

# --- Setting up: git, shared, k8s, vm -----------------------------------------------------------------------------
git_up() {   # Gitea on :3000, with this repo pushed to it as the `gitea` remote
  set -x
  $SHARED up -d --wait --quiet-pull gitea
  $SHARED exec -T -u git gitea gitea admin user create --admin --username demo --password 'Password123' \
    --email demo@example.com --must-change-password=false
  curl -fsu demo:'Password123' -o /dev/null -H 'Content-Type: application/json' \
    -d '{"name":"gitops","default_branch":"main"}' http://localhost:3000/api/v1/user/repos
  git remote remove gitea 2>/dev/null || true
  git remote add gitea "$GITEA"
  set +x
  sync
}

sync() {   # push the working tree as it is (committed or not) to Gitea's main, via a throwaway commit
  idx=$(mktemp -u)
  tree=$(GIT_INDEX_FILE=$idx sh -c 'git add -A && git write-tree')
  rm -f "$idx"
  commit=$(git -c user.name=demo -c user.email=demo@example.com commit-tree "$tree" -p HEAD -m "Working tree snapshot")
  git push --force -q gitea "$commit:refs/heads/main"
}

fetch_ca() {   # step-ca's root certificate into certs/: what Traefik and your client trust. No certificate is issued here, Traefik asks for its own over ACME
  mkdir -p certs
  $SHARED exec -T step-ca cat /home/step/certs/root_ca.crt > certs/ca.pem
}

shared_up() {   # everything in shared/compose.yaml: Gitea is already up from `git`, the rest starts here
  set -x
  $SHARED up -d --quiet-pull
  set +x
  wait_for 120 http://localhost:3001/api/health "$SHARED logs lgtm"
  wait_for 120 http://localhost:8180/realms/demo "$SHARED logs keycloak"
  wait_for 120 https://localhost:9000/health "$SHARED logs step-ca"
  fetch_ca
  echo "Grafana http://localhost:3001  Keycloak http://localhost:8180  Vault http://localhost:8200  (login for all: demo / Password123)  step-ca https://localhost:9000"
}

wait_for_host_name() {   # k3d adds host.k3d.internal to CoreDNS a moment after `cluster create` returns. Flux looking it
  # up before then fails, the miss is cached and Flux backs off, which cost up to a minute and a half in CI: wait for the name.
  # k3s also sometimes crashes while starting (a permissions race), leaving a cluster that looks up but is dead: say so, fast
  i=0 dead=0
  until kubectl -n kube-system get cm coredns -o jsonpath='{.data.NodeHosts}' 2> /dev/null | grep -q host.k3d.internal; do
    if kubectl get --raw /readyz > /dev/null 2>&1; then dead=0; else dead=$((dead+1)); fi
    [ $dead -lt "${API_DEAD_AFTER:-20}" ] || { echo "The k3s API has not answered for ${API_DEAD_AFTER:-20}s: k3s sometimes crashes while starting. Run ./demo.sh clean, then try again" >&2; exit 1; }
    i=$((i+1)); [ $i -lt 120 ] || { echo "host.k3d.internal never reached CoreDNS (kubectl -n kube-system get pods)" >&2; exit 1; }
    sleep 1
  done
}

k8s_up() {   # k3d cluster, Flux, and Traefik Hub installed by Flux from platform/k8s, then chapter 1
  need_token; need_ca
  started=$(date +%s)   # not $SECONDS: dash, which is sh on Ubuntu, does not have it
  set -x
  repo=http://host.k3d.internal:3000/demo/gitops.git
  # The ports above are yours; the cluster owns the host's :80 and :443 too, because ACME validation only connects there
  k3d cluster create $K3D --wait -p "$K3D_HTTP:80@loadbalancer" -p "$K3D_HTTPS:443@loadbalancer" -p "$K3D_API:8082@loadbalancer" \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" --k3s-arg "--disable=traefik@server:0"
  kube
  echo "== k3d is up after $(( $(date +%s) - started ))s"
  wait_for_host_name
  echo "== host.k3d.internal resolves after $(( $(date +%s) - started ))s"
  flux install
  echo "== Flux is installed after $(( $(date +%s) - started ))s"
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
  flux create secret git gitea-auth --url=$repo --username=demo --password='Password123'
  kubectl create namespace traefik
  set +x   # keep the token off screen
  kubectl -n traefik create secret generic traefik-hub-license --from-literal=token="$HUB_TOKEN"
  set -x
  kubectl -n traefik create secret generic step-ca-root --from-file=ca.pem=certs/ca.pem   # for ACME against step-ca
  flux create source git gitops --url=$repo --branch=main --secret-ref=gitea-auth --interval=10s
  echo "== Flux reads the repo after $(( $(date +%s) - started ))s"
  # The stack first: the chapters use Traefik's CRDs, which only exist once it is installed (they depend on it)
  flux create kustomization stack --source=GitRepository/gitops --path=./platform/k8s --prune=true --interval=10s --wait
  set +x
  echo "== the stack is ready after $(( $(date +%s) - started ))s"
  chapter_up 1
  kubectl -n traefik rollout status deploy/traefik --timeout=300s
  echo "== k3d is done after $(( $(date +%s) - started ))s: dashboard http://localhost:$K3D_API/dashboard/"
}

vm_up() {   # Lima VM running platform/vm/vm-provision.sh (any Linux VM works the same way)
  need_token
  set -x
  if ! limactl list -q | grep -qx $VM; then limactl start --name=$VM --tty=false --set ".disk=\"20GiB\"" template:default
  elif ! limactl list --format '{{.Status}}' $VM | grep -q Running; then limactl start $VM --tty=false; fi   # re-running provisions again
  set +x   # keep the token off screen
  limactl shell $VM sudo HUB_TOKEN="$HUB_TOKEN" \
    GITOPS_REPO=http://demo:Password123@host.lima.internal:3000/demo/gitops.git sh -s < platform/vm/vm-provision.sh
  wait_for 300 http://localhost:$VM_PING/ping "limactl shell $VM sudo journalctl -u traefik"
  echo "VM up: http://localhost:$VM_HTTP"
}

# --- Chapters: which are on in k3d, and their tests ---------------------------------------------------------------
chapter_up() {   # [N|all]: Flux applies chapters 1..N on k3d (default all) and removes the later ones
  upto=${1:-all}
  kube
  turned_on=
  for d in chapters/[0-9][0-9]-*; do
    [ -f "$d/kustomization.yaml" ] || continue   # a chapter with no Kubernetes objects is skipped
    num=${d#chapters/}; num=$((1${num%%-*} - 100))   # 01 -> 1 (the leading 1 stops 08 being read as octal)
    name=chapter-${d#chapters/}
    if [ "$upto" = all ] || [ "$num" -le "$upto" ]; then
      flux create kustomization "$name" --source=GitRepository/gitops --path="./$d" --depends-on=stack --prune=true --interval=10s --export | kubectl apply -f -
      turned_on="$turned_on kustomization/$name"
    else
      flux delete kustomization "$name" --silent 2>/dev/null || true
    fi
  done
  for d in $(enabled_chapters); do   # a chapter that was removed or renamed leaves its Flux Kustomization behind
    [ -f "$d/kustomization.yaml" ] || flux delete kustomization "chapter-${d#chapters/}" --silent
  done
  # Applied together and waited for together: one slow chapter costs its own wait, not everyone's (`flux create` alone waits one by one)
  [ -z "$turned_on" ] || kubectl -n flux-system wait --for=condition=Ready --timeout=300s $turned_on
}

enabled_chapters() {   # the chapter directories that have a Flux Kustomization on k3d
  kube
  for k in $(kubectl get kustomization -n flux-system -o name 2>/dev/null); do
    case ${k##*/} in chapter-*) echo "chapters/${k##*/chapter-}" ;; esac
  done | sort
}

# The test files of the given chapters: *.hurl pass on k3d and on the exported VM, *.k8s.hurl on k3d only,
# *.vm.hurl on everything, including the hand-written VM
chapter_tests() { for d in "$@"; do ls "$d"/*.hurl 2>/dev/null || true; done; }

# --- Sanity check: k3d's config on the VM -------------------------------------------------------------------------
vm_exported() { vm_sudo test -f /etc/traefik/dynamic/exported.yaml; }   # is the VM running `export`'s config?

export_vm() {   # k3d's config, as file-provider YAML, on the VM
  need_ca; kube
  mkdir -p platform/vm/generated
  exported=platform/vm/generated/exported.yaml
  platform/vm/export.sh http://localhost:$K3D_API k3d-$K3D $VM_BACKEND > $exported
  echo "exported $(yq '(.http.routers // {}) | length' $exported) routers, $(yq '(.http.middlewares // {}) | length' $exported) middlewares, $(yq '(.http.services // {}) | length' $exported) services to $exported"
  vm_sudo systemctl disable --now gitops-sync.timer gitops-sync.service > /dev/null 2>&1   # or Git would put the hand-written files back
  vm_sudo sh -c 'rm -f /etc/traefik/dynamic/*'
  vm_sudo tee /etc/traefik/dynamic/exported.yaml < $exported > /dev/null
  echo "The k3d dashboard shows what was exported from: http://localhost:$K3D_API/dashboard/ (the VM has none)"
  export_matrix
}

export_matrix() {   # every enabled chapter's tests against the VM: what runs there on the exported config, and what doesn't
  status=0
  echo "== what runs on the VM, from the exported config"
  for f in $(chapter_tests $(enabled_chapters)); do
    case $f in
      *.k8s.hurl) printf '  %-5s %s\n        %s\n' SKIP "$f" "$(sed -n '1s/^# Kubernetes only: //p' "$f")" ;;
      *) if result=$(hurl --test --retry 20 --retry-interval 1000 --cacert certs/ca.pem \
                      --variable base_url=http://localhost:$VM_HTTP --variable tls_port= "$f" 2>&1); then
           printf '  %-5s %s\n' PASS "$f"
         else
           printf '  %-5s %s\n' FAIL "$f"; echo "$result"; status=1
         fi ;;
    esac
  done
  return $status
}

vm_reset() {   # undo export_vm: gitops-sync puts the hand-written files back within seconds
  vm_sudo systemctl enable --now gitops-sync.timer > /dev/null
  vm_sudo systemctl start gitops-sync.service
}

# --- Testing ------------------------------------------------------------------------------------------------------
smoke() {   # an up check for every shared service (the traffic generator needs both gateways up too)
  status=0
  echo "== shared services"
  hurl --test --insecure --retry 20 --retry-interval 1000 shared/tests/*.hurl || status=1
  [ "$($SHARED exec -T redis sh -c 'redis-cli set smoke ok >/dev/null && redis-cli get smoke')" = ok ] \
    || { echo "error: redis does not answer"; status=1; }
  i=0
  until log=$($SHARED logs --tail 20 traffic) && echo "$log" | grep -q "^traffic.* 200 .*:$K3D_HTTP/" && echo "$log" | grep -q "^traffic.* 200 .*:$VM_HTTP/"; do
    i=$((i+1)); [ $i -lt 10 ] || { echo "error: traffic gets no 200 from one of the gateways (k3d :$K3D_HTTP, VM :$VM_HTTP)"; status=1; break; }
    sleep 1
  done
  return $status
}

test_all() {   # hurl retries for up to 20s, so this can run straight after `sync`
  status=0
  smoke || status=1
  echo "== shared/opa"
  docker run --rm -v "$PWD/shared/opa:/policies:ro" openpolicyagent/opa:1.21.2 test /policies || status=1
  need_ca
  chapters=$(enabled_chapters)
  [ -n "$chapters" ] || { echo "No chapter is on: ./demo.sh chapter 1"; return 1; }
  # k3d runs every test of the enabled chapters. The VM runs the *.vm.hurl ones (they match its hand-written config),
  # or, after `export`, all of them except the *.k8s.hurl ones (Kubernetes only)
  if [ $# -gt 0 ]; then k8s_files="$*"; vm_files=$(printf '%s\n' "$@" | grep -v '\.k8s\.hurl$' || true)
  else
    k8s_files=$(chapter_tests $chapters)
    if vm_exported; then vm_files=$(chapter_tests $chapters | grep -v '\.k8s\.hurl$' || true)
    else vm_files=$(for d in $chapters; do ls $d/*.vm.hurl 2>/dev/null || true; done); fi
  fi
  for target in k3d vm; do   # HTTPS (ACME) is on k3d only
    if [ $target = k3d ]; then files=$k8s_files; port=$K3D_HTTP; tls=$K3D_HTTPS; label="k3d (localhost:$port, HTTPS on $tls)"
    else files=$vm_files; port=$VM_HTTP; tls=; label="VM (localhost:$port)"; vm_exported && label="$label, exported config"; fi
    [ -n "$files" ] || { echo "== $label: no tests"; continue; }
    echo "== $label"
    hurl --test --retry 20 --retry-interval 1000 --cacert certs/ca.pem \
      --variable base_url="http://localhost:$port" --variable tls_port="$tls" $files || status=1
  done
  return $status
}

# --- Tearing down, and the commands -------------------------------------------------------------------------------
clean() {
  rm -rf platform/vm/generated
  k3d cluster delete $K3D || true
  limactl delete -f $VM || true
  $SHARED down -v || true
  git remote remove gitea 2>/dev/null || true
}

case $1 in
  up)    git_up; shared_up; k8s_up; vm_up ;;
  git)   git_up ;;
  shared) shared_up ;;
  k8s)   k8s_up ;;
  vm)    vm_up ;;
  chapter) shift; chapter_up "$@" ;;
  sync)  sync ;;
  export) export_vm ;;
  vm-reset) vm_reset ;;
  smoke) smoke ;;
  test)  shift; test_all "$@" ;;
  clean) clean ;;
  rebuild) clean; git_up; shared_up; k8s_up; vm_up; chapter_up all; test_all; export_vm ;;
  *)     sed -n '2,13p' "$0"; exit 1 ;;
esac
