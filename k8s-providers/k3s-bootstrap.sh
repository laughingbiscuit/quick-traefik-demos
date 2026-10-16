#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -f ../.env ] && . ../.env
: "${HUB_TOKEN:?set HUB_TOKEN in .env (copy .env.example)}"
curl -sf -o /dev/null http://localhost:3000/api/healthz || { echo "Gitea is not running on :3000: run ./bootstrap-git.sh first"; exit 1; }
set -x
GITOPS_REPO=http://host.k3d.internal:3000/demo/gitops.git

k3d cluster create k8s-demo --wait -p "8080:80@loadbalancer" --k3s-arg "--disable=traefik@server:0"
KUBECONFIG=$(k3d kubeconfig write k8s-demo) && export KUBECONFIG   # immune to other tools switching context
flux install
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

flux create secret git gitea-auth --url=$GITOPS_REPO --username=demo --password='Passw0rd!'
kubectl create namespace traefik
set +x   # keep the token off screen
kubectl -n traefik create secret generic traefik-hub-license --from-literal=token="$HUB_TOKEN"
curl -sf -o /dev/null http://localhost:3000/api/healthz || { echo "Gitea is not running on :3000: run ./bootstrap-git.sh first"; exit 1; }
set -x

flux create source git gitops --url=$GITOPS_REPO --branch=main --secret-ref=gitea-auth --interval=10s
flux create kustomization stack --source=GitRepository/gitops --path=./k8s-providers/scenarios/stack --prune=true --interval=10s --wait
flux create kustomization scenarios --source=GitRepository/gitops --path=./k8s-providers/scenarios --prune=true --interval=10s

until curl -sf http://localhost:8080/; do sleep 2; done
