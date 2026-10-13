#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required_files=(
  README.md
  ANSWER_KEY.md
  BLUE_TEAM.md
  guidance/README.md
  guidance/setup.sh
  guidance/database/schema.sql
  guidance/plinkcom/public/dashboard.php
  ignition/README.md
  ignition/setup.sh
  ignition/plinkai_stub.py
  assembly/README.md
  assembly/Setup-Assembly.ps1
  manifest/README.md
  manifest/Setup-Manifest.ps1
  manifest/schema.sql
)

for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || { printf 'missing or empty: %s\n' "$file" >&2; exit 1; }
done

assert_single_installer() {
  local host="$1" pattern="$2" expected="$3"
  local -a scripts=()
  mapfile -t scripts < <(find "$host" -type f -name "$pattern" -print)
  if [[ ${#scripts[@]} -ne 1 ]]; then
    printf '%s must contain exactly one %s installer: %s\n' "$host" "$pattern" "$expected" >&2
    printf 'found: %s\n' "${scripts[*]:-(none)}" >&2
    exit 1
  fi
  if [[ ${scripts[0]} != "$expected" ]]; then
    printf '%s installer must be %s; found %s\n' "$host" "$expected" "${scripts[0]}" >&2
    exit 1
  fi
}

assert_single_installer guidance '*.sh' guidance/setup.sh
assert_single_installer ignition '*.sh' ignition/setup.sh
assert_single_installer assembly '*.ps1' assembly/Setup-Assembly.ps1
assert_single_installer manifest '*.ps1' manifest/Setup-Manifest.ps1

bash -n guidance/setup.sh ignition/setup.sh

if missing_database_output="$(bash guidance/setup.sh --skip-training-artifacts 2>&1)"; then
  printf 'guidance/setup.sh accepted a missing database mode\n' >&2
  exit 1
fi
grep -q -- 'Exactly one database mode is required' <<< "$missing_database_output"

if conflicting_database_output="$(bash guidance/setup.sh --manifest-ip 192.0.2.40 --local-mariadb 2>&1)"; then
  printf 'guidance/setup.sh accepted conflicting database modes\n' >&2
  exit 1
fi
grep -q -- 'mutually exclusive' <<< "$conflicting_database_output"

pycache="$(mktemp -d /tmp/ihpl-pycache.XXXXXX)"
trap 'rm -rf -- "$pycache"' EXIT
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile ignition/plinkai_stub.py

if command -v php >/dev/null 2>&1; then
  while IFS= read -r -d '' source; do php -l "$source" >/dev/null; done < <(find guidance/plinkcom -type f -name '*.php' -print0)
fi

if rg -n '\b(exec|shell_exec|system|passthru|proc_open|popen|eval)\s*\(' guidance/plinkcom ignition/plinkai_stub.py; then
  printf 'high-risk command execution primitive found in an application file\n' >&2
  exit 1
fi

rg -q 'rocket-build' assembly/Setup-Assembly.ps1
rg -q 'mysql-database-backup' assembly/Setup-Assembly.ps1
rg -q 'Open WebUI v0.11.3' ignition/README.md
rg -q "callsign.*EQUUS I|EQUUS I" manifest/schema.sql
rg -q 'RemoteAddress.*GuidanceIp.*AssemblyIp' manifest/Setup-Manifest.ps1
rg -q 'grep --no-messages bishop' ANSWER_KEY.md
rg -q "useradd --create-home --shell /bin/bash plinktern" guidance/setup.sh
rg -q "useradd --create-home --shell /bin/bash plinktern" ignition/setup.sh
rg -q "Ensure-IhplLocalUser -Name 'plinktern'.*Administrators" assembly/Setup-Assembly.ps1
rg -q "Ensure-IhplLocalUser -Name 'plinktern'.*Administrators" manifest/Setup-Manifest.ps1
rg -q "'jmoney'.*'operator'" manifest/schema.sql
rg -q "'plinktern'.*'admin'" manifest/schema.sql
rg -q -- '--local-mariadb' guidance/setup.sh
rg -Fq 'packages+=(mariadb-server)' guidance/setup.sh
rg -q 'bind-address=127.0.0.1' guidance/setup.sh

if rg -n '\b(Get|New|Set|Enable|Disable|Add)-Local(User|GroupMember)\b' assembly manifest; then
  printf 'Windows setup still depends on the unavailable LocalAccounts cmdlets\n' >&2
  exit 1
fi

git diff --check
printf 'Static validation passed.\n'
