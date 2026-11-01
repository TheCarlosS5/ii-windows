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

# One task, through the Task Scheduler's COM API (Schedule.Service). Not Get-ScheduledTask: that one lists every task
# of the PC first and fails for all of them when a single task is broken (which the old \ii-windows can leave, see
# Install-IiAutostart). $null when there is no such task (or it cannot be loaded). The fields ii looks at, named like
# Get-ScheduledTask's: Description, Principal.UserId / RunLevel, Actions[].Execute, Triggers[].Kind,
# Settings.MultipleInstances.
function Get-IiTaskFolderObject([string]$TaskPath, [switch]$Create) {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $path = '\' + $TaskPath.Trim('\')
    try { return $svc.GetFolder($path) } catch { if (-not $Create) { return $null } }
    $svc.GetFolder('\').CreateFolder($path.TrimStart('\'), $null)
}

function Get-IiLogonTask([string]$TaskPath, [string]$TaskName) {
    $folder = Get-IiTaskFolderObject $TaskPath
    if (-not $folder) { return $null }
    try { $t = $folder.GetTask($TaskName) } catch { return $null }
    $d = $t.Definition
    $actions = @(foreach ($a in $d.Actions) { if ($a.Type -eq 0) { [pscustomobject]@{ Execute = $a.Path; Arguments = $a.Arguments } } })
    $triggers = @(foreach ($tr in $d.Triggers) { [pscustomobject]@{ Kind = $(if ($tr.Type -eq 9) { 'Logon' } else { "type $($tr.Type)" }) } })
    [pscustomobject]@{
        TaskName = $t.Name; TaskPath = $TaskPath; Xml = $t.Xml
        Description = [string]$d.RegistrationInfo.Description
        Principal = [pscustomobject]@{ UserId = [string]$d.Principal.UserId; RunLevel = $(if ($d.Principal.RunLevel -eq 1) { 'Highest' } else { 'Limited' }) }
        Actions = $actions; Triggers = $triggers
        Settings = [pscustomobject]@{ MultipleInstances = @('Parallel', 'Queue', 'IgnoreNew', 'StopExisting')[[int]$d.Settings.MultipleInstances] }
    }
}

function Remove-IiLogonTask([string]$TaskPath, [string]$TaskName) {
    (Get-IiTaskFolderObject $TaskPath).DeleteTask($TaskName, 0)
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
    $register = {
        Register-ScheduledTask -TaskName $name -TaskPath $TaskPath -Description $description -Trigger $trigger -Action $action `
            -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    }

    # The old flat task \ii-windows has the name of the new folder \ii-windows\: a task and a folder cannot share it
    # (the folder would be made over the task's file, and removing the old task afterwards takes the new one's
    # registration with it, leaving a task Windows can no longer load and Get-ScheduledTask failing for every task of
    # the PC). So when they collide, the old one goes first; if the new one cannot be registered, it is put back.
    $legacy = Get-IiLogonTask $LegacyTaskPath $LegacyTaskName
    $legacyOwnership = Get-IiTaskOwnership $legacy $Sid $InstallDir -Legacy
    $collides = ($LegacyTaskPath.TrimEnd('\') + '\' + $LegacyTaskName + '\') -ieq ('\' + $TaskPath.Trim('\') + '\')
    if ($collides -and $legacyOwnership -eq 'foreign') {
        $result.Conflicts += "La tarea antigua $LegacyTaskPath$LegacyTaskName no es de esta instalación o de este usuario y ocupa el nombre de la carpeta $TaskPath`: no se registra el inicio automático."
        return $result
    }
    if ($collides -and $legacyOwnership -eq 'legacy-own') {
        $saved = $legacy.Xml
        Remove-IiLogonTask $LegacyTaskPath $LegacyTaskName
        try { & $register }
        catch {
            try { (Get-IiTaskFolderObject $LegacyTaskPath).RegisterTask($LegacyTaskName, $saved, 6, $null, $null, 3) | Out-Null } catch {}
            throw
        }
        $result.Migrated = $true
    } else {
        & $register
        # The old flat task elsewhere: migrated only when it is provably ours, once the new one is in place.
        switch ($legacyOwnership) {
            'legacy-own' {
                Remove-IiLogonTask $LegacyTaskPath $LegacyTaskName
                $result.Migrated = $true
            }
            'foreign' { $result.Conflicts += "La tarea antigua $LegacyTaskPath$LegacyTaskName no es de esta instalación o de este usuario: se conserva." }
        }
    }

    # Registered is what Windows can load, not what Register-ScheduledTask said: on a PC whose Task Scheduler already
    # has the broken old task, registering "works" and the task never runs.
    & schtasks.exe /query /tn "$TaskPath$name" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $result.Registered = $true
    } else {
        $result.Conflicts += "Windows no puede cargar la tarea $TaskPath$name (el Programador de tareas tiene dañada la tarea antigua \ii-windows). Arréglalo una vez desde una terminal de administrador: schtasks /delete /tn \ii-windows /f ; y vuelve a instalar."
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
        'own' { Remove-IiLogonTask $TaskPath $name; $result.Removed += "$TaskPath$name" }
        'foreign' { $result.Kept += "$TaskPath$name" }
    }
    $legacy = Get-IiLogonTask $LegacyTaskPath $LegacyTaskName
    switch (Get-IiTaskOwnership $legacy $Sid $InstallDir -Legacy) {
        'legacy-own' { Remove-IiLogonTask $LegacyTaskPath $LegacyTaskName; $result.Removed += "$LegacyTaskPath$LegacyTaskName" }
        'foreign' { $result.Kept += "$LegacyTaskPath$LegacyTaskName" }
    }
    $result
}
