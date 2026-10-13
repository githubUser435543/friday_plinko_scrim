# Manifest — MariaDB

Manifest is a Windows Server 2019 host running RDP and MariaDB 13.1.1 on TCP 3306. It stores PlinkCom users, vehicle telemetry, and mission events.

## Install

Open 64-bit Windows PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Setup-Manifest.ps1 `
  -ManifestIp 172.16.1.40 `
  -GuidanceIp 172.16.1.10 `
  -AssemblyIp 172.16.1.30 `
  -StarterPassword 'H00ves0nTheM00n'
```

Use `-SkipTrainingArtifacts` for a clean service-only build. The installer downloads the official MariaDB archive and its published SHA-256 file, verifies the archive, initializes the database, seeds PlinkCom, enables RDP, and restricts inbound TCP 3306 to Guidance and Assembly.

Local accounts are created and password-managed with Windows' built-in `net.exe`, then configured and verified through WinNT/ADSI. The installer does not depend on the `Microsoft.PowerShell.LocalAccounts` module and works from either 32-bit or 64-bit Windows PowerShell.

The exact requested version is the default. If the official archive does not publish `13.1.1`, the script stops instead of silently installing a different database version; pass a version that exists only after updating the exercise requirements.

## Verification

```powershell
Get-Service MariaDB
net.exe user jmoney
net.exe user plinktern
net.exe localgroup Administrators
Get-NetTCPConnection -LocalPort 3306 -State Listen
& 'C:\Program Files\MariaDB 13.1.1\bin\mariadb.exe' -u jmoney -p -e 'SELECT * FROM plinkcom.rockets;'
Get-NetFirewallRule -DisplayName 'IHPL MariaDB 3306'
```

Use `plinktern` for database administration and `jmoney` for scoring checks. Both accounts initially use `H00ves0nTheM00n`.

## Firewall scope

`IHPL MariaDB 3306` permits only the configured Guidance and Assembly addresses. Guidance needs database access for PlinkCom, and Assembly needs it for the backup job. Add a separate, narrowly scoped rule if the scoring engine connects directly.

Logs and setup files are under `C:\ProgramData\IHPL`. MariaDB data is under `C:\ProgramData\MariaDB\data`.
