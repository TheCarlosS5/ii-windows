@echo off
rem ii-windows: uninstall and restore Windows.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
pause
