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

bash -n \
  guidance/setup.sh \
  guidance/training/install-artifacts.sh \
  ignition/setup.sh \
  ignition/training/install-artifacts.sh

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
rg -q "Ensure-LocalRangeUser -Name 'plinktern'.*Administrators" assembly/Setup-Assembly.ps1
rg -q "Ensure-LocalRangeUser -Name 'plinktern'.*Administrators" manifest/Setup-Manifest.ps1
rg -q "'jmoney'.*'operator'" manifest/schema.sql
rg -q "'plinktern'.*'admin'" manifest/schema.sql
rg -q -- '--local-mariadb' guidance/setup.sh
rg -Fq 'packages+=(mariadb-server)' guidance/setup.sh
rg -q 'bind-address=127.0.0.1' guidance/setup.sh

git diff --check
printf 'Static validation passed.\n'
