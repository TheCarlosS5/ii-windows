$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
"lines: " + (Get-Content $log.FullName).Count
Get-Content $log.FullName | Where-Object { $_ -match 'qpa' } | Select-Object -First 5
Get-Content $log.FullName | Where-Object { $_ -match 'KEY|CHAR|ACTIVATE|FOCUS' } | Select-Object -Last 25
