# Assembly — Jenkins

Assembly is a Windows Server 2022 host running RDP and Jenkins on TCP 8080. The installer creates two freestyle jobs:

- `rocket-build`: builds, tests, documents, and lints the rocket once a minute.
- `mysql-database-backup`: checks Manifest's MariaDB endpoint and writes a timestamped backup manifest once a minute.

## Install

Open 64-bit Windows PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Setup-Assembly.ps1 `
  -AssemblyIp 172.16.1.30 `
  -ManifestIp 172.16.1.40 `
  -StarterPassword 'H00ves0nTheM00n'
```

Use `-SkipTrainingArtifacts` for a clean service-only build. The script enables RDP, creates `plinktern` and `jmoney`, installs Microsoft OpenJDK 17 and the pinned Jenkins MSI from official HTTPS endpoints, seeds Jenkins, and opens only TCP 8080 for Jenkins.

Local accounts are created and password-managed with Windows' built-in `net.exe`, then configured and verified through WinNT/ADSI. The installer does not depend on the `Microsoft.PowerShell.LocalAccounts` module and works from either 32-bit or 64-bit Windows PowerShell.

The findings include unauthorized Jenkins users, anonymous read access, enabled legacy RDP users, and a Users-writable batch file executed every minute as SYSTEM. The Jenkins Windows service also runs as LocalSystem, so authenticated Jenkins administrators have operating-system command execution through job configuration.

## Verification

```powershell
Get-Service Jenkins
net.exe user jmoney
net.exe user plinktern
net.exe localgroup Administrators
Test-NetConnection -ComputerName localhost -Port 8080
Invoke-WebRequest -UseBasicParsing http://localhost:8080/login
Get-NetFirewallRule -DisplayName 'IHPL Jenkins 8080'
```

Browse to Assembly on TCP 8080 and sign in as `plinktern` for administration or `jmoney` for scoring. Both accounts initially use `H00ves0nTheM00n`. On first startup, allow up to two minutes for Jenkins to initialize the security realm and jobs.

## Notes

- Jenkins home: `C:\ProgramData\Jenkins\.jenkins`
- Downloaded installers: `C:\ProgramData\IHPL\Downloads`
- Setup and verbose MSI logs: `C:\ProgramData\IHPL\Logs`
- Job output: `C:\ProgramData\IHPL\Builds`
- The setup script never disables TLS verification and requires a valid Authenticode signature on downloaded MSI files.
