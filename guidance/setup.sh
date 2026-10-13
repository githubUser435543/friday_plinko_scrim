#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_IP="172.16.1.40"
GUIDANCE_IP="172.16.1.10"
STARTER_PASSWORD="H00ves0nTheM00n"
INSTALL_TRAINING_ARTIFACTS=1

usage() {
  printf 'Usage: %s [--manifest-ip IP] [--guidance-ip IP] [--password VALUE] [--skip-training-artifacts]\n' "$0"
}

while (($#)); do
  case "$1" in
    --manifest-ip) MANIFEST_IP="${2:?missing manifest IP}"; shift 2 ;;
    --guidance-ip) GUIDANCE_IP="${2:?missing guidance IP}"; shift 2 ;;
    --password) STARTER_PASSWORD="${2:?missing password}"; shift 2 ;;
    --skip-training-artifacts) INSTALL_TRAINING_ARTIFACTS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  printf 'Run this script as root.\n' >&2
  exit 1
fi

if [[ ! $MANIFEST_IP =~ ^[0-9a-fA-F:.]+$ || ! $GUIDANCE_IP =~ ^[0-9a-fA-F:.]+$ ]]; then
  printf 'IP parameters contain unsupported characters.\n' >&2
  exit 2
fi

if [[ $STARTER_PASSWORD == *$'\n'* || $STARTER_PASSWORD == *'"'* ]]; then
  printf 'Password cannot contain a newline or double quote.\n' >&2
  exit 2
fi

install -d -m 0750 /var/log/ihpl-setup
exec > >(tee -a /var/log/ihpl-setup/guidance.log) 2>&1

printf '[Guidance] Installing supported packages...\n'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  apache2 libapache2-mod-php php php-cli php-mysql mariadb-client \
  openssh-server sudo curl ca-certificates gcc

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
  printf 'SetEnv PLINKCOM_DB_HOST "%s"\n' "$MANIFEST_IP"
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

printf '[Guidance] Updating the PlinkCom password hash if Manifest is reachable...\n'
db_defaults="$(mktemp /tmp/plinkcom-mysql.XXXXXX)"
cleanup() { rm -f -- "$db_defaults"; }
trap cleanup EXIT
chmod 0600 "$db_defaults"
{
  printf '[client]\nuser=jmoney\npassword=%s\nhost=%s\nport=3306\n' "$STARTER_PASSWORD" "$MANIFEST_IP"
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
    printf '[Guidance] WARNING: Manifest is not reachable; rerun this script after MariaDB is ready.\n' >&2
  else
    sleep 5
  fi
done

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow out to "$MANIFEST_IP" port 3306 proto tcp
fi

if [[ $INSTALL_TRAINING_ARTIFACTS -eq 1 ]]; then
  "$SCRIPT_DIR/training/install-artifacts.sh"
fi

printf '[Guidance] Verifying services...\n'
systemctl is-active --quiet ssh
systemctl is-active --quiet apache2
curl --fail --silent --show-error http://127.0.0.1/login.php >/dev/null
printf '[Guidance] Ready: http://%s/ (database: %s:3306)\n' "$GUIDANCE_IP" "$MANIFEST_IP"
