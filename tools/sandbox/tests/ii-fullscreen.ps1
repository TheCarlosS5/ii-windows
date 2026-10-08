# INSIDE the sandbox: with a fullscreen "game" in front, the bar, screen corners and notification
# popups step aside; the overlay (Win+G) still comes over it on demand.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
$game = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\fake-game.ps1' -PassThru
Start-Sleep 4
& "$dist\bin\notify-send.exe" 'Mensaje durante la partida' 'No deberia tapar el juego' -a Discord
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\fs-game.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name overlayToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\fs-overlay.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name overlayToggle | Out-Null
Start-Sleep 1
$game | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\fs-after.png" -H 120 | Out-Null
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'ullscreen|Notification 1' } | Select-Object -Last 8
