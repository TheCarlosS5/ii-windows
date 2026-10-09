# INSIDE the sandbox: the loading cover ii-host shows while the shell starts (screenshots), with
# the first-run text (no compiled QML yet), and that it goes away once the shell is up.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$env:LOCALAPPDATA\quickshell\cache\by-shell" -Recurse -Force -ErrorAction SilentlyContinue
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep -Milliseconds 1500
& "$dev\screenshot.ps1" -Out "$out\splash-1.png" | Out-Null
Start-Sleep 25
& "$dev\screenshot.ps1" -Out "$out\splash-2-after.png" | Out-Null
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" | Select-String 'splash' | Select-Object -Last 3 | ForEach-Object { $_.Line }
& "$hostDir\ii-host.exe" --rescue
