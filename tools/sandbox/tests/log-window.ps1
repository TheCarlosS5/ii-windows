$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
$lines = Get-Content $log.FullName
$i = ($lines | Select-String 'virtual key= 0x43' | Select-Object -First 1).LineNumber
$lines[($i - 3)..($i + 30)] | Where-Object { $_ -notmatch 'handleGeometryChange|updatePossibleKeyCodes' }
