# INSIDE the sandbox (after firstrun-probe): is the shell alive, what windows, how does its log end.
"processes:"; Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name) $($_.Id) $($_.Path)" }
"--- z-order"; & C:\ii\tools\dev\zorder.ps1 | Select-Object -First 12
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
"--- log tail ($($log.FullName))"; Get-Content $log.FullName | Select-Object -Last 15
"--- host.log"; Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" | Select-Object -Last 12
