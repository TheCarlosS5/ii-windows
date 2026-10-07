# Runs INSIDE the sandbox: start the shell (no host), then open each main panel through its
# GlobalShortcut and screenshot it.
$ErrorActionPreference = 'Continue'
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$out\panel-*.png" -ErrorAction SilentlyContinue
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16

foreach ($s in 'searchToggleRelease', 'sidebarRightToggle', 'sidebarLeftToggle', 'cheatsheetToggle', 'sessionToggle', 'mediaControlsToggle', 'overlayToggle', 'wallpaperSelectorToggle') {
    if ($s -eq 'searchToggleRelease') {
        & "$dev\send-shortcut.ps1" -Name $s -PressOnly | Out-Null
        & "$dev\send-shortcut.ps1" -Name $s -ReleaseOnly
    } else {
        & "$dev\send-shortcut.ps1" -Name $s
    }
    Start-Sleep 1.5
    & "$dev\screenshot.ps1" -Out "$out\panel-$s.png" | Out-Null
    # toggle back (search toggles on release after a press)
    if ($s -eq 'searchToggleRelease') {
        & "$dev\send-shortcut.ps1" -Name $s -PressOnly | Out-Null
        & "$dev\send-shortcut.ps1" -Name $s -ReleaseOnly | Out-Null
    } else {
        & "$dev\send-shortcut.ps1" -Name $s | Out-Null
    }
    Start-Sleep 1
}

if (-not $p.HasExited) { $p.Refresh(); 'quickshell: ws={0:N0} MB' -f ($p.WorkingSet64 / 1MB); Stop-Process -Id $p.Id -Force } else { "exited $($p.ExitCode)" }
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'ERROR|WARN|shortcut' -and $_ -notmatch 'proc/|os-release|binary could not be found|polish' } | Select-Object -Last 40
