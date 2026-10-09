@echo off
rem ii-windows: report a problem (diagnostics file on the Desktop + the GitHub bug form).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ii-report.ps1"
