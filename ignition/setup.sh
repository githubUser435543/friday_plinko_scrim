#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IGNITION_IP="172.16.1.20"
STARTER_PASSWORD="H00ves0nTheM00n"
OPEN_WEBUI_VERSION="v0.11.3"
INSTALL_TRAINING_ARTIFACTS=1

usage() {
  printf 'Usage: %s [--ignition-ip IP] [--password VALUE] [--open-webui-version TAG] [--skip-training-artifacts]\n' "$0"
}

while (($#)); do
  case "$1" in
    --ignition-ip) IGNITION_IP="${2:?missing ignition IP}"; shift 2 ;;
    --password) STARTER_PASSWORD="${2:?missing password}"; shift 2 ;;
    --open-webui-version) OPEN_WEBUI_VERSION="${2:?missing version}"; shift 2 ;;
    --skip-training-artifacts) INSTALL_TRAINING_ARTIFACTS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  printf 'Run this script as root.\n' >&2
  exit 1
fi
if [[ ! $IGNITION_IP =~ ^[0-9a-fA-F:.]+$ ]]; then
  printf 'IP parameter contains unsupported characters.\n' >&2
  exit 2
fi

install -d -m 0750 /var/log/ihpl-setup
exec > >(tee -a /var/log/ihpl-setup/ignition.log) 2>&1

DNF_ARGS=(-y)
if ! dnf -q makecache; then
  printf '[Ignition] Configured Fedora repositories are unavailable; using the signed Fedora 38 archive.\n'
  cat > /etc/yum.repos.d/ihpl-fedora-archive.repo <<'EOF'
[ihpl-fedora-archive]
name=Fedora 38 archive - Everything
baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/38/Everything/$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-38-primary

[ihpl-fedora-updates-archive]
name=Fedora 38 archive - Updates
baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/updates/38/Everything/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-38-primary
EOF
  DNF_ARGS+=(--disablerepo=* --enablerepo=ihpl-fedora-archive --enablerepo=ihpl-fedora-updates-archive)
fi

printf '[Ignition] Installing supported packages...\n'
dnf "${DNF_ARGS[@]}" install openssh-server podman curl python3 sudo gcc firewalld

printf '[Ignition] Creating the plinktern administrator and jmoney scoring account...\n'
if ! id jmoney >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash jmoney
fi
if ! id plinktern >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash plinktern
fi
printf 'jmoney:%s\n' "$STARTER_PASSWORD" | chpasswd
printf 'plinktern:%s\n' "$STARTER_PASSWORD" | chpasswd
usermod -aG wheel plinktern
gpasswd --delete jmoney wheel >/dev/null 2>&1 || true
systemctl enable --now sshd firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

printf '[Ignition] Installing the local PlinkAI model endpoint...\n'
install -D -m 0755 "$SCRIPT_DIR/plinkai_stub.py" /opt/plinkai/plinkai_stub.py
cat > /etc/systemd/system/plinkai-stub.service <<'EOF'
[Unit]
Description=Offline PlinkAI OpenAI-compatible API
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/bin/python3 /opt/plinkai/plinkai_stub.py
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now plinkai-stub.service

printf '[Ignition] Pulling Open WebUI %s...\n' "$OPEN_WEBUI_VERSION"
podman pull "ghcr.io/open-webui/open-webui:${OPEN_WEBUI_VERSION}"
install -d -m 0750 /var/lib/open-webui
cat > /etc/systemd/system/open-webui.service <<EOF
[Unit]
Description=Open WebUI ${OPEN_WEBUI_VERSION}
Requires=plinkai-stub.service
After=network-online.target plinkai-stub.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/podman rm -f open-webui
ExecStart=/usr/bin/podman run --name open-webui --log-driver=journald -p 80:8080 -v /var/lib/open-webui:/app/backend/data:Z -e WEBUI_NAME=PlinkAI -e WEBUI_AUTH=true -e ENABLE_SIGNUP=true -e DEFAULT_USER_ROLE=user -e ENABLE_OLLAMA_API=false -e ENABLE_OPENAI_API=true -e OPENAI_API_BASE_URL=http://host.containers.internal:11435/v1 -e OPENAI_API_BASE_URLS=http://host.containers.internal:11435/v1 -e OPENAI_API_KEY=ihpl-local-only -e OPENAI_API_KEYS=ihpl-local-only ghcr.io/open-webui/open-webui:${OPEN_WEBUI_VERSION}
ExecStop=/usr/bin/podman stop -t 20 open-webui

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now open-webui.service

printf '[Ignition] Waiting for Open WebUI...\n'
for attempt in {1..60}; do
  if curl --fail --silent http://127.0.0.1/health >/dev/null; then
    break
  fi
  if [[ $attempt -eq 60 ]]; then
    journalctl --no-pager -u open-webui.service -n 80
    printf 'Open WebUI did not become ready.\n' >&2
    exit 1
  fi
  sleep 5
done

seed_user() {
  local name="$1" email="$2" password="$3"
  python3 - "$name" "$email" "$password" <<'PY'
import json
import sys
import urllib.error
import urllib.request

name, email, password = sys.argv[1:]
body = json.dumps({"name": name, "email": email, "password": password}).encode()
request = urllib.request.Request("http://127.0.0.1/api/v1/auths/signup", data=body, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(request, timeout=15) as response:
        print(f"seeded {email}: HTTP {response.status}")
except urllib.error.HTTPError as error:
    if error.code in (400, 409):
        print(f"account already present or signup rejected for {email}; continuing")
    else:
        raise
PY
}

seed_user 'Plinktern Administrator' 'plinktern@plinko.horse' "$STARTER_PASSWORD"
seed_user 'J-Money' 'jmoney@plinko.horse' "$STARTER_PASSWORD"
seed_user 'Telemetry Support Bot' 'support.bot@plinko.horse' 'Orbit-Support-2026!'

sed -i 's/-e ENABLE_SIGNUP=true/-e ENABLE_SIGNUP=false/' /etc/systemd/system/open-webui.service
systemctl daemon-reload
systemctl restart open-webui.service

if [[ $INSTALL_TRAINING_ARTIFACTS -eq 1 ]]; then
  "$SCRIPT_DIR/training/install-artifacts.sh"
fi

systemctl is-active --quiet sshd
systemctl is-active --quiet plinkai-stub
systemctl is-active --quiet open-webui
curl --fail --silent http://127.0.0.1:11435/v1/models >/dev/null
printf '[Ignition] Ready: http://%s/ (Open WebUI %s)\n' "$IGNITION_IP" "$OPEN_WEBUI_VERSION"
