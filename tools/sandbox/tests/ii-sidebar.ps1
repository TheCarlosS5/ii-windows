# INSIDE the sandbox: the shell loads with the Windows sidebar patches, the right sidebar opens
# (screenshot), its night light dialog opens, `ii-shim nightlight` answers, and the rescue
# leaves the gamma backup cleaned up.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
Check 'shell running' ([bool](Get-Process quickshell -ErrorAction SilentlyContinue))
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\sb-1-sidebar.png" | Out-Null
"nightlight status: $(& "$dist\bin\ii-shim.exe" nightlight status 2>&1)"
"nightlight 4500: $(& "$dist\bin\ii-shim.exe" nightlight 4500 2>&1) (exit $LASTEXITCODE)"
Start-Sleep 2
"nightlight status: $(& "$dist\bin\ii-shim.exe" nightlight status 2>&1)"
"nightlight off: $(& "$dist\bin\ii-shim.exe" nightlight off 2>&1) (exit $LASTEXITCODE)"
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'ERROR|sidebarRight|Sidebar|nightlight|Hyprsunset' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 12
& "$hostDir\ii-host.exe" --rescue
Start-Sleep 2
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" -Tail 8
"fails: $script:fails"
