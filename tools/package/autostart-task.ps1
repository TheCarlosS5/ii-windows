# ii-windows: the logon task that starts ii as early as possible (Windows delays programs in the
# Run key by several seconds after logon; a logon task starts right away). Creating a task with
# a logon trigger needs administrator rights once; the task itself runs ii as the normal user,
# without administrator rights (RunLevel Limited).
#
#   autostart-task.ps1 -Create -User DOMAIN\name -HostExe <ii-host.exe> -Arguments "<args>"
#   autostart-task.ps1 -Remove
param([switch]$Create, [switch]$Remove, [string]$User, [string]$HostExe, [string]$Arguments)
$ErrorActionPreference = 'Stop'
$name = 'ii-windows'
try {
    if ($Remove) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
        exit 0
    }
    if ($Create) {
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
        $action = New-ScheduledTaskAction -Execute $HostExe -Argument $Arguments -WorkingDirectory (Split-Path $HostExe)
        $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
        # ii-host sets its own priority (high while booting, then normal); no time limit; laptops
        # on battery too; one instance.
        $settings = New-ScheduledTaskSettingsSet -Priority 4 -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable:$false
        Register-ScheduledTask -TaskName $name -Description 'Inicia ii-windows (illogical-impulse) al entrar en Windows' `
            -Trigger $trigger -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        exit 0
    }
    exit 2
} catch {
    Write-Error $_
    exit 1
}
