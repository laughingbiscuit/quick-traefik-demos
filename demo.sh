#!/bin/sh
# One entry point for both demos:
#   ./demo.sh up      Gitea, then the k8s demo (:8080) and the VM demo (:8000, dashboard :8001)
#   ./demo.sh sync    push this working tree to Gitea: both demos pick it up within ~20s
#   ./demo.sh test    run tests/*.hurl (or the files you name) against both demos
#   ./demo.sh rebuild clean, up, then test: a from-scratch check that everything works
#   ./demo.sh clean   delete everything the demos created (your changes stay in this repo)
# `up` runs the steps `git`, `k8s` and `vm`, which you can also run one at a time.
set -e
cd "$(dirname "$0")"
[ -f .env ] && . ./.env
GITEA=http://demo:Passw0rd%21@localhost:3000/demo/gitops.git

wait_for() {   # <seconds> <url> <hint>: poll until the URL answers, or give up
  i=0
  until curl -sf -o /dev/null "$2"; do
    i=$((i+2)); [ $i -lt "$1" ] || { echo "No answer from $2 after $1s: $3"; exit 1; }
    sleep 2
  done
}

need_token() { : "${HUB_TOKEN:?set HUB_TOKEN in .env (copy .env.example)}"; }

git_up() {   # Gitea on :3000, with this repo pushed to it as the `gitea` remote
  set -x
  docker run -d --name gitea -p 3000:3000 -e GITEA__security__INSTALL_LOCK=true gitea/gitea:1.24
  wait_for 120 http://localhost:3000/api/healthz "docker logs gitea"
  docker exec -u git gitea gitea admin user create --admin --username demo --password 'Passw0rd!' \
    --email demo@example.com --must-change-password=false
  curl -fsu demo:'Passw0rd!' -o /dev/null -H 'Content-Type: application/json' \
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

k8s_up() {   # k3d cluster, Flux, and Traefik Hub installed by Flux from k8s-providers/stack
  need_token
  set -x
  repo=http://host.k3d.internal:3000/demo/gitops.git
  k3d cluster create k8s-demo --wait -p "8080:80@loadbalancer" --k3s-arg "--disable=traefik@server:0"
  KUBECONFIG=$(k3d kubeconfig write k8s-demo) && export KUBECONFIG   # immune to other tools switching context
  flux install
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
  flux create secret git gitea-auth --url=$repo --username=demo --password='Passw0rd!'
  kubectl create namespace traefik
  set +x   # keep the token off screen
  kubectl -n traefik create secret generic traefik-hub-license --from-literal=token="$HUB_TOKEN"
  set -x
  flux create source git gitops --url=$repo --branch=main --secret-ref=gitea-auth --interval=10s
  # Two Kustomizations: the scenarios use Traefik's CRDs, which only exist once the stack is installed
  flux create kustomization stack --source=GitRepository/gitops --path=./k8s-providers/stack --prune=true --interval=10s --wait
  flux create kustomization scenarios --source=GitRepository/gitops --path=./k8s-providers/scenarios --prune=true --interval=10s
  kubectl -n traefik rollout status deploy/traefik --timeout=300s
  set +x
}

vm_up() {   # Lima VM running file-provider/vm-provision.sh (any Linux VM works the same way)
  need_token
  set -x
  limactl start --name=fp-demo --tty=false --set ".disk=\"20GiB\"" template:default
  set +x   # keep the token off screen
  limactl shell fp-demo sudo HUB_TOKEN="$HUB_TOKEN" \
    GITOPS_REPO=http://demo:Passw0rd%21@host.lima.internal:3000/demo/gitops.git sh -s < file-provider/vm-provision.sh
  wait_for 300 http://localhost:8001/ping "limactl shell fp-demo sudo journalctl -u traefik"
  echo "Dashboard: http://localhost:8001/dashboard/"
}

test_all() {   # hurl retries for up to 20s, so this can run straight after `sync`
  [ $# -gt 0 ] || set -- tests/*.hurl
  status=0
  for target in k8s-providers=8080 file-provider=8000; do
    echo "== ${target%=*} (localhost:${target#*=})"
    hurl --test --retry 20 --retry-interval 1000 --variable base_url="http://localhost:${target#*=}" "$@" || status=1
  done
  return $status
}

clean() {
  k3d cluster delete k8s-demo || true
  limactl delete -f fp-demo || true
  docker rm -fv gitea || true
  git remote remove gitea 2>/dev/null || true
}

case $1 in
  up)    git_up; k8s_up; vm_up ;;
  git)   git_up ;;
  k8s)   k8s_up ;;
  vm)    vm_up ;;
  sync)  sync ;;
  test)  shift; test_all "$@" ;;
  clean) clean ;;
  rebuild) clean; git_up; k8s_up; vm_up; test_all ;;
  *)     sed -n '2,8p' "$0"; exit 1 ;;
esac
