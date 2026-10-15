#!/bin/sh
# Turns any Linux VM into the file-provider demo. Needs GITOPS_REPO and HUB_TOKEN.
set -e
: "${GITOPS_REPO:?}" "${HUB_TOKEN:?}"
set -x

command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh

mkdir -p /etc/gitops
cat > /etc/gitops/env <<EOF
GITOPS_REPO=$GITOPS_REPO
HUB_TOKEN=$HUB_TOKEN
EOF
chmod 600 /etc/gitops/env

cat > /usr/local/bin/gitops-sync <<'EOF'
#!/bin/sh
set -e
REPO=/opt/gitops/repo
DEMO=$REPO/file-provider
TRAEFIK_CONFIG=/opt/gitops/dynamic
[ -d $REPO ] || git clone -q "$GITOPS_REPO" $REPO
git -C $REPO fetch -q && git -C $REPO reset -q --hard origin/main

rm -rf /tmp/enabled && mkdir -m 755 /tmp/enabled
grep -vE '^[[:space:]]*(#|$)' $DEMO/enabled.txt | (cd $DEMO && xargs -r cp -t /tmp/enabled)
mkdir -p $TRAEFIK_CONFIG && rsync -a --delete /tmp/enabled/ $TRAEFIK_CONFIG/

docker compose -p gitops --env-file /etc/gitops/env -f $DEMO/stack/compose.yaml up -d --remove-orphans --quiet-pull
EOF
chmod 755 /usr/local/bin/gitops-sync

cat > /etc/systemd/system/gitops-sync.service <<'EOF'
[Service]
Type=oneshot
EnvironmentFile=/etc/gitops/env
ExecStart=/usr/local/bin/gitops-sync
EOF

cat > /etc/systemd/system/gitops-sync.timer <<'EOF'
[Timer]
OnBootSec=10s
OnUnitActiveSec=10s
AccuracySec=1s
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now gitops-sync.timer
systemctl start gitops-sync
