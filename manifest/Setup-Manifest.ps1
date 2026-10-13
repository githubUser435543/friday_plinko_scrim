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
. (Join-Path $PSScriptRoot 'LocalAccounts.ps1')

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
        & (Join-Path $PSScriptRoot 'Install-TrainingArtifacts.ps1') -MariaData $MariaData
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
