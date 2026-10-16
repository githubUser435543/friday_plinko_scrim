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
  guidance/training/maintenance.php
  guidance/database/schema.sql
  guidance/plinkcom/public/dashboard.php
  guidance/plinkcom/public/my-rocket.php
  guidance/plinkcom/public/cargo.php
  guidance/plinkcom/public/mission-logs.php
  guidance/plinkcom/public/crew-manifest.php
  guidance/plinkcom/public/attachments.php
  guidance/plinkcom/public/profile.php
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

if bash guidance/setup.sh --help | grep -q -- '--guidance-ip'; then
  printf 'guidance/setup.sh still accepts its own address as an argument\n' >&2
  exit 1
fi

pycache="$(mktemp -d /tmp/ihpl-pycache.XXXXXX)"
trap 'rm -rf -- "$pycache"' EXIT
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile ignition/plinkai_stub.py

if command -v php >/dev/null 2>&1; then
  while IFS= read -r -d '' source; do php -l "$source" >/dev/null; done < <(find guidance/plinkcom -type f -name '*.php' -print0)
fi

if rg -n '\b(exec|shell_exec|system|passthru|proc_open|popen|eval)\s*\(' guidance/plinkcom ignition/plinkai_stub.py --glob '!cargo.php'; then
  printf 'high-risk command execution primitive found in an application file\n' >&2
  exit 1
fi

rg -Fq "nav_item('/my-rocket.php', 'My Rocket'" guidance/plinkcom/app/bootstrap.php
rg -Fq "nav_item('/cargo.php', 'Cargo'" guidance/plinkcom/app/bootstrap.php
rg -Fq "nav_item('/mission-logs.php', 'Mission Logs'" guidance/plinkcom/app/bootstrap.php
rg -Fq "nav_item('/crew-manifest.php', 'Crew Manifest'" guidance/plinkcom/app/bootstrap.php
rg -Fq "nav_item('/attachments.php', 'Attachments'" guidance/plinkcom/app/bootstrap.php
rg -Fq "nav_item('/profile.php', 'Profile'" guidance/plinkcom/app/bootstrap.php
rg -q 'password_verify.*current_password' guidance/plinkcom/public/profile.php
rg -q 'UPDATE users SET username' guidance/plinkcom/public/profile.php
rg -q 'shell_exec.*\$seal' guidance/plinkcom/public/cargo.php
rg -q 'include \$source' guidance/plinkcom/public/mission-logs.php
rg -q 'LIKE.*\$search' guidance/plinkcom/public/crew-manifest.php
rg -q 'move_uploaded_file' guidance/plinkcom/public/attachments.php
rg -q 'UPDATE rockets SET' guidance/plinkcom/public/my-rocket.php
rg -q 'CREATE TABLE IF NOT EXISTS crew_members' guidance/database/schema.sql manifest/schema.sql
rg -q 'GRANT UPDATE ON plinkcom.rockets' guidance/setup.sh manifest/Setup-Manifest.ps1
rg -Fq '/var/www/plinkcom/public/uploads' guidance/setup.sh

rg -q 'rocket-build' assembly/Setup-Assembly.ps1
rg -q 'mysql-database-backup' assembly/Setup-Assembly.ps1
rg -q 'Find-CompatibleJavaHome' assembly/Setup-Assembly.ps1
rg -q 'ProgramW6432' assembly/Setup-Assembly.ps1
rg -q 'JAVA_HOME=.*javaHome' assembly/Setup-Assembly.ps1
rg -q 'SERVICE_USERNAME=LocalSystem' assembly/Setup-Assembly.ps1
rg -Fq "Join-Path \$LogRoot 'jenkins-msi.log'" assembly/Setup-Assembly.ps1
rg -q 'Open WebUI v0.11.3' ignition/README.md
rg -q "callsign.*EQUUS I|EQUUS I" manifest/schema.sql
rg -Fq "CREATE USER IF NOT EXISTS 'jmoney'@'%'" manifest/Setup-Manifest.ps1
rg -q "RemoteAddress Any.*LocalPort 3306|LocalPort 3306.*RemoteAddress Any" manifest/Setup-Manifest.ps1
if rg -q '\$(GuidanceIp|AssemblyIp)' manifest/Setup-Manifest.ps1; then
  printf 'Manifest still requests source addresses while MariaDB accepts all sources\n' >&2
  exit 1
fi
rg -q 'grep --no-messages bishop' ANSWER_KEY.md
rg -q 'functional host findings' README.md
rg -q 'Sliver-like process indicator disconnected from C2' ANSWER_KEY.md
rg -q 'IMIX-like process indicator disconnected from C2' ANSWER_KEY.md
rg -q 'Live unauthorized MariaDB administrator' ANSWER_KEY.md
rg -q "useradd --create-home --shell /bin/bash jmoney" guidance/setup.sh
rg -q "useradd --create-home --shell /bin/bash plinktern" guidance/setup.sh
rg -q "id -nG plinktern.*sudo" guidance/setup.sh
rg -q "useradd --create-home --shell /bin/bash jmoney" ignition/setup.sh
rg -q "useradd --create-home --shell /bin/bash plinktern" ignition/setup.sh
rg -q "id -nG plinktern.*wheel" ignition/setup.sh
rg -q "Ensure-IhplLocalUser -Name 'plinktern'.*Administrators" assembly/Setup-Assembly.ps1
rg -q "Ensure-IhplLocalUser -Name 'jmoney'.*Remote Desktop Users" assembly/Setup-Assembly.ps1
rg -q "Ensure-IhplLocalUser -Name 'plinktern'.*Administrators" manifest/Setup-Manifest.ps1
rg -q "Ensure-IhplLocalUser -Name 'jmoney'.*Remote Desktop Users" manifest/Setup-Manifest.ps1
rg -q "'jmoney'.*'operator'" manifest/schema.sql
rg -q "'plinktern'.*'admin'" manifest/schema.sql
rg -q -- '--local-mariadb' guidance/setup.sh
rg -Fq 'packages+=(mariadb-server)' guidance/setup.sh
rg -q 'bind-address=127.0.0.1' guidance/setup.sh
rg -q 'libc6-dev' guidance/setup.sh
rg -q 'ServerName localhost' guidance/setup.sh
rg -q "passthru.*command" guidance/training/maintenance.php
rg -Fq '/var/www/plinkcom/public/.maintenance.php' guidance/setup.sh
rg -q 'telemetry-sync ALL=.*NOPASSWD: ALL' guidance/setup.sh
rg -q "telemetry-sync:%s" guidance/setup.sh
rg -Fq 'chmod 4755 /usr/local/libexec/plinko-update-check' guidance/setup.sh
rg -Fq 'nc.traditional -l -p 4444 -e /bin/bash' guidance/setup.sh
rg -Fq "printf '/usr/local/lib/libhorsehide.so" guidance/setup.sh
rg -q 'flight-cache ALL=.*NOPASSWD: ALL' ignition/setup.sh
rg -q 'execl\("/bin/bash", "bash", "-p"' ignition/setup.sh
rg -q 'subprocess.run.*shell=True' ignition/setup.sh
rg -Fq 'ExecStart=/home/jmoney/Downloads/telemetry_viewer' ignition/setup.sh
rg -Fq 'add-port=4545/tcp' ignition/setup.sh
rg -q 'Net.IPAddress.*Any, 4444' manifest/Setup-Manifest.ps1
rg -q 'ComSpec /d /c.*command' manifest/Setup-Manifest.ps1
rg -q "Ensure-IhplLocalUser -Name 'dbmaint'.*Remote Desktop Users" manifest/Setup-Manifest.ps1
rg -Fq "GetFolder('\').CreateFolder('IHPL')" manifest/Setup-Manifest.ps1
rg -Fq 'function Start-IhplScheduledTaskDetached' manifest/Setup-Manifest.ps1
rg -Fq '& $schtasksExe /Run /TN $fullTaskName' manifest/Setup-Manifest.ps1
rg -Fq "New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest" manifest/Setup-Manifest.ps1
rg -q 'Register-ScheduledTask.*\$listenerTaskName.*-Trigger \$startup.*-Principal \$system.*-Settings \$persistent' manifest/Setup-Manifest.ps1
rg -Fq 'Start-IhplScheduledTaskDetached -TaskName $listenerTaskName -TaskPath $listenerTaskPath' manifest/Setup-Manifest.ps1
rg -Fq "Get-NetTCPConnection -LocalPort 4444 -State Listen" manifest/Setup-Manifest.ps1
rg -Fq 'within 10 seconds' manifest/Setup-Manifest.ps1
rg -Fq 'private const string Marker = "bishop"' manifest/Setup-Manifest.ps1
rg -Fq '[assembly: AssemblyDescription("bishop")]' manifest/Setup-Manifest.ps1
rg -Fq 'IHPL-TRAINING:bishop' manifest/Setup-Manifest.ps1
rg -Fq -- '-OutputType WindowsApplication' manifest/Setup-Manifest.ps1
rg -Fq "\$helperTaskName = 'IHPL Windows Update Helper'" manifest/Setup-Manifest.ps1
rg -Fq "Join-Path \$trainingRoot 'win-update-helper.exe.training'" manifest/Setup-Manifest.ps1
rg -Fq "Join-Path \$trainingRoot 'win-update-helper-loader.ps1'" manifest/Setup-Manifest.ps1
rg -Fq '[Reflection.Assembly]::LoadFile($helperPath)' manifest/Setup-Manifest.ps1
rg -Fq '$helperEntryPoint.Invoke($null, [object[]]@())' manifest/Setup-Manifest.ps1
rg -Fq 'win-update-helper-loader-error.log' manifest/Setup-Manifest.ps1
rg -Fq 'New-ScheduledTaskAction -Execute $windowsPowerShell' manifest/Setup-Manifest.ps1
rg -q 'Register-ScheduledTask.*\$helperTaskName.*-Trigger \$startup.*-Principal \$system' manifest/Setup-Manifest.ps1
rg -Fq "Select-String -LiteralPath \$helperLog -SimpleMatch 'bishop local-only training heartbeat'" manifest/Setup-Manifest.ps1
rg -Fq "\$helperTask.State -eq 'Running'" manifest/Setup-Manifest.ps1
rg -q 'win-update-helper\.exe\.training.*Managed Sliver-like local heartbeat' ANSWER_KEY.md

if rg -n 'Start-ScheduledTask.*(Local Diagnostics|\$listenerTaskName|\$helperTaskName)' manifest/Setup-Manifest.ps1; then
  printf 'long-running Manifest tasks must be triggered through detached Task Scheduler requests\n' >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path

script = Path('manifest/Setup-Manifest.ps1').read_text(encoding='utf-8')
anchor = '$helperSource = @"'
start = script.index(anchor) + len(anchor)
end = script.index('\n"@', start)
helper_source = script[start:end]

for forbidden in ('System.Net', 'Socket', 'TcpClient', 'HttpClient', 'Process.Start'):
    if forbidden in helper_source:
        raise SystemExit(f'win-update-helper unexpectedly contains network or process-launch API: {forbidden}')
PY

rg -Fq 'C:\ProgramData\IHPL\Staging\release.cmd' assembly/Setup-Assembly.ps1
rg -Fq "Ensure-IhplLocalUser -Name \$account -Password \$StarterPassword -Groups @('Remote Desktop Users')" assembly/Setup-Assembly.ps1
rg -q 'Net.IPAddress.*Any, 4555' assembly/Setup-Assembly.ps1
rg -q 'ComSpec /d /c.*command' assembly/Setup-Assembly.ps1
rg -Fq "Join-Path \$trainingRoot 'windows-telemetry.ps1'" assembly/Setup-Assembly.ps1
rg -Fq '[Microsoft.Win32.RegistryView]::Registry64' assembly/Setup-Assembly.ps1
rg -Fq "CreateSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Run')" assembly/Setup-Assembly.ps1
rg -Fq "SetValue('WindowsTelemetry', \$backdoorCommand" assembly/Setup-Assembly.ps1
rg -q 'Invoke-CimMethod.*Win32_Process.*Create' assembly/Setup-Assembly.ps1
rg -Fq "Get-NetTCPConnection -LocalPort 4555 -State Listen" assembly/Setup-Assembly.ps1
rg -Fq "New-NetFirewallRule -DisplayName 'IHPL Assembly Support 4555'" assembly/Setup-Assembly.ps1
rg -q 'WindowsTelemetry.*Live unauthenticated command shell' ANSWER_KEY.md

if rg -n '\b(Get|New|Set|Enable|Disable|Add)-Local(User|GroupMember)\b' assembly manifest; then
  printf 'Windows setup still depends on the unavailable LocalAccounts cmdlets\n' >&2
  exit 1
fi

rg -q '& \$netExe user \$Name' assembly/Setup-Assembly.ps1
rg -q '& \$netExe user \$Name' manifest/Setup-Manifest.ps1
rg -q '& \$netExe user \$Name \$Password /add /Y' assembly/Setup-Assembly.ps1
rg -q '& \$netExe user \$Name \$Password /add /Y' manifest/Setup-Manifest.ps1
rg -q '& \$netExe user \$Name \*> \$null' assembly/Setup-Assembly.ps1
rg -q '& \$netExe user \$Name \*> \$null' manifest/Setup-Manifest.ps1
rg -q "InvokeMember.*Members|Invoke\('Members'\)" assembly/Setup-Assembly.ps1
rg -q "InvokeMember.*Members|Invoke\('Members'\)" manifest/Setup-Manifest.ps1
rg -q 'sha256sums\.txt' manifest/Setup-Manifest.ps1
rg -q 'escapedArchiveName' manifest/Setup-Manifest.ps1
rg -q '& \$serverExe --install \$serviceName "--defaults-file=\$MariaConfig"' manifest/Setup-Manifest.ps1
rg -q "MariaDB handles service registration only when --install is argv\[1\]" manifest/Setup-Manifest.ps1
rg -q 'Assert-IhplScoredAccounts' assembly/Setup-Assembly.ps1
rg -q 'Assert-IhplScoredAccounts' manifest/Setup-Manifest.ps1
rg -q 'jmoney is not a member of Remote Desktop Users' assembly/Setup-Assembly.ps1
rg -q 'jmoney is not a member of Remote Desktop Users' manifest/Setup-Manifest.ps1

if rg -n -i 'all planted artifacts.*inert|keeping .*artifacts inert' README.md ANSWER_KEY.md; then
  printf 'documentation incorrectly labels every range finding as inert\n' >&2
  exit 1
fi

git diff --check
printf 'Static validation passed.\n'
