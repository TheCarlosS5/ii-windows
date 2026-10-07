Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
$env:QT_LOGGING_RULES = 'quickshell.win32*.info=true;quickshell.win32*.debug=true'
$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\s0.png | Out-Null
& C:\ii\tools\dev\send-shortcut.ps1 -Name searchToggleRelease -PressOnly
Start-Sleep 1
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\s1-pressed.png | Out-Null
& C:\ii\tools\dev\send-shortcut.ps1 -Name searchToggleRelease -ReleaseOnly
Start-Sleep 1.5
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\s2-released.png | Out-Null
& C:\ii\tools\dev\zorder.ps1 | Select-Object -First 8
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'win32|ERROR|lock' -and $_ -notmatch 'polish' } | Select-Object -Last 25
