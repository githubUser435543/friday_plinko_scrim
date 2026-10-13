#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TrainingRoot = 'C:\ProgramData\IHPL\Training'
$StagingRoot = 'C:\ProgramData\IHPL\Staging'
New-Item -ItemType Directory -Force -Path $TrainingRoot, $StagingRoot | Out-Null
. (Join-Path $PSScriptRoot 'LocalAccounts.ps1')

foreach ($account in @('flightops-old', 'rocketvendor')) {
    Ensure-IhplLocalUser -Name $account -Password ("Disabled-$([guid]::NewGuid())!") -Description 'Legacy IHPL training account' -Disabled
}

$acl = Get-Acl -LiteralPath $StagingRoot
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Users', 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.SetAccessRule($rule)
Set-Acl -LiteralPath $StagingRoot -AclObject $acl

$inventoryScript = Join-Path $TrainingRoot 'build-inventory.ps1'
@'
$output = 'C:\ProgramData\IHPL\Training\build-inventory.log'
Get-Service Jenkins | Select-Object Name, Status | Out-File -FilePath $output -Append
'@ | Set-Content -LiteralPath $inventoryScript -Encoding UTF8

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -File `"$inventoryScript`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName 'IHPL Build Inventory' -TaskPath '\IHPL\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

@'
Training finding: review the installed Jenkins core and plugin versions against the
current Jenkins security advisories. No exploit code or command-execution primitive
is installed by this project.
'@ | Set-Content -LiteralPath (Join-Path $TrainingRoot 'jenkins-version-review.txt') -Encoding UTF8

Write-Host '[Assembly] Inert artifacts installed; no RCE exploit or command shell is present.'
