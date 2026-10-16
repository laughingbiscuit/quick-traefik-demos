#!/bin/sh
# Sends one request every INTERVAL seconds, picking a gateway at random: K8S_WEIGHT percent go to
# the Kubernetes gateway, the rest to the VM. Change a knob and run `docker compose up -d` again.
K8S=${K8S_GATEWAY:-http://host.docker.internal:8080}
VM=${VM_GATEWAY:-http://host.docker.internal:8000}

while :; do
  if [ "$(awk 'BEGIN { srand(); print int(rand() * 100) }')" -lt "${K8S_WEIGHT:-50}" ]; then gw=$K8S; else gw=$VM; fi
  curl -s -o /dev/null -w "%{http_code} $gw${URL_PATH:-/passthrough}\n" "$gw${URL_PATH:-/passthrough}" || true
  sleep "${INTERVAL:-1}"
done
