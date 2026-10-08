# INSIDE the sandbox: the desktop music widget without music (a note in a morphing shape), then
# with a (silent) media session playing (ii's player card).
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep 16
& "$dev\screenshot.ps1" -Out "$out\media-idle-1.png" | Out-Null
Start-Sleep 5
& "$dev\screenshot.ps1" -Out "$out\media-idle-2.png" | Out-Null
$src = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\media-source.ps1' -PassThru -WindowStyle Hidden
Start-Sleep 8
& "$dev\screenshot.ps1" -Out "$out\media-playing.png" | Out-Null
$src | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'MediaWidget|media/' | Select-Object -Last 5
'done'
