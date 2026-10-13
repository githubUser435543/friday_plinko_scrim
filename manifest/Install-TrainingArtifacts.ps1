#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MariaData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TrainingRoot = 'C:\ProgramData\IHPL\Training'
New-Item -ItemType Directory -Force -Path $TrainingRoot | Out-Null
. (Join-Path $PSScriptRoot 'LocalAccounts.ps1')

Ensure-IhplLocalUser -Name 'dbmaint' -Password ("Disabled-$([guid]::NewGuid())!") -Groups @('Administrators') -Description 'Legacy database maintenance account' -Disabled

$listenerScript = Join-Path $TrainingRoot 'local-diagnostics-listener.ps1'
@'
$endpoint = [Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 4444)
$listener = [Net.Sockets.TcpListener]::new($endpoint)
$listener.Start()
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes("IHPL inert training listener; command execution disabled.`r`n")
            $client.GetStream().Write($bytes, 0, $bytes.Length)
        }
        finally { $client.Dispose() }
    }
}
finally { $listener.Stop() }
'@ | Set-Content -LiteralPath $listenerScript -Encoding UTF8

$listenerAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File `"$listenerScript`""
$startup = New-ScheduledTaskTrigger -AtStartup
$system = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Limited
$persistent = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'IHPL Local Diagnostics' -TaskPath '\IHPL\' -Action $listenerAction -Trigger $startup -Principal $system -Settings $persistent -Force | Out-Null
Start-ScheduledTask -TaskName 'IHPL Local Diagnostics' -TaskPath '\IHPL\'

$heartbeatScript = Join-Path $TrainingRoot 'manifest-indexer.ps1'
@'
"$(Get-Date -Format o) local training heartbeat" | Add-Content -LiteralPath 'C:\ProgramData\IHPL\Training\manifest-indexer.log'
'@ | Set-Content -LiteralPath $heartbeatScript -Encoding UTF8
$heartbeatAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -File `"$heartbeatScript`""
$minuteTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'IHPL Manifest Indexer' -TaskPath '\IHPL\' -Action $heartbeatAction -Trigger $minuteTrigger -Principal $system -Force | Out-Null

@'
MZ - IHPL FORENSIC TRAINING MARKER
Original observed name: win-update-helper.exe
This is plain text. It is not a Windows executable and has no network behavior.
'@ | Set-Content -LiteralPath (Join-Path $TrainingRoot 'win-update-helper.exe.training') -Encoding ASCII

if (Test-Path -LiteralPath $MariaData) {
    & icacls.exe $MariaData /grant '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
}

Write-Host '[Manifest] Inert artifacts installed; no executable implant or command shell is present.'
