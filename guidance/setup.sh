#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_IP=""
DEPLOY_LOCAL_MARIADB=0
DATABASE_HOST=""
GUIDANCE_IP="172.16.1.10"
STARTER_PASSWORD="H00ves0nTheM00n"
INSTALL_TRAINING_ARTIFACTS=1

usage() {
  printf 'Usage: %s (--manifest-ip IP | --local-mariadb) [--guidance-ip IP] [--password VALUE] [--skip-training-artifacts]\n' "$0"
}

install_training_artifacts() {
  printf '[Guidance] Planting incident-response findings...\n'
  install -d -m 0755 /opt/ihpl-training /usr/local/libexec /usr/local/share
  install -m 0644 "$SCRIPT_DIR/training/maintenance.php" /var/www/plinkcom/public/assets/.maintenance.php

  if ! id telemetry-sync >/dev/null 2>&1; then
    useradd --system --create-home --shell /usr/sbin/nologin telemetry-sync
  fi
  passwd -l telemetry-sync >/dev/null 2>&1 || true
  printf 'telemetry-sync ALL=(root) NOPASSWD: /usr/bin/id\n' > /etc/sudoers.d/telemetry-sync
  chmod 0440 /etc/sudoers.d/telemetry-sync
  visudo --check --file=/etc/sudoers.d/telemetry-sync

  cat > /tmp/plinko-update-check.c <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
int main(void) {
    uid_t user = getuid();
    gid_t group = getgid();
    if (setresgid(group, group, group) != 0 || setresuid(user, user, user) != 0) return 1;
    puts("IHPL diagnostics: training artifact only; privileges dropped.");
    return 0;
}
EOF
  gcc -O2 -Wall -Wextra -o /usr/local/libexec/plinko-update-check /tmp/plinko-update-check.c
  rm -f /tmp/plinko-update-check.c
  chown root:root /usr/local/libexec/plinko-update-check
  chmod 4755 /usr/local/libexec/plinko-update-check

  install -m 0755 /usr/bin/sleep /opt/ihpl-training/bishop-agent
  cat > /etc/systemd/system/plinko-telemetry-agent.service <<'EOF'
[Unit]
Description=Legacy Plinko telemetry compatibility agent
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/opt/ihpl-training/bishop-agent infinity
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /opt/ihpl-training/banner_listener.py <<'PY'
#!/usr/bin/env python3
import socket

with socket.socket() as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 4444))
    server.listen(4)
    while True:
        client, _ = server.accept()
        with client:
            client.sendall(b"IHPL maintenance listener; command execution disabled.\n")
PY
  chmod 0755 /opt/ihpl-training/banner_listener.py
  cat > /etc/systemd/system/plinko-maintenance-listener.service <<'EOF'
[Unit]
Description=PlinkCom legacy maintenance listener
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/bin/python3 /opt/ihpl-training/banner_listener.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/plinko-health-refresh.service <<'EOF'
[Unit]
Description=Refresh legacy PlinkCom health marker

[Service]
Type=oneshot
ExecStart=/usr/bin/touch /var/tmp/.plinkcom-health
EOF
  cat > /etc/systemd/system/plinko-health-refresh.timer <<'EOF'
[Unit]
Description=Refresh legacy PlinkCom health marker every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=plinko-health-refresh.service

[Install]
WantedBy=timers.target
EOF

  printf '# training clue only; this is deliberately not /etc/ld.so.preload\n/usr/local/lib/libhorsehide.so\n' > /etc/ld.so.preload.training
  printf 'bishop-agent\nplinko-maintenance-listener\n' > /usr/local/share/.process-hide.training
  chmod 0644 /etc/ld.so.preload.training /usr/local/share/.process-hide.training

  systemctl daemon-reload
  systemctl enable --now plinko-telemetry-agent.service plinko-maintenance-listener.service plinko-health-refresh.timer
  printf '[Guidance] Findings installed; the Sliver indicator is disconnected and payload stand-ins do not execute commands.\n'
}

while (($#)); do
  case "$1" in
    --manifest-ip) MANIFEST_IP="${2:?missing manifest IP}"; shift 2 ;;
    --local-mariadb) DEPLOY_LOCAL_MARIADB=1; shift ;;
    --guidance-ip) GUIDANCE_IP="${2:?missing guidance IP}"; shift 2 ;;
    --password) STARTER_PASSWORD="${2:?missing password}"; shift 2 ;;
    --skip-training-artifacts) INSTALL_TRAINING_ARTIFACTS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z $MANIFEST_IP && $DEPLOY_LOCAL_MARIADB -eq 0 ]]; then
  printf 'Exactly one database mode is required: --manifest-ip IP or --local-mariadb.\n' >&2
  usage >&2
  exit 2
fi

if [[ -n $MANIFEST_IP && $DEPLOY_LOCAL_MARIADB -eq 1 ]]; then
  printf 'The --manifest-ip and --local-mariadb options are mutually exclusive.\n' >&2
  usage >&2
  exit 2
fi

if [[ $DEPLOY_LOCAL_MARIADB -eq 1 ]]; then
  DATABASE_HOST="127.0.0.1"
else
  DATABASE_HOST="$MANIFEST_IP"
fi

if [[ $EUID -ne 0 ]]; then
  printf 'Run this script as root.\n' >&2
  exit 1
fi

if [[ ! $DATABASE_HOST =~ ^[0-9a-fA-F:.]+$ || ! $GUIDANCE_IP =~ ^[0-9a-fA-F:.]+$ ]]; then
  printf 'IP parameters contain unsupported characters.\n' >&2
  exit 2
fi

if [[ $STARTER_PASSWORD == *$'\n'* || $STARTER_PASSWORD == *\"* || $STARTER_PASSWORD == *\'* || $STARTER_PASSWORD == *\\* ]]; then
  printf 'Password cannot contain a newline, quote, or backslash.\n' >&2
  exit 2
fi

install -d -m 0750 /var/log/ihpl-setup
exec > >(tee -a /var/log/ihpl-setup/guidance.log) 2>&1

printf '[Guidance] Installing supported packages...\n'
export DEBIAN_FRONTEND=noninteractive
apt-get update
packages=(
  apache2 libapache2-mod-php php php-cli php-mysql mariadb-client
  openssh-server sudo curl ca-certificates gcc libc6-dev
)
if [[ $DEPLOY_LOCAL_MARIADB -eq 1 ]]; then
  packages+=(mariadb-server)
fi
apt-get install -y --no-install-recommends "${packages[@]}"

if [[ $DEPLOY_LOCAL_MARIADB -eq 1 ]]; then
  printf '[Guidance] Configuring loopback-only MariaDB and seeding PlinkCom...\n'
  cat > /etc/mysql/mariadb.conf.d/60-plinkcom-local.cnf <<'EOF'
[mariadbd]
bind-address=127.0.0.1
port=3306
skip-name-resolve
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
EOF
  systemctl enable --now mariadb
  systemctl restart mariadb
  mariadb --protocol=socket --user=root < "$SCRIPT_DIR/database/schema.sql"
  mariadb --protocol=socket --user=root <<SQL
CREATE USER IF NOT EXISTS 'jmoney'@'localhost' IDENTIFIED BY '$STARTER_PASSWORD';
ALTER USER 'jmoney'@'localhost' IDENTIFIED BY '$STARTER_PASSWORD';
GRANT SELECT ON plinkcom.* TO 'jmoney'@'localhost';
GRANT UPDATE ON plinkcom.users TO 'jmoney'@'localhost';
CREATE USER IF NOT EXISTS 'jmoney'@'127.0.0.1' IDENTIFIED BY '$STARTER_PASSWORD';
ALTER USER 'jmoney'@'127.0.0.1' IDENTIFIED BY '$STARTER_PASSWORD';
GRANT SELECT ON plinkcom.* TO 'jmoney'@'127.0.0.1';
GRANT UPDATE ON plinkcom.users TO 'jmoney'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'plinktern'@'localhost' IDENTIFIED BY '$STARTER_PASSWORD';
ALTER USER 'plinktern'@'localhost' IDENTIFIED BY '$STARTER_PASSWORD';
GRANT ALL PRIVILEGES ON plinkcom.* TO 'plinktern'@'localhost';
FLUSH PRIVILEGES;
SQL
fi

printf '[Guidance] Creating the plinktern administrator and jmoney scoring account...\n'
if ! id jmoney >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash jmoney
fi
if ! id plinktern >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash plinktern
fi
printf 'jmoney:%s\n' "$STARTER_PASSWORD" | chpasswd
printf 'plinktern:%s\n' "$STARTER_PASSWORD" | chpasswd
usermod -aG sudo plinktern
gpasswd --delete jmoney sudo >/dev/null 2>&1 || true
id jmoney >/dev/null
id plinktern >/dev/null
if [[ " $(id -nG plinktern) " != *' sudo '* ]]; then
  printf 'plinktern was not added to the sudo group.\n' >&2
  exit 1
fi

printf '[Guidance] Deploying PlinkCom...\n'
install -d -m 0755 /var/www/plinkcom
rm -rf /var/www/plinkcom/app /var/www/plinkcom/public
cp -a "$SCRIPT_DIR/plinkcom/app" /var/www/plinkcom/app
cp -a "$SCRIPT_DIR/plinkcom/public" /var/www/plinkcom/public
chown -R root:www-data /var/www/plinkcom
find /var/www/plinkcom -type d -exec chmod 0755 {} +
find /var/www/plinkcom -type f -exec chmod 0644 {} +

install -m 0644 "$SCRIPT_DIR/apache/plinkcom.conf" /etc/apache2/sites-available/plinkcom.conf
umask 027
runtime_conf=/etc/apache2/conf-available/plinkcom-runtime.conf
{
  printf 'ServerName localhost\n'
  printf 'SetEnv PLINKCOM_DB_HOST "%s"\n' "$DATABASE_HOST"
  printf 'SetEnv PLINKCOM_DB_PORT "3306"\n'
  printf 'SetEnv PLINKCOM_DB_NAME "plinkcom"\n'
  printf 'SetEnv PLINKCOM_DB_USER "jmoney"\n'
  printf 'SetEnv PLINKCOM_DB_PASSWORD "%s"\n' "$STARTER_PASSWORD"
} > "$runtime_conf"
chmod 0640 "$runtime_conf"
chown root:www-data "$runtime_conf"
a2enmod headers >/dev/null
a2dissite 000-default >/dev/null 2>&1 || true
a2ensite plinkcom >/dev/null
a2enconf plinkcom-runtime >/dev/null
apache2ctl configtest
systemctl enable --now ssh apache2
systemctl reload apache2

printf '[Guidance] Synchronizing PlinkCom application passwords...\n'
db_defaults="$(mktemp /tmp/plinkcom-mysql.XXXXXX)"
cleanup() { rm -f -- "$db_defaults"; }
trap cleanup EXIT
chmod 0600 "$db_defaults"
{
  printf '[client]\nuser=jmoney\npassword=%s\nhost=%s\nport=3306\n' "$STARTER_PASSWORD" "$DATABASE_HOST"
} > "$db_defaults"
# PHP evaluates $argv; Bash must pass it literally.
# shellcheck disable=SC2016
password_hash="$(php -r 'echo password_hash($argv[1], PASSWORD_BCRYPT);' "$STARTER_PASSWORD")"
for attempt in {1..12}; do
  if mysql --defaults-extra-file="$db_defaults" --connect-timeout=3 plinkcom \
      --execute="UPDATE users SET password_hash='${password_hash}' WHERE username IN ('jmoney','plinktern');"; then
    printf '[Guidance] Database authentication synchronized.\n'
    break
  fi
  if [[ $attempt -eq 12 ]]; then
    printf '[Guidance] WARNING: MariaDB is not reachable; rerun this script after the database is ready.\n' >&2
  else
    sleep 5
  fi
done

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  ufw allow OpenSSH
  ufw allow 80/tcp
  if [[ $DEPLOY_LOCAL_MARIADB -eq 0 ]]; then
    ufw allow out to "$DATABASE_HOST" port 3306 proto tcp
  fi
fi

if [[ $INSTALL_TRAINING_ARTIFACTS -eq 1 ]]; then
  install_training_artifacts
fi

printf '[Guidance] Verifying services...\n'
systemctl is-active --quiet ssh
systemctl is-active --quiet apache2
if [[ $DEPLOY_LOCAL_MARIADB -eq 1 ]]; then
  systemctl is-active --quiet mariadb
fi
curl --fail --silent --show-error http://127.0.0.1/login.php >/dev/null
printf '[Guidance] Ready: http://%s/ (database: %s:3306)\n' "$GUIDANCE_IP" "$DATABASE_HOST"
