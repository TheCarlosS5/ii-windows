# INSIDE the sandbox: notification lines from the most recent quickshell logs.
Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 3 | ForEach-Object {
    "== $($_.FullName) $($_.LastWriteTime)"
    Get-Content $_.FullName | Where-Object { $_ -match 'notif|Notif|ERROR|FATAL' } | Select-Object -First 10
}
