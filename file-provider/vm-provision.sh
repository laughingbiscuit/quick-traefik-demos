#!/bin/sh
# Turns any Linux VM into the file-provider demo, with no Docker: Traefik Hub and whoami are plain
# binaries from GitHub under systemd. Needs GITOPS_REPO and HUB_TOKEN. No TLS here: ACME needs the host's :80 and :443, see the k8s demo.
set -e
: "${GITOPS_REPO:?}" "${HUB_TOKEN:?}"
set -x

HUB_VERSION=v3.21.2       # github.com/traefik/hub/releases
WHOAMI_VERSION=v1.11.0    # github.com/traefik/whoami/releases (v1.12.0 has no binaries)

case $(uname -m) in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) echo "unsupported CPU: $(uname -m)"; exit 1 ;;
esac

# Download both release tarballs, check their checksums, install the binaries.
dl=$(mktemp -d)
cd "$dl"
hub=traefik-hub_${HUB_VERSION}_linux_${arch}
curl -fsSL -O https://github.com/traefik/hub/releases/download/$HUB_VERSION/$hub.tar.gz \
  -O https://github.com/traefik/hub/releases/download/$HUB_VERSION/$hub.tar.gz.sha256.txt
echo "$(cat $hub.tar.gz.sha256.txt)  $hub.tar.gz" | sha256sum -c -
tar xzf $hub.tar.gz
install -m 755 traefik-hub-linux-$arch /usr/local/bin/traefik-hub
whoami=whoami_${WHOAMI_VERSION}_linux_${arch}
curl -fsSL -O https://github.com/traefik/whoami/releases/download/$WHOAMI_VERSION/$whoami.tar.gz \
  -O https://github.com/traefik/whoami/releases/download/$WHOAMI_VERSION/whoami_${WHOAMI_VERSION#v}_checksums.txt
grep " $whoami.tar.gz\$" whoami_${WHOAMI_VERSION#v}_checksums.txt | sha256sum -c -
tar xzf $whoami.tar.gz whoami
install -m 755 whoami /usr/local/bin/whoami
cd /; rm -rf "$dl"

id traefik >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin traefik
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

# Dynamic config: the dashboard and the scenarios listed in enabled.txt. Traefik hot-reloads it.
rm -rf /tmp/enabled && mkdir -m 755 /tmp/enabled
cp $DEMO/dashboard.yaml /tmp/enabled/
grep -vE '^[[:space:]]*(#|$)' $SCENARIOS/enabled.txt | (cd $SCENARIOS && xargs -r cp -t /tmp/enabled)
mkdir -p $TRAEFIK_CONFIG && rsync -a --delete /tmp/enabled/ $TRAEFIK_CONFIG/

# Static config: only rewrite it when it differs, or the path unit would restart Traefik on every run.
cmp -s $DEMO/traefik-static.yaml /etc/traefik/traefik-static.yaml || install -m 644 $DEMO/traefik-static.yaml /etc/traefik/traefik-static.yaml
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
ExecStart=/usr/local/bin/traefik-hub --configFile=/etc/traefik/traefik-static.yaml
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# The scenarios' backend. Port 9500: Lima forwards every guest port to the host, so it must not clash with a shared service.
cat > /etc/systemd/system/whoami.service <<'EOF'
[Unit]
Description=whoami, the backend of the VM scenarios

[Service]
DynamicUser=yes
ExecStart=/usr/local/bin/whoami --port 9500 --name vm-whoami
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Restart Traefik when its static config changes (dynamic files hot-reload).
cat > /etc/systemd/system/traefik-restart.path <<'EOF'
[Path]
PathChanged=/etc/traefik/traefik-static.yaml
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
systemctl enable --now whoami.service traefik.service traefik-restart.path gitops-sync.timer
