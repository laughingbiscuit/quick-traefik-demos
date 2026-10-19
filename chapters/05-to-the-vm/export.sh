#!/bin/sh
# The k3d Traefik's dynamic config as file-provider YAML for the VM, on stdout.
#
#   export.sh URL CONTEXT BACKEND      export.sh http://localhost:8082 k3d-k8s-demo http://localhost:9500
#
# 1. crd2file reads URL/api/rawdata: Traefik has already translated the Ingress, IngressRoute and
#    HTTPRoute objects, so that is what we take. CONTEXT lets it read what rawdata leaves out.
# 2. Services still on pod IPs (they mean nothing on the VM) are pointed at BACKEND, the whoami the VM runs.
# 3. The dashboard router is dropped: the VM has no dashboard, and this would switch it on.
#
# Only dynamic config comes out. Static config (entrypoints, certificate resolvers, providers) does not:
# a route that needs the websecure entrypoint or the "step" resolver loads on the VM but can't work there.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
url=${1:?usage: export.sh URL CONTEXT BACKEND} ctx=${2:?usage: export.sh URL CONTEXT BACKEND} backend=${3:?usage: export.sh URL CONTEXT BACKEND}

raw=$(mktemp) first=$(mktemp)
trap 'rm -f "$raw" "$first"' EXIT
curl -fsS "$url/api/rawdata" > "$raw"

# First pass: which services are on pod IPs. Second pass: the same, with those pointed at BACKEND.
"$here/crd2file.sh" -c "$ctx" "$raw" > "$first" 2> /dev/null
set --
for s in $(yq '(.http.services // {}) | to_entries | .[] | select(.value.loadBalancer.servers) | .key' "$first"); do
  set -- "$@" "$s=$backend"
done
"$here/crd2file.sh" -c "$ctx" "$raw" "$@" | yq 'del(.http.routers[] | select(.service == "api@internal"))'
