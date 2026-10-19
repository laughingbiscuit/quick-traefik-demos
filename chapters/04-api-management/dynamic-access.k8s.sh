#!/bin/sh
# Kubernetes only (it changes the cluster, which a hurl file cannot): run by ./demo.sh test from the repo root.
# Partner A is not subscribed to Payments. One more subscription lets it call Payments, with the same token and the same
# Keycloak client; deleting that subscription takes the access away again. No restart, and nothing changes at the
# identity provider.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
grant=$here/grant-partner-a-payments.yaml

TOKEN=$(curl -s -u partner-a:Password123 -d grant_type=client_credentials \
  http://localhost:8180/realms/demo/protocol/openid-connect/token | jq -r .access_token)
call() { curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "${BASE_URL:-http://localhost:8080}/payments"; }

# <status> <seconds>: keep asking until Payments answers with the status, or give up
expect() {
  i=0
  until [ "$(call)" = "$1" ]; do
    i=$((i+1)); [ $i -lt "$2" ] || { echo "FAIL: partner-a -> payments gave $(call), wanted $1 within ${2}s"; exit 1; }
    sleep 1
  done
  echo "  ok    partner-a -> payments is $1 (after ${i}s)"
}

trap 'kubectl delete -f "$grant" --ignore-not-found > /dev/null 2>&1' EXIT
kubectl delete -f "$grant" --ignore-not-found > /dev/null 2>&1   # a clean start, whatever an earlier run left

echo "dynamic access"
expect 403 30
kubectl apply -f "$grant" > /dev/null
expect 200 30
kubectl delete -f "$grant" > /dev/null
expect 403 30
