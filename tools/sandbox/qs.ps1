# Host side: run quickshell INSIDE the sandbox on a config, then collect log + screenshot.
#   qs.ps1 -Config C:\ii\build\ii [-Seconds 15] [-Shot name] [-Grep pattern] [-Tail 80]
# Paths are sandbox paths (C:\ii = the repo, read-only).
param(
    [string]$Config = 'C:\ii\build\ii',
    [int]$Seconds = 15,
    [string]$Shot = 'qs',
    [string]$Extra = '',
    [int]$Tail = 80,
    [switch]$Host2,  # also start ii-host (taskbar hidden, shortcuts) before the shell
    [switch]$Seed    # put build\seed\colors.json + wallpaper in place before starting
)
$seedScript = @'
$state = "$env:LOCALAPPDATA\quickshell\State\user\generated"
New-Item -ItemType Directory -Force $state | Out-Null
Copy-Item C:\ii\build\seed\colors.json "$state\colors.json" -Force
$pics = "$env:USERPROFILE\Pictures"
New-Item -ItemType Directory -Force $pics | Out-Null
Copy-Item C:\ii\build\seed\wallpaper.jpg "$pics\ii-wallpaper.jpg" -Force
$cfgPath = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $cfg.background.wallpaperPath = ("$pics\ii-wallpaper.jpg" -replace '\\', '/')
    $cfg | ConvertTo-Json -Depth 32 | Set-Content -Encoding utf8 $cfgPath
    'seeded config wallpaperPath=' + $cfg.background.wallpaperPath
} else {
    New-Item -ItemType Directory -Force (Split-Path $cfgPath) | Out-Null
    @{ background = @{ wallpaperPath = ("$pics\ii-wallpaper.jpg" -replace '\\', '/') } } | ConvertTo-Json | Set-Content -Encoding utf8 $cfgPath
    'seeded minimal config'
}
'@
$script = Join-Path $env:TEMP 'sbx-qs-run.ps1'
@"
`$ErrorActionPreference = 'Continue'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "`$env:TEMP\quickshell" -Recurse -Force -ErrorAction SilentlyContinue
`$env:QT_FORCE_STDERR_LOGGING = '1'
# mapped folders are slow to scan; run from the sandbox's own disk
`$local = "`$env:USERPROFILE\qs-config"
robocopy "$Config" `$local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$(if ($Seed) { $seedScript })
$(if ($Host2) { "Start-Process C:\ii\host\build\ii-host.exe; Start-Sleep 2" })
`$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
`$psi.Arguments = '-p "' + `$local + '" $Extra'
`$psi.UseShellExecute = `$false
`$psi.CreateNoWindow = `$true
`$p = [System.Diagnostics.Process]::Start(`$psi)
Start-Sleep $Seconds
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\$Shot.png | Out-Null
`$alive = -not `$p.HasExited
if (`$alive) { `$p.Refresh(); 'quickshell alive: ws={0:N0} MB private={1:N0} MB cpu={2:N1}s' -f (`$p.WorkingSet64/1MB), (`$p.PrivateMemorySize64/1MB), `$p.TotalProcessorTime.TotalSeconds; Stop-Process -Id `$p.Id -Force } else { "quickshell exited with code `$(`$p.ExitCode)" }
$(if ($Host2) { "Start-Process C:\ii\host\build\ii-host.exe -ArgumentList '--rescue' -Wait" })
Start-Sleep 1
`$log = Get-ChildItem "`$env:TEMP\quickshell\by-id\*\log.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
if (`$log) { Copy-Item `$log.FullName C:\xchg\outbox\$Shot.log; Get-Content `$log.FullName | Where-Object { `$_ -notmatch 'DEBUG' } | Select-Object -Last $Tail } else { 'no log' }
"@ | Set-Content -Encoding utf8 $script
& "$PSScriptRoot\sbx.ps1" run $script -Timeout ($Seconds + 90)
