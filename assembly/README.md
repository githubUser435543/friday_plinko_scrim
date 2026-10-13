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

The default Jenkins version is a maintained baseline. A working RCE or exploit PoC is deliberately not included; use the benign version-review artifact for the patch-management exercise.

## Verification

```powershell
Get-Service Jenkins
Test-NetConnection -ComputerName localhost -Port 8080
Invoke-WebRequest -UseBasicParsing http://localhost:8080/login
Get-NetFirewallRule -DisplayName 'IHPL Jenkins 8080'
```

Browse to `http://172.16.1.30:8080/` and sign in as `jmoney`. On first startup, allow up to two minutes for Jenkins to initialize the security realm and jobs.

## Notes

- Jenkins home: `C:\ProgramData\Jenkins\.jenkins`
- Installer/logs: `C:\ProgramData\IHPL`
- Job output: `C:\ProgramData\IHPL\Builds`
- The setup script never disables TLS verification and requires a valid Authenticode signature on downloaded MSI files.
