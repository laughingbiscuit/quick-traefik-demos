#!/bin/sh
# Run tests against whichever demos are running (k8s on :8080, VM on :8000):
#   ./test.sh tests/00-passthrough.hurl
cd "$(dirname "$0")" || exit
[ $# -gt 0 ] || { echo "usage: ./test.sh tests/<scenario>.hurl ..."; exit 1; }

running() {   # ask k3d / Lima, not the port: Traefik may be mid-restart
  case $1 in
    k8s-providers) [ -n "$(docker ps -q -f name=^k3d-k8s-demo-server-0$)" ] ;;
    file-provider) [ "$(limactl list -f '{{.Status}}' fp-demo 2>/dev/null)" = Running ] ;;
  esac
}

run() {   # <demo> <port> <tests...>
  demo=$1 port=$2; shift 2
  running "$demo" || return 0
  echo "== $demo (localhost:$port)"
  ran=yes
  hurl --test --retry 20 --retry-interval 1000 --variable base_url="http://localhost:$port" "$@"
}

status=0
run k8s-providers 8080 "$@" || status=1
run file-provider 8000 "$@" || status=1
[ -n "$ran" ] || { echo "No demo is running."; exit 1; }
exit $status
