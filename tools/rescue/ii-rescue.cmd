@echo off
rem Double-click (or run from Task Manager > Run new task) to restore the normal Windows desktop.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ii-rescue.ps1" -RestartExplorer
