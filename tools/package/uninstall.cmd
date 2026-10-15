@echo off
rem ii-windows: uninstall and restore Windows.
rem   uninstall.cmd                  opens the uninstall window (uninstall-gui.ps1)
rem   uninstall.cmd -Yes [-KeepConfig] [-KeepSecrets]   the console version, no window
if "%~1"=="" if exist "%~dp0uninstall-gui.ps1" (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0uninstall-gui.ps1"
  exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
pause
