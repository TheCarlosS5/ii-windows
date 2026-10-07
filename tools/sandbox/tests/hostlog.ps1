$d = "$env:LOCALAPPDATA\ii-windows"
"--- state.ini"; Get-Content "$d\state.ini" -ErrorAction SilentlyContinue
"--- host.log (taskbar/rescue/guard lines)"; Get-Content "$d\host.log" -ErrorAction SilentlyContinue | Where-Object { $_ -match "taskbar|rescue|guard|restore|hide|shutdown|another|autohide|state" } | Select-Object -Last 60
