#!/bin/sh
# Turns any Linux VM into the file-provider demo. Needs GITOPS_REPO and HUB_TOKEN.
set -e
: "${GITOPS_REPO:?}" "${HUB_TOKEN:?}"
set -x

TRAEFIK_IMAGE=ghcr.io/traefik/traefik-hub:v3.21.2

# Docker runs the dependencies (compose) and is where the Traefik binary comes from.
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh

# Traefik runs as a plain binary under systemd, copied out of the release image.
id traefik >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin traefik
cid=$(docker create "$TRAEFIK_IMAGE")
docker cp "$cid":/traefik-hub /usr/local/bin/traefik-hub
docker rm "$cid" >/dev/null
mkdir -p /etc/traefik/dynamic
set +x   # keep the token off screen
echo "TRAEFIK_HUB_TOKEN=$HUB_TOKEN" > /etc/traefik/traefik.env
chmod 600 /etc/traefik/traefik.env
set -x

mkdir -p /etc/gitops
cat > /etc/gitops/env <<EOF
GITOPS_REPO=$GITOPS_REPO
EOF
chmod 600 /etc/gitops/env

cat > /usr/local/bin/gitops-sync <<'EOF'
#!/bin/sh
set -e
REPO=/opt/gitops/repo
DEMO=$REPO/file-provider
SCENARIOS=$DEMO/scenarios
TRAEFIK_CONFIG=/etc/traefik/dynamic
[ -d $REPO ] || git clone -q "$GITOPS_REPO" $REPO
git -C $REPO fetch -q && git -C $REPO reset -q --hard origin/main

# Dynamic config: the dashboard plus the scenarios listed in enabled.txt. Traefik hot-reloads it.
rm -rf /tmp/enabled && mkdir -m 755 /tmp/enabled
cp $DEMO/dashboard.yaml /tmp/enabled/
grep -vE '^[[:space:]]*(#|$)' $SCENARIOS/enabled.txt | (cd $SCENARIOS && xargs -r cp -t /tmp/enabled)
mkdir -p $TRAEFIK_CONFIG && rsync -a --delete /tmp/enabled/ $TRAEFIK_CONFIG/

# Static config: only rewrite it when it differs, or the path unit would restart Traefik on every run.
cmp -s $DEMO/traefik-static.yaml /etc/traefik/traefik-static.yaml || install -m 644 $DEMO/traefik-static.yaml /etc/traefik/traefik-static.yaml

docker compose -p gitops -f $DEMO/stack/compose.yaml up -d --remove-orphans --quiet-pull
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

cat > /etc/systemd/system/traefik.service <<'EOF'
[Unit]
Description=Traefik Hub
After=network-online.target
# Keep retrying: one failed start (e.g. the Hub licence check) must not stop Traefik for good
StartLimitIntervalSec=0

[Service]
User=traefik
EnvironmentFile=/etc/traefik/traefik.env
ExecStart=/usr/local/bin/traefik-hub --configFile=/etc/traefik/traefik.yaml
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# Restart Traefik when its static config changes (dynamic files hot-reload).
cat > /etc/systemd/system/traefik-restart.path <<'EOF'
[Path]
PathChanged=/etc/traefik/traefik.yaml
Unit=traefik-restart.service
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/traefik-restart.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/systemctl restart traefik.service
EOF

systemctl daemon-reload
systemctl start gitops-sync
systemctl enable --now traefik.service traefik-restart.path gitops-sync.timer
