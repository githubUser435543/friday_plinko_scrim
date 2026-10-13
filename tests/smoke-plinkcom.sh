#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
suffix="${RANDOM}${RANDOM}"
DOCKER_CONFIG="$(mktemp -d /tmp/ihpl-docker-config.XXXXXX)"
export DOCKER_CONFIG
network="ihpl-smoke-${suffix}"
database="ihpl-mariadb-${suffix}"
application="ihpl-plinkcom-${suffix}"
image="ihpl-plinkcom-smoke:${suffix}"
cookie_jar="$(mktemp /tmp/ihpl-cookie.XXXXXX)"
login_page="$(mktemp /tmp/ihpl-login.XXXXXX)"

cleanup() {
  docker rm -f "$application" "$database" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -f -- "$cookie_jar" "$login_page"
  rm -rf -- "$DOCKER_CONFIG"
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run -d --name "$database" --network "$network" --network-alias manifest \
  -e MARIADB_ROOT_PASSWORD='smoke-root-password' \
  -e MARIADB_DATABASE=plinkcom \
  -e MARIADB_USER=jmoney \
  -e MARIADB_PASSWORD='H00ves0nTheM00n' \
  -v "$ROOT/manifest/schema.sql:/docker-entrypoint-initdb.d/01-schema.sql:ro" \
  mariadb:11.4 >/dev/null

for attempt in {1..60}; do
  if docker exec "$database" mariadb-admin ping -h 127.0.0.1 -u root -psmoke-root-password --silent >/dev/null 2>&1; then break; fi
  [[ $attempt -lt 60 ]] || { docker logs "$database"; exit 1; }
  sleep 2
done

docker build -q -f "$ROOT/tests/Dockerfile.plinkcom" -t "$image" "$ROOT" >/dev/null
docker run -d --name "$application" --network "$network" -p 127.0.0.1::8000 \
  -e PLINKCOM_DB_HOST=manifest \
  -e PLINKCOM_DB_USER=jmoney \
  -e PLINKCOM_DB_PASSWORD='H00ves0nTheM00n' \
  -e PLINKCOM_DB_NAME=plinkcom \
  -v "$ROOT/guidance/plinkcom:/app:ro" "$image" >/dev/null

host_port="$(docker port "$application" 8000/tcp | awk -F: 'NR==1 {print $NF}')"
base_url="http://127.0.0.1:${host_port}"
for attempt in {1..30}; do
  if curl -fsS "$base_url/login.php" -o "$login_page" -c "$cookie_jar"; then break; fi
  [[ $attempt -lt 30 ]] || { docker logs "$application"; exit 1; }
  sleep 1
done

csrf="$(sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' "$login_page" | head -1)"
[[ -n $csrf ]] || { printf 'No CSRF token found.\n' >&2; exit 1; }

curl -fsS -L -b "$cookie_jar" -c "$cookie_jar" \
  --data-urlencode "csrf=$csrf" \
  --data-urlencode 'username=jmoney' \
  --data-urlencode 'password=H00ves0nTheM00n' \
  "$base_url/login.php" | grep -q 'EQUUS I'
curl -fsS "$base_url/api/status.php" | grep -q 'NOMINAL'
printf 'PlinkCom login, dashboard, and status API smoke test passed.\n'
