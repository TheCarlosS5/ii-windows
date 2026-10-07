$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'Error|error|Unable|Cannot|undefined|not a' -and $_ -notmatch 'proc/|os-release|binary could not|inode-directory|polish' } | ForEach-Object { $_.Substring([Math]::Min(24, $_.Length)) } | Sort-Object -Unique | Select-Object -First 40
