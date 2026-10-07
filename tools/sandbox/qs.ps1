# Host side: run quickshell INSIDE the sandbox on a config, then collect log + screenshot.
#   qs.ps1 -Config C:\ii\build\ii [-Seconds 15] [-Shot name] [-Grep pattern] [-Tail 80]
# Paths are sandbox paths (C:\ii = the repo, read-only).
param(
    [string]$Config = 'C:\ii\build\ii',
    [int]$Seconds = 15,
    [string]$Shot = 'qs',
    [string]$Extra = '',
    [int]$Tail = 80,
    [switch]$Host2   # also start ii-host (taskbar hidden, shortcuts) before the shell
)
$script = Join-Path $env:TEMP 'sbx-qs-run.ps1'
@"
`$ErrorActionPreference = 'Continue'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "`$env:TEMP\quickshell" -Recurse -Force -ErrorAction SilentlyContinue
`$env:QT_FORCE_STDERR_LOGGING = '1'
# mapped folders are slow to scan; run from the sandbox's own disk
`$local = "`$env:USERPROFILE\qs-config"
robocopy "$Config" `$local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
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
