#!/bin/sh
set -xe
cd "$(dirname "$0")"

docker run -d --name gitea -p 3000:3000 -e GITEA__security__INSTALL_LOCK=true gitea/gitea:1.24
until curl -sf http://localhost:3000/api/healthz; do sleep 2; done
docker exec -u git gitea gitea admin user create --admin --username demo --password 'Passw0rd!' \
  --email demo@example.com --must-change-password=false
curl -fsu demo:'Passw0rd!' -o /dev/null -H 'Content-Type: application/json' \
  -d '{"name":"gitops","auto_init":true,"default_branch":"main"}' http://localhost:3000/api/v1/user/repos

git clone http://demo:Passw0rd%21@localhost:3000/demo/gitops.git gitops-demo-repo
cp -R file-provider/scenarios gitops-demo-repo/file-provider
cp -R k8s-providers/scenarios gitops-demo-repo/k8s-providers
cd gitops-demo-repo
git config user.name demo && git config user.email demo@example.com
git add . && git commit -m "Add demo scenarios" && git push
