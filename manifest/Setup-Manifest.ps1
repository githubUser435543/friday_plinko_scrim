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

    try {
        $entry = [ADSI]("WinNT://{0}/{1},user" -f $env:COMPUTERNAME, $Name)
        $null = $entry.psbase.NativeObject
        return $entry
    }
    catch {
        return $null
    }
}

function Add-IhplLocalGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.DirectoryServices.DirectoryEntry]$User,
        [Parameter(Mandatory)][string]$Group
    )

    $groupEntry = [ADSI]("WinNT://{0}/{1},group" -f $env:COMPUTERNAME, $Group)
    $null = $groupEntry.psbase.NativeObject
    $memberPath = [string]$User.Path
    $isMember = [bool]$groupEntry.psbase.Invoke('IsMember', @($memberPath))
    if (-not $isMember) {
        $groupEntry.psbase.Invoke('Add', @($memberPath))
    }
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

    $user = Get-IhplLocalUser -Name $Name
    if ($null -eq $user) {
        $computer = [ADSI]("WinNT://{0},computer" -f $env:COMPUTERNAME)
        $user = $computer.Create('user', $Name)
        $user.SetPassword($Password)
        $user.SetInfo()
        $user = Get-IhplLocalUser -Name $Name
        if ($null -eq $user) {
            throw "Local account $Name was created but could not be reopened."
        }
    }
    else {
        $user.SetPassword($Password)
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

function Install-IhplTrainingArtifacts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MariaData)

    $trainingRoot = 'C:\ProgramData\IHPL\Training'
    New-Item -ItemType Directory -Force -Path $trainingRoot | Out-Null

    Ensure-IhplLocalUser -Name 'dbmaint' -Password ("Disabled-$([guid]::NewGuid())!") -Groups @('Administrators') -Description 'Legacy database maintenance account' -Disabled

    $listenerScript = Join-Path $trainingRoot 'local-diagnostics-listener.ps1'
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

    $heartbeatScript = Join-Path $trainingRoot 'manifest-indexer.ps1'
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
'@ | Set-Content -LiteralPath (Join-Path $trainingRoot 'win-update-helper.exe.training') -Encoding ASCII

    if (Test-Path -LiteralPath $MariaData) {
        & icacls.exe $MariaData /grant '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
    }

    Write-Host '[Manifest] Inert artifacts installed; no executable implant or command shell is present.'
}

function Save-VerifiedArchive {
    param(
        [Parameter(Mandatory)][uri]$ArchiveUri,
        [Parameter(Mandatory)][uri]$ChecksumUri,
        [Parameter(Mandatory)][string]$Destination
    )
    $checksumPath = "$Destination.sha256"
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -UseBasicParsing -Uri $ArchiveUri -OutFile $Destination
    }
    Invoke-WebRequest -UseBasicParsing -Uri $ChecksumUri -OutFile $checksumPath
    $checksumText = Get-Content -LiteralPath $checksumPath -Raw
    $match = [regex]::Match($checksumText, '(?i)\b[0-9a-f]{64}\b')
    if (-not $match.Success) { throw "No SHA-256 digest was published at $ChecksumUri." }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $match.Value.ToUpperInvariant()) { throw "SHA-256 verification failed for $Destination." }
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

    $archiveName = "mariadb-$MariaDbVersion-winx64.zip"
    $archivePath = Join-Path $DownloadRoot $archiveName
    $archiveUri = "https://archive.mariadb.org/mariadb-$MariaDbVersion/winx64-packages/$archiveName"
    Write-Host "[Manifest] Downloading and verifying MariaDB $MariaDbVersion..."
    Save-VerifiedArchive -ArchiveUri $archiveUri -ChecksumUri "$archiveUri.sha256" -Destination $archivePath

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

    if (-not (Get-Service -Name MariaDB -ErrorAction SilentlyContinue)) {
        & $serverExe "--defaults-file=$MariaConfig" --install MariaDB
        if ($LASTEXITCODE -ne 0) { throw "MariaDB service registration exited with $LASTEXITCODE." }
    }
    Set-Service -Name MariaDB -StartupType Automatic
    Start-Service -Name MariaDB

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
        Write-Host '[Manifest] Planting inert incident-response artifacts...'
        Install-IhplTrainingArtifacts -MariaData $MariaData
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
