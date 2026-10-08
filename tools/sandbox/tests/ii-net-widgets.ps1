# INSIDE the sandbox: widgets that used curl/jq upstream. Weather on the desktop (wttr.in through
# `ii-shim weather`), the music widget with cover art, and the overlay's floating image (a gif
# downloaded with `ii-shim fetch`).
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
$configPath = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
Remove-Item $configPath -ErrorAction SilentlyContinue

$src = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\media-source.ps1' -PassThru -WindowStyle Hidden
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
# Weather on (ii writes the config back; edit after it exists), next to the photo's default spot.
$cfg = Get-Content $configPath -Raw | ConvertFrom-Json
$cfg.background.widgets.weather.enable = $true
$cfg | ConvertTo-Json -Depth 20 -Compress | Set-Content $configPath -Encoding UTF8
Start-Sleep 20
& "$dev\screenshot.ps1" -Out "$out\net-1-desktop.png" | Out-Null

& "$dev\send-shortcut.ps1" -Name overlayToggle | Out-Null
Start-Sleep 8
& "$dev\screenshot.ps1" -Out "$out\net-2-overlay.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name overlayToggle | Out-Null

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'Weather|weather|ImageDownloader|PlayerControl|fetch' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -First 12
"cover art cache: $((Get-ChildItem "$env:LOCALAPPDATA\quickshell" -Recurse -Include *.img -ErrorAction SilentlyContinue | Measure-Object).Count) files"
& "$hostDir\ii-host.exe" --rescue
Stop-Process -Id $src.Id -Force -ErrorAction SilentlyContinue
"done"
