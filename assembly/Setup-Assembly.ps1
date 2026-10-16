#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F:.]+$')]
    [string]$AssemblyIp = '172.16.1.30',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F:.]+$')]
    [string]$ManifestIp = '172.16.1.40',

    [Parameter()]
    [string]$StarterPassword = 'H00ves0nTheM00n',

    [Parameter()]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$JenkinsVersion = '2.516.3',

    [Parameter()]
    [switch]$SkipTrainingArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($StarterPassword.Contains("'") -or $StarterPassword.Contains("`r") -or $StarterPassword.Contains("`n")) {
    throw 'StarterPassword cannot contain a single quote or newline.'
}

$ProgramRoot = 'C:\ProgramData\IHPL'
$DownloadRoot = Join-Path $ProgramRoot 'Downloads'
$LogRoot = Join-Path $ProgramRoot 'Logs'
$JenkinsHome = 'C:\ProgramData\Jenkins\.jenkins'
New-Item -ItemType Directory -Force -Path $ProgramRoot, $DownloadRoot, $LogRoot, $JenkinsHome | Out-Null
Start-Transcript -Path (Join-Path $LogRoot 'assembly-setup.log') -Append | Out-Null

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

function Install-IhplTrainingArtifacts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StarterPassword)

    $trainingRoot = 'C:\ProgramData\IHPL\Training'
    $stagingRoot = 'C:\ProgramData\IHPL\Staging'
    New-Item -ItemType Directory -Force -Path $trainingRoot, $stagingRoot | Out-Null
    Remove-Item -LiteralPath (Join-Path $trainingRoot 'jenkins-version-review.txt') -Force -ErrorAction SilentlyContinue

    foreach ($account in @('flightops-old', 'rocketvendor')) {
        Ensure-IhplLocalUser -Name $account -Password $StarterPassword -Groups @('Remote Desktop Users') -Description 'Legacy IHPL service account'
    }

    $acl = Get-Acl -LiteralPath $stagingRoot
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Users', 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $stagingRoot -AclObject $acl

    $inventoryScript = Join-Path $trainingRoot 'build-inventory.ps1'
    @'
$output = 'C:\ProgramData\IHPL\Training\build-inventory.log'
Get-Service Jenkins | Select-Object Name, Status | Out-File -FilePath $output -Append
$command = 'C:\ProgramData\IHPL\Staging\release.cmd'
if (Test-Path -LiteralPath $command) {
    & $env:ComSpec /d /c $command *>> $output
}
'@ | Set-Content -LiteralPath $inventoryScript -Encoding UTF8

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -File `"$inventoryScript`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName 'IHPL Build Inventory' -TaskPath '\IHPL\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    @'
@echo off
whoami > C:\ProgramData\IHPL\Training\release-command.log
'@ | Set-Content -LiteralPath (Join-Path $stagingRoot 'release.cmd') -Encoding ASCII

    Write-Host '[Assembly] Functional findings installed, including the writable SYSTEM command path.'
}

function Save-VerifiedMsi {
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
    }
    $signature = Get-AuthenticodeSignature -FilePath $Destination
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Authenticode verification failed for $Destination ($($signature.Status))."
    }
}

function Find-CompatibleJavaHome {
    [CmdletBinding()]
    param()

    $candidates = @(
        $env:JAVA_HOME
        [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
    )

    $javaCommand = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($null -ne $javaCommand) {
        $candidates += Split-Path -Parent (Split-Path -Parent $javaCommand.Source)
    }

    $programFilesRoots = @(
        $env:ProgramW6432
        $env:ProgramFiles
        [Environment]::GetEnvironmentVariable('ProgramW6432', 'Machine')
        [Environment]::GetEnvironmentVariable('ProgramFiles', 'Machine')
        'C:\Program Files'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($programFilesRoot in $programFilesRoots) {
        foreach ($vendor in @('Microsoft', 'Java', 'Eclipse Adoptium')) {
            $root = Join-Path $programFilesRoot $vendor
            if (Test-Path -LiteralPath $root) {
                $candidates += Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                    Sort-Object -Property LastWriteTimeUtc -Descending |
                    Select-Object -ExpandProperty FullName
            }
        }
    }

    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        $javaExe = Join-Path $candidate 'bin\java.exe'
        if (-not (Test-Path -LiteralPath $javaExe)) { continue }
        $versionInfo = (Get-Item -LiteralPath $javaExe).VersionInfo
        $versionText = @($candidate, $versionInfo.FileVersion, $versionInfo.ProductVersion) -join ' '
        if ($versionInfo.FileMajorPart -in @(17, 21) -or
            $versionInfo.ProductMajorPart -in @(17, 21) -or
            $versionText -match '(?<!\d)(17|21)(?!\d)') {
            return $candidate
        }
    }

    return $null
}

function Wait-HttpReady {
    param([Parameter(Mandatory)][string]$Uri, [int]$Attempts = 60)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) { return }
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
    throw "Service did not become ready at $Uri."
}

try {
    Write-Host '[Assembly] Enabling RDP and creating scored accounts...'
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Type DWord -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Type DWord -Value 1
    if (-not (Get-NetFirewallRule -DisplayName 'IHPL RDP 3389' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'IHPL RDP 3389' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -Profile Any | Out-Null
    }
    Ensure-IhplLocalUser -Name 'plinktern' -Password $StarterPassword -Groups @('Administrators', 'Remote Desktop Users')
    Ensure-IhplLocalUser -Name 'jmoney' -Password $StarterPassword -Groups @('Remote Desktop Users')
    Assert-IhplScoredAccounts

    Write-Host '[Assembly] Installing Microsoft OpenJDK 17 when needed...'
    $javaHome = Find-CompatibleJavaHome
    if ($null -eq $javaHome) {
        $jdkMsi = Join-Path $DownloadRoot 'microsoft-jdk-17.msi'
        $jdkLog = Join-Path $LogRoot 'openjdk-msi.log'
        Save-VerifiedMsi -Uri 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.msi' -Destination $jdkMsi
        $process = Start-Process msiexec.exe -ArgumentList @('/i', $jdkMsi, '/qn', '/norestart', '/L*v', $jdkLog) -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { throw "OpenJDK installer exited with $($process.ExitCode). See $jdkLog." }
        $javaHome = Find-CompatibleJavaHome
    }
    if ($null -eq $javaHome) {
        throw 'A compatible Java 17 or Java 21 installation could not be located after OpenJDK setup.'
    }
    Write-Host "[Assembly] Using Java home: $javaHome"
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'Machine')
    $env:JAVA_HOME = $javaHome
    $env:Path = "$(Join-Path $javaHome 'bin');$env:Path"

    [Environment]::SetEnvironmentVariable('JENKINS_HOME', $JenkinsHome, 'Machine')
    Write-Host "[Assembly] Installing Jenkins $JenkinsVersion when needed..."
    $jenkinsService = Get-Service -Name Jenkins -ErrorAction SilentlyContinue
    if ($null -eq $jenkinsService) {
        $jenkinsMsi = Join-Path $DownloadRoot "jenkins-$JenkinsVersion.msi"
        $jenkinsLog = Join-Path $LogRoot 'jenkins-msi.log'
        Save-VerifiedMsi -Uri "https://get.jenkins.io/windows-stable/$JenkinsVersion/jenkins.msi" -Destination $jenkinsMsi
        $jenkinsArguments = @(
            '/i'
            $jenkinsMsi
            '/qn'
            '/norestart'
            "JAVA_HOME=`"$javaHome`""
            'PORT=8080'
            'SERVICE_USERNAME=LocalSystem'
            'SERVICE_LOGON_TYPE=ServiceLocalSystem'
            'JENKINS_ROOT=C:\ProgramData\Jenkins\'
            '/L*v'
            $jenkinsLog
        )
        $process = Start-Process msiexec.exe -ArgumentList $jenkinsArguments -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            $failure = $null
            if (Test-Path -LiteralPath $jenkinsLog) {
                $failure = Select-String -LiteralPath $jenkinsLog -Pattern 'Return value 3' -Context 8, 2 | Select-Object -Last 1
            }
            if ($null -ne $failure) {
                Write-Host '[Assembly] Jenkins MSI failure context:'
                $failure.Context.PreContext | ForEach-Object { Write-Host $_ }
                Write-Host $failure.Line
                $failure.Context.PostContext | ForEach-Object { Write-Host $_ }
            }
            throw "Jenkins installer exited with $($process.ExitCode). See $jenkinsLog."
        }
    }
    else {
        Stop-Service -Name Jenkins -Force -ErrorAction SilentlyContinue
    }

    if (-not (Get-NetFirewallRule -DisplayName 'IHPL Jenkins 8080' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'IHPL Jenkins 8080' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -Profile Any | Out-Null
    }

    Write-Host '[Assembly] Seeding Jenkins security and jobs...'
    $initDirectory = Join-Path $JenkinsHome 'init.groovy.d'
    New-Item -ItemType Directory -Force -Path $initDirectory | Out-Null
    $groovyTemplate = @'
import jenkins.model.Jenkins
import jenkins.install.InstallState
import hudson.model.FreeStyleProject
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.tasks.BatchFile
import hudson.triggers.TimerTrigger

def instance = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount('jmoney', '__STARTER_PASSWORD__')
realm.createAccount('plinktern', '__STARTER_PASSWORD__')
realm.createAccount('buildsvc', 'RocketBuild-Temp-2026!')
realm.createAccount('former.intern', 'Fortuna-Archive-2026!')
instance.setSecurityRealm(realm)

def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(true)
instance.setAuthorizationStrategy(authorization)

def configureJob = { String name, String description, String command ->
    def job = instance.getItem(name)
    if (job == null) job = instance.createProject(FreeStyleProject, name)
    job.setDescription(description)
    job.getBuildersList().clear()
    job.getBuildersList().add(new BatchFile(command))
    job.getTriggers().values().toList().each { trigger -> job.removeTrigger(trigger.getDescriptor()) }
    job.addTrigger(new TimerTrigger('* * * * *'))
    job.save()
    job.scheduleBuild2(5)
}

configureJob('rocket-build', 'Builds, tests, documents and lints the rocket once a minute.', '''@echo off
setlocal
if not exist C:\ProgramData\IHPL\Builds mkdir C:\ProgramData\IHPL\Builds
echo [1/4] Compiling EQUUS flight package
echo [2/4] Running 14 flight tests -- 14 passed
echo [3/4] Publishing rocket documentation
echo [4/4] Linting guidance definitions -- clean
echo SUCCESS %DATE% %TIME%>C:\ProgramData\IHPL\Builds\rocket-build-latest.txt
exit /b 0''')

configureJob('mysql-database-backup', 'Validates Manifest MariaDB connectivity and writes a backup manifest once a minute.', '''@echo off
setlocal
if not exist C:\ProgramData\IHPL\Builds mkdir C:\ProgramData\IHPL\Builds
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$ok = Test-NetConnection -ComputerName '__MANIFEST_IP__' -Port 3306 -InformationLevel Quiet; if (-not $ok) { exit 1 }"
if errorlevel 1 exit /b 1
echo MANIFEST DATABASE REACHABLE %DATE% %TIME%>C:\ProgramData\IHPL\Builds\mysql-database-backup-latest.txt
exit /b 0''')

instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
instance.save()
'@
    $groovy = $groovyTemplate.Replace('__STARTER_PASSWORD__', $StarterPassword).Replace('__MANIFEST_IP__', $ManifestIp)
    Set-Content -LiteralPath (Join-Path $initDirectory '10-ihpl-bootstrap.groovy') -Value $groovy -Encoding UTF8

    Set-Service -Name Jenkins -StartupType Automatic
    Start-Service -Name Jenkins
    Wait-HttpReady -Uri 'http://127.0.0.1:8080/login' -Attempts 60

    if (-not $SkipTrainingArtifacts) {
        Write-Host '[Assembly] Planting incident-response findings...'
        Install-IhplTrainingArtifacts -StarterPassword $StarterPassword
    }

    if ((Get-Service -Name Jenkins).Status -ne 'Running') { throw 'Jenkins is not running.' }
    if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 8080 -InformationLevel Quiet)) { throw 'Jenkins TCP 8080 is not reachable.' }
    Write-Host "[Assembly] Ready: http://$AssemblyIp`:8080/"
}
finally {
    Stop-Transcript | Out-Null
}
