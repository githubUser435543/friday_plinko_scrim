# Manifest — MariaDB

Manifest is a Windows Server 2019 host running RDP and MariaDB 13.1.1 on TCP 3306. It stores PlinkCom users, vehicle telemetry, and mission events.

## Install

Open 64-bit Windows PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Setup-Manifest.ps1 `
  -ManifestIp 172.16.1.40 `
  -StarterPassword 'H00ves0nTheM00n'
```

Use `-SkipTrainingArtifacts` for a clean service-only build. The installer downloads the official MariaDB archive and its published SHA-256 file, verifies the archive, initializes the database, seeds PlinkCom, enables RDP, and opens inbound TCP 3306 from all source addresses.

The MariaDB account `jmoney` uses the host pattern `%`, so PlinkCom and scoring clients can authenticate from any IP address with the correct password.

Local accounts are created and password-managed with Windows' built-in `net.exe`, then configured and verified through WinNT/ADSI. The installer does not depend on the `Microsoft.PowerShell.LocalAccounts` module and works from either 32-bit or 64-bit Windows PowerShell.

Unless `-SkipTrainingArtifacts` is used, the installer also builds and starts the real managed executable `C:\ProgramData\IHPL\Training\win-update-helper.exe.training`. The executable contains the string `bishop`, writes only a local heartbeat log, and makes no network connections. Because Windows Task Scheduler will not directly launch the nonstandard `.training` suffix, the SYSTEM task invokes its managed entry point through `win-update-helper-loader.ps1`. The `\IHPL\IHPL Windows Update Helper` at-startup task provides persistence.

The TCP 4444 diagnostics listener is launched asynchronously by the `\IHPL\IHPL Local Diagnostics` at-startup task. It runs as the built-in SYSTEM service account from `C:\ProgramData\IHPL\Training`, so it remains active after the RDP session closes and does not depend on the installer account continuing to exist.

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
Get-ScheduledTask -TaskPath '\IHPL\' -TaskName 'IHPL Local Diagnostics'
Get-NetTCPConnection -LocalPort 4444 -State Listen
Get-ScheduledTask -TaskPath '\IHPL\' -TaskName 'IHPL Windows Update Helper'
Get-Content C:\ProgramData\IHPL\Training\win-update-helper.log -Tail 5
findstr.exe /m /c:bishop C:\ProgramData\IHPL\Training\win-update-helper.exe.training
```

Use `plinktern` for database administration and `jmoney` for scoring checks. Both accounts initially use `H00ves0nTheM00n`.

## Firewall scope

`IHPL MariaDB 3306` permits TCP 3306 from any remote address. MariaDB still requires a valid database username and password.

Logs and setup files are under `C:\ProgramData\IHPL`. MariaDB data is under `C:\ProgramData\MariaDB\data`.
