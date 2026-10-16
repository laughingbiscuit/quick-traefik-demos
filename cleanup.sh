#!/bin/sh
cd "$(dirname "$0")" || exit
k3d cluster delete k8s-demo
limactl delete -f fp-demo
docker rm -fv gitea
git remote remove gitea 2>/dev/null || true
