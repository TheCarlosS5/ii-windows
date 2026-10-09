# INSIDE the sandbox: ii-host's log and the tail of every quickshell instance log (newest last).
param([int]$Tail = 25)
"=== host.log"
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" -ErrorAction SilentlyContinue | Select-Object -Last 40
foreach ($f in Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime) {
    "=== $($f.FullName) ($(Get-Content $f.FullName -TotalCount 1))"
    Get-Content $f.FullName | Select-String -NotMatch 'Sink added|Source added' | Select-Object -Last $Tail | ForEach-Object { $_.Line }
}
