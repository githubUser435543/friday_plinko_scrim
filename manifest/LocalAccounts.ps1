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
