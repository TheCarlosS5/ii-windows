# ii's start-at-logon task, owned per user (R06). Dot-sourced by install.ps1, uninstall.ps1,
# autostart-task.ps1 and the tests.
#
#   - the task lives in its own folder and is named after the user's SID: \ii-windows\Logon-<SID>
#     (a durable identity: user names change, SIDs do not), and says so in its description;
#   - installing replaces only a task that carries this user's owner marker; removing removes only
#     that. A task with the same name registered by someone else is reported and left alone;
#   - the old flat task \ii-windows (every version up to 0.1.3) is migrated only if it is provably
#     this user's and this installation's (runs as this SID, starts a program inside this install
#     folder); otherwise it stays, and the conflict is reported;
#   - it runs as the user, limited (no elevation); the shell is never started with more rights.

$script:IiTaskFolder = '\ii-windows\'
$script:IiLegacyTaskPath = '\'
$script:IiLegacyTaskName = 'ii-windows'

function Get-IiUserSid { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }

function Get-IiOwnerMarker([string]$Sid) { "[ii-windows-owner:$Sid]" }

function Convert-IiAccountToSid([string]$Account) {
    if (-not $Account) { return $null }
    try { return (New-Object Security.Principal.NTAccount($Account)).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch { return $null }
}

function Test-IiUnder([string]$Path, [string]$Dir) {
    if (-not $Path -or -not $Dir) { return $false }
    try {
        $p = [IO.Path]::GetFullPath($Path.Trim('"'))
        $d = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
    } catch { return $false }
    if ($d.Length -le 3) { return $false }
    $p.StartsWith($d + '\', [StringComparison]::OrdinalIgnoreCase)
}

# 'none' (no such task) | 'own' (carries this SID's marker) | 'legacy-own' (the old flat task,
# provably this user's and this installation's) | 'foreign' (anything else with that name).
function Get-IiTaskOwnership($Task, [string]$Sid, [string]$InstallDir, [switch]$Legacy) {
    if (-not $Task) { return 'none' }
    if (-not $Legacy) {
        if (([string]$Task.Description).Contains((Get-IiOwnerMarker $Sid))) { return 'own' }
        return 'foreign'
    }
    $runsAsUs = (Convert-IiAccountToSid ([string]$Task.Principal.UserId)) -eq $Sid
    $exe = if (@($Task.Actions).Count -gt 0) { [string]@($Task.Actions)[0].Execute } else { '' }
    if ($runsAsUs -and (Test-IiUnder $exe $InstallDir)) { return 'legacy-own' }
    return 'foreign'
}

function Get-IiLogonTask([string]$TaskPath, [string]$TaskName) {
    Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
}

# Registers (or updates) this user's logon task. Returns @{ Registered; Migrated; Conflicts[] }.
function Install-IiAutostart {
    param(
        [Parameter(Mandatory)][string]$Sid, [Parameter(Mandatory)][string]$User, [Parameter(Mandatory)][string]$HostExe,
        [Parameter(Mandatory)][string]$Arguments, [Parameter(Mandatory)][string]$InstallDir,
        [string]$Version = 'dev', [string]$TaskPath = $script:IiTaskFolder,
        [string]$LegacyTaskPath = $script:IiLegacyTaskPath, [string]$LegacyTaskName = $script:IiLegacyTaskName
    )
    $result = [pscustomobject]@{ Registered = $false; Migrated = $false; Conflicts = @() }
    $name = "Logon-$Sid"

    $existing = Get-IiLogonTask $TaskPath $name
    if ((Get-IiTaskOwnership $existing $Sid $InstallDir) -eq 'foreign') {
        $result.Conflicts += "Ya existe la tarea $TaskPath$name y no es de este usuario: no se toca."
        return $result
    }

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
    $action = New-ScheduledTaskAction -Execute $HostExe -Argument $Arguments -WorkingDirectory (Split-Path $HostExe)
    $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
    # ii-host sets its own priority (high while booting, then normal); no time limit; laptops on
    # battery too; one instance.
    $settings = New-ScheduledTaskSettingsSet -Priority 4 -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable:$false
    $description = "Inicia ii-windows (illogical-impulse) al entrar en Windows. $(Get-IiOwnerMarker $Sid) [version:$Version]"
    Register-ScheduledTask -TaskName $name -TaskPath $TaskPath -Description $description -Trigger $trigger -Action $action `
        -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    $result.Registered = $true

    # The old flat task: migrate it only when it is provably ours, once the new one is in place.
    $legacy = Get-IiLogonTask $LegacyTaskPath $LegacyTaskName
    switch (Get-IiTaskOwnership $legacy $Sid $InstallDir -Legacy) {
        'legacy-own' {
            Unregister-ScheduledTask -TaskPath $LegacyTaskPath -TaskName $LegacyTaskName -Confirm:$false -ErrorAction Stop
            $result.Migrated = $true
        }
        'foreign' { $result.Conflicts += "La tarea antigua $LegacyTaskPath$LegacyTaskName no es de esta instalación o de este usuario: se conserva." }
    }
    $result
}

# Removes this user's task (and the old flat one if it is provably ours). Others are left alone.
function Remove-IiAutostart {
    param(
        [Parameter(Mandatory)][string]$Sid, [Parameter(Mandatory)][string]$InstallDir, [string]$TaskPath = $script:IiTaskFolder,
        [string]$LegacyTaskPath = $script:IiLegacyTaskPath, [string]$LegacyTaskName = $script:IiLegacyTaskName
    )
    $result = [pscustomobject]@{ Removed = @(); Kept = @() }
    $name = "Logon-$Sid"
    $existing = Get-IiLogonTask $TaskPath $name
    switch (Get-IiTaskOwnership $existing $Sid $InstallDir) {
        'own' { Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $name -Confirm:$false -ErrorAction Stop; $result.Removed += "$TaskPath$name" }
        'foreign' { $result.Kept += "$TaskPath$name" }
    }
    $legacy = Get-IiLogonTask $LegacyTaskPath $LegacyTaskName
    switch (Get-IiTaskOwnership $legacy $Sid $InstallDir -Legacy) {
        'legacy-own' { Unregister-ScheduledTask -TaskPath $LegacyTaskPath -TaskName $LegacyTaskName -Confirm:$false -ErrorAction Stop; $result.Removed += "$LegacyTaskPath$LegacyTaskName" }
        'foreign' { $result.Kept += "$LegacyTaskPath$LegacyTaskName" }
    }
    $result
}
