#!/bin/sh
# One entry point for both demos:
#   ./demo.sh up      Gitea and the shared services, then the k8s demo (:8080, TLS :8443) and the VM demo (:8000, TLS :8444, dashboard :8001)
#   ./demo.sh sync    push this working tree to Gitea: both demos pick it up within ~20s
#   ./demo.sh test    run tests/*.hurl (or the files you name) against both demos, plus the shared services' smoke tests
#   ./demo.sh smoke   just the smoke tests of the shared services
#   ./demo.sh rebuild clean, up, then test: a from-scratch check that everything works
#   ./demo.sh clean   delete everything the demos created (your changes stay in this repo)
#   ./demo.sh rebuild clean, up, sync and test in one
# `up` runs the steps `git`, `shared`, `k8s` and `vm`, which you can also run one at a time.
set -e
cd "$(dirname "$0")"
[ -f .env ] && . ./.env
SHARED="docker compose -p shared -f shared/compose.yaml"
GITEA=http://demo:Password123@localhost:3000/demo/gitops.git

wait_for() {   # <seconds> <url> <hint>: poll until the URL answers, or give up
  i=0
  until curl -skf -o /dev/null "$2"; do
    i=$((i+2)); [ $i -lt "$1" ] || { echo "No answer from $2 after $1s: $3"; exit 1; }
    sleep 2
  done
}

issue_cert() {   # a *.test certificate from step-ca for both websecure entrypoints, kept in certs/ (valid 24h)
  # curl refuses a wildcard with one dot, so *.demo.test is in there too: whoami.demo.test works everywhere
  mkdir -p certs
  ca="$SHARED exec -T step-ca"
  $ca step ca certificate '*.test' /tmp/tls.crt /tmp/tls.key --san demo.test --san '*.demo.test' \
    --provisioner admin --provisioner-password-file /home/step/secrets/password --force > /dev/null
  $ca cat /tmp/tls.crt > certs/tls.crt
  $ca cat /tmp/tls.key > certs/tls.key
  $ca cat /home/step/certs/root_ca.crt > certs/ca.pem
  chmod 600 certs/tls.key
  openssl verify -CAfile certs/ca.pem -untrusted certs/tls.crt certs/tls.crt > /dev/null
}

need_cert() { [ -f certs/tls.crt ] || { echo "No certs/tls.crt: run ./demo.sh shared first"; exit 1; }; }

need_token() { : "${HUB_TOKEN:?set HUB_TOKEN in .env (copy .env.example)}"; }

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

shared_up() {   # everything in shared/compose.yaml: Gitea is already up from `git`, the rest starts here
  set -x
  $SHARED up -d --quiet-pull
  [ "$(docker wait $($SHARED ps -aq ollama-pull))" = 0 ]   # the model download
  set +x
  wait_for 120 http://localhost:3001/api/health "$SHARED logs lgtm"
  wait_for 120 http://localhost:8180/realms/demo "$SHARED logs keycloak"
  wait_for 120 https://localhost:9000/health "$SHARED logs step-ca"
  issue_cert
  echo "Grafana http://localhost:3001  Keycloak http://localhost:8180  Vault http://localhost:8200  (login for all: demo / Password123)  step-ca https://localhost:9000"
}

k8s_up() {   # k3d cluster, Flux, and Traefik Hub installed by Flux from k8s-providers/stack
  need_token; need_cert
  set -x
  repo=http://host.k3d.internal:3000/demo/gitops.git
  # :8080 and :8443 are yours; the cluster owns the host's :80 and :443 too, because ACME validation only connects there
  k3d cluster create k8s-demo --wait -p "8080:80@loadbalancer" -p "8443:443@loadbalancer" \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" --k3s-arg "--disable=traefik@server:0"
  KUBECONFIG=$(k3d kubeconfig write k8s-demo) && export KUBECONFIG   # immune to other tools switching context
  flux install
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
  flux create secret git gitea-auth --url=$repo --username=demo --password='Password123'
  kubectl create namespace traefik
  set +x   # keep the token off screen
  kubectl -n traefik create secret generic traefik-hub-license --from-literal=token="$HUB_TOKEN"
  set -x
  kubectl -n traefik create secret tls wildcard-test --cert=certs/tls.crt --key=certs/tls.key
  kubectl -n traefik create secret generic step-ca-root --from-file=ca.pem=certs/ca.pem   # for ACME against step-ca
  flux create source git gitops --url=$repo --branch=main --secret-ref=gitea-auth --interval=10s
  # Two Kustomizations: the scenarios use Traefik's CRDs, which only exist once the stack is installed
  flux create kustomization stack --source=GitRepository/gitops --path=./k8s-providers/stack --prune=true --interval=10s --wait
  flux create kustomization scenarios --source=GitRepository/gitops --path=./k8s-providers/scenarios --prune=true --interval=10s
  kubectl -n traefik rollout status deploy/traefik --timeout=300s
  set +x
}

vm_up() {   # Lima VM running file-provider/vm-provision.sh (any Linux VM works the same way)
  need_token; need_cert
  set -x
  limactl start --name=fp-demo --tty=false --set ".disk=\"20GiB\"" template:default
  set +x   # keep the token off screen
  limactl shell fp-demo sudo HUB_TOKEN="$HUB_TOKEN" \
    TLS_CERT="$(base64 < certs/tls.crt | tr -d '\n')" TLS_KEY="$(base64 < certs/tls.key | tr -d '\n')" \
    GITOPS_REPO=http://demo:Password123@host.lima.internal:3000/demo/gitops.git sh -s < file-provider/vm-provision.sh
  wait_for 300 http://localhost:8001/ping "limactl shell fp-demo sudo journalctl -u traefik"
  echo "Dashboard: http://localhost:8001/dashboard/"
}

smoke() {   # an up check for every shared service (the traffic generator needs both gateways up too)
  status=0
  echo "== shared services"
  hurl --test --insecure --retry 20 --retry-interval 1000 shared/tests/*.hurl || status=1
  [ "$($SHARED exec -T redis sh -c 'redis-cli set smoke ok >/dev/null && redis-cli get smoke')" = ok ] \
    || { echo "error: redis does not answer"; status=1; }
  i=0
  until $SHARED logs --tail 5 traffic | grep -q ' 200 '; do
    i=$((i+1)); [ $i -lt 10 ] || { echo "error: traffic gets no 200 from the gateways"; status=1; break; }
    sleep 1
  done
  return $status
}

test_all() {   # hurl retries for up to 20s, so this can run straight after `sync`
  status=0
  smoke || status=1
  echo "== shared/opa"
  docker run --rm -v "$PWD/shared/opa:/policies:ro" openpolicyagent/opa:1.21.2 test /policies || status=1
  need_cert
  for target in k8s-providers=8080:8443 file-provider=8000:8444; do
    ports=${target#*=}
    if [ $# -gt 0 ]; then files="$*"   # tests named *.k8s.hurl are for Kubernetes only
    elif [ "${target%=*}" = k8s-providers ]; then files=$(ls tests/*.hurl)
    else files=$(ls tests/*.hurl | grep -v '\.k8s\.hurl$'); fi
    echo "== ${target%=*} (localhost:${ports%:*}, TLS on ${ports#*:})"
    hurl --test --retry 20 --retry-interval 1000 --cacert certs/ca.pem \
      --variable base_url="http://localhost:${ports%:*}" --variable tls_port="${ports#*:}" $files || status=1
  done
  return $status
}

clean() {
  k3d cluster delete k8s-demo || true
  limactl delete -f fp-demo || true
  $SHARED down -v || true
  git remote remove gitea 2>/dev/null || true
}

case $1 in
  up)    git_up; shared_up; k8s_up; vm_up ;;
  git)   git_up ;;
  shared) shared_up ;;
  k8s)   k8s_up ;;
  vm)    vm_up ;;
  sync)  sync ;;
  smoke) smoke ;;
  test)  shift; test_all "$@" ;;
  clean) clean ;;
  rebuild) clean; git_up; shared_up; k8s_up; vm_up; test_all ;;
  *)     sed -n '2,8p' "$0"; exit 1 ;;

esac
