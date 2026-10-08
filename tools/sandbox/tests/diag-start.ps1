# INSIDE the sandbox: start ii-host + quickshell like the tests do and print both logs.
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 25
"processes: $((Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', ')"
"--- host.log"
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" -Tail 15
"--- quickshell"
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -notmatch 'btoa' } | Select-Object -Last 15
& "$hostDir\ii-host.exe" --rescue
