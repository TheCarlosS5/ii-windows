"build: " + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | ForEach-Object { "$($_.DisplayVersion) $($_.CurrentBuild).$($_.UBR)" })
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "screen $($_.DeviceName) $($_.Bounds) work=$($_.WorkingArea)" }
& C:\ii\tools\dev\windows.ps1 | Select-String 'Shell_TrayWnd|Shell_Secondary|Progman|WorkerW|SHELLDLL|hwnd'
Get-CimInstance Win32_VideoController | Select-Object Name | Format-Table | Out-String
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\sbx-desktop.png | Out-Null; 'shot ok'
