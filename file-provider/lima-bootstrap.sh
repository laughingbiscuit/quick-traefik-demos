#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -f ../.env ] && . ../.env
: "${HUB_TOKEN:?set HUB_TOKEN in .env (copy .env.example)}"
curl -sf -o /dev/null http://localhost:3000/api/healthz || { echo "Gitea is not running on :3000: run ./bootstrap-git.sh first"; exit 1; }
set -x

limactl start --name=fp-demo --tty=false --set ".disk=\"20GiB\"" template:default
set +x   # keep the token off screen
limactl shell fp-demo sudo HUB_TOKEN="$HUB_TOKEN" \
  GITOPS_REPO=http://demo:Passw0rd%21@host.lima.internal:3000/demo/gitops.git sh -s < vm-provision.sh
set -x

until curl -sf http://localhost:8000/; do sleep 2; done
echo "Dashboard: http://localhost:8001/dashboard/"
