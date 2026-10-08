# INSIDE a fresh sandbox: install and look at ii's first run (no colors.json, no config yet).
$out = 'C:\xchg\outbox'
$zip = (Get-ChildItem C:\ii\out\ii-windows-*.zip | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
$work = "$env:TEMP\ii-firstrun"; Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip $work
$pkg = (Get-ChildItem $work -Directory | Select-Object -First 1).FullName
& powershell -NoProfile -ExecutionPolicy Bypass -File "$pkg\install.ps1" -Yes -StartNow *> $null
Start-Sleep 30
& C:\ii\tools\dev\screenshot.ps1 -Out "$out\firstrun.png" | Out-Null
"colors.json: $(Test-Path "$env:LOCALAPPDATA\quickshell\State\user\generated\colors.json")"
"config.json: $(Test-Path "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json")"
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'ERROR|FATAL|failed to|Failed|first|First|switchwall|wallpaper|Wallpaper|Config' } | Select-Object -First 25
