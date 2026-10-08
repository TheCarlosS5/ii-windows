@echo off
rem ii-windows: install for this user (asks before each step).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
