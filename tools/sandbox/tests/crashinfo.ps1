$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-Object -Last 12
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 2 -ErrorAction SilentlyContinue | ForEach-Object { $_.Message -split "`n" | Select-Object -First 12 }
