Get-Process explorer -ErrorAction SilentlyContinue | Select-Object Id,StartTime,Path | Format-Table | Out-String
& C:\ii\tools\dev\windows.ps1 | Select-String 'Shell_TrayWnd|Progman|SHELLDLL|WorkerW' | Select-Object -First 8
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\inspect2.png | Out-Null
