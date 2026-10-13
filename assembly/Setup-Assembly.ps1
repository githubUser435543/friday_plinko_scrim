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

function Get-PlainCredential {
    param([Parameter(Mandatory)][string]$Value)
    return ConvertTo-SecureString -String $Value -AsPlainText -Force
}

function Ensure-LocalRangeUser {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string[]]$Groups
    )
    $securePassword = Get-PlainCredential -Value $Password
    $existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        New-LocalUser -Name $Name -Password $securePassword -PasswordNeverExpires -UserMayNotChangePassword:$false | Out-Null
    }
    else {
        Set-LocalUser -Name $Name -Password $securePassword -PasswordNeverExpires $true
        Enable-LocalUser -Name $Name
    }
    foreach ($group in $Groups) {
        $present = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue | Where-Object Name -Match "\\$([regex]::Escape($Name))$"
        if ($null -eq $present) {
            Add-LocalGroupMember -Group $group -Member $Name
        }
    }
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
    Ensure-LocalRangeUser -Name 'plinktern' -Password $StarterPassword -Groups @('Administrators', 'Remote Desktop Users')
    Ensure-LocalRangeUser -Name 'jmoney' -Password $StarterPassword -Groups @('Remote Desktop Users')

    Write-Host '[Assembly] Installing Microsoft OpenJDK 17 when needed...'
    $javaCommand = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($null -eq $javaCommand) {
        $jdkMsi = Join-Path $DownloadRoot 'microsoft-jdk-17.msi'
        Save-VerifiedMsi -Uri 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.msi' -Destination $jdkMsi
        $process = Start-Process msiexec.exe -ArgumentList @('/i', $jdkMsi, '/qn', '/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { throw "OpenJDK installer exited with $($process.ExitCode)." }
    }

    [Environment]::SetEnvironmentVariable('JENKINS_HOME', $JenkinsHome, 'Machine')
    Write-Host "[Assembly] Installing Jenkins $JenkinsVersion when needed..."
    $jenkinsService = Get-Service -Name Jenkins -ErrorAction SilentlyContinue
    if ($null -eq $jenkinsService) {
        $jenkinsMsi = Join-Path $DownloadRoot "jenkins-$JenkinsVersion.msi"
        Save-VerifiedMsi -Uri "https://get.jenkins.io/windows-stable/$JenkinsVersion/jenkins.msi" -Destination $jenkinsMsi
        $process = Start-Process msiexec.exe -ArgumentList @('/i', $jenkinsMsi, '/qn', '/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { throw "Jenkins installer exited with $($process.ExitCode)." }
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
        Write-Host '[Assembly] Planting inert incident-response artifacts...'
        & (Join-Path $PSScriptRoot 'Install-TrainingArtifacts.ps1')
    }

    if ((Get-Service -Name Jenkins).Status -ne 'Running') { throw 'Jenkins is not running.' }
    if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 8080 -InformationLevel Quiet)) { throw 'Jenkins TCP 8080 is not reachable.' }
    Write-Host "[Assembly] Ready: http://$AssemblyIp`:8080/"
}
finally {
    Stop-Transcript | Out-Null
}
