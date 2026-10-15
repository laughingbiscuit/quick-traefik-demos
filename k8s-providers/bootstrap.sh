#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -f ../.env ] && . ../.env
: "${HUB_TOKEN:?set HUB_TOKEN in .env (copy .env.example)}"
set -x
GITOPS_REPO=http://host.k3d.internal:3000/demo/gitops.git

k3d cluster create k8s-demo --wait -p "8080:80@loadbalancer" --k3s-arg "--disable=traefik@server:0"
KUBECONFIG=$(k3d kubeconfig write k8s-demo) && export KUBECONFIG   # immune to other tools switching context
flux install

flux create secret git gitea-auth --url=$GITOPS_REPO --username=demo --password='Passw0rd!'
kubectl create namespace traefik
set +x   # keep the token off screen
kubectl -n traefik create secret generic traefik-hub-license --from-literal=token="$HUB_TOKEN"
set -x

flux create source git gitops --url=$GITOPS_REPO --branch=main --secret-ref=gitea-auth --interval=10s
flux create kustomization stack --source=GitRepository/gitops --path=./k8s-providers/stack --prune=true --interval=10s --wait
flux create kustomization scenarios --source=GitRepository/gitops --path=./k8s-providers --prune=true --interval=10s

until curl -sf http://localhost:8080/; do sleep 2; done
