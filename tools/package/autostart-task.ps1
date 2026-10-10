# ii-windows: the logon task that starts ii as early as possible (Windows delays programs in the
# Run key by several seconds after logon; a logon task starts right away). The task runs ii as the
# normal user, without administrator rights (RunLevel Limited). On some machines creating a task
# with a logon trigger needs administrator rights once; the installer then runs this script
# elevated and reads its result file. The task is owned per user (see ii-autostart.ps1).
#
#   autostart-task.ps1 -Create -User DOMAIN\name -HostExe <ii-host.exe> -Arguments "<args>" -InstallDir <dir> [-Version v] [-ResultFile f.json]
#   autostart-task.ps1 -Remove -InstallDir <dir> [-ResultFile f.json]
# Exit codes: 0 done, 1 error, 2 bad arguments, 3 done but with conflicts to report (see the result file).
param(
    [switch]$Create, [switch]$Remove, [string]$User, [string]$HostExe, [string]$Arguments, [string]$InstallDir,
    [string]$Version = 'dev', [string]$ResultFile = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ii-autostart.ps1')
$sid = Get-IiUserSid
function Save($o) { if ($ResultFile) { $o | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultFile -Encoding UTF8 } }
try {
    if ($Remove) {
        if (-not $InstallDir) { exit 2 }
        $r = Remove-IiAutostart -Sid $sid -InstallDir $InstallDir
        Save $r
        exit 0
    }
    if ($Create) {
        if (-not $User -or -not $HostExe -or -not $Arguments -or -not $InstallDir) { exit 2 }
        $r = Install-IiAutostart -Sid $sid -User $User -HostExe $HostExe -Arguments $Arguments -InstallDir $InstallDir -Version $Version
        Save $r
        if ($r.Conflicts.Count -gt 0 -and -not $r.Registered) { exit 3 }
        exit 0
    }
    exit 2
} catch {
    Save ([pscustomobject]@{ Error = $_.Exception.Message })
    Write-Error $_
    exit 1
}
