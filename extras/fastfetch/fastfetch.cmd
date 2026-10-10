@echo off
rem ii-windows: `fastfetch` with ii's look, without ever overriding what you ask for.
rem
rem   1. What you type wins: with -c/--config nothing of ii's is added; with --logo/-l/--logo-* ii's
rem      logo is not added (its config still is).
rem   2. Your own config: the file in %II_FASTFETCH_CONFIG%, or %LOCALAPPDATA%\ii-windows\fastfetch.jsonc.
rem   3. Otherwise ii's config and its "ii" logo (an ASCII one when the terminal cannot show Unicode;
rem      II_FASTFETCH_ASCII=1 forces it).
rem A fastfetch you installed yourself and that comes earlier on PATH takes precedence over this command.
rem Extra arguments are passed on (e.g. fastfetch --pipe).
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0.."
set "FF=%ROOT%\fastfetch"
set "II_VERSION=dev"
set "ACTIVE="
rem Installed with versions: the active version's own folder (current.txt is written by the installer).
if exist "%ROOT%\current.txt" (
  for /f "usebackq tokens=1,* delims==" %%a in ("%ROOT%\current.txt") do if /i "%%a"=="active" set "ACTIVE=%%b"
)
if defined ACTIVE if /i not "!ACTIVE!"=="legacy" if exist "%ROOT%\versions\!ACTIVE!\fastfetch\fastfetch.exe" (
  set "FF=%ROOT%\versions\!ACTIVE!\fastfetch"
  set "II_VERSION=!ACTIVE!"
)
if not exist "%FF%\fastfetch.exe" (
  echo fastfetch is not part of this ii-windows installation ^(%FF%\fastfetch.exe^). Nothing was run.
  exit /b 1
)

set "USER_CONFIG="
set "USER_LOGO="
for %%a in (%*) do (
  set "arg=%%~a"
  if /i "!arg!"=="-c" set "USER_CONFIG=1"
  if /i "!arg!"=="--config" set "USER_CONFIG=1"
  if /i "!arg:~0,6!"=="--logo" set "USER_LOGO=1"
  if /i "!arg!"=="-l" set "USER_LOGO=1"
)
if defined USER_CONFIG (
  "%FF%\fastfetch.exe" %*
  exit /b !errorlevel!
)

set "CFG=%FF%\ii.jsonc"
set "OURS=1"
if defined II_FASTFETCH_CONFIG if exist "%II_FASTFETCH_CONFIG%" (set "CFG=%II_FASTFETCH_CONFIG%" & set "OURS=")
if defined OURS if exist "%LOCALAPPDATA%\ii-windows\fastfetch.jsonc" (set "CFG=%LOCALAPPDATA%\ii-windows\fastfetch.jsonc" & set "OURS=")

if not defined OURS (
  "%FF%\fastfetch.exe" -c "!CFG!" %*
  exit /b !errorlevel!
)
if defined USER_LOGO (
  "%FF%\fastfetch.exe" -c "!CFG!" %*
  exit /b !errorlevel!
)

rem Unicode logo in Windows Terminal or a UTF-8 console; the ASCII one elsewhere.
set "LOGO=%FF%\ii-logo.txt"
set "UNICODE=1"
if not defined WT_SESSION (
  set "CP="
  for /f "tokens=2 delims=:" %%c in ('chcp') do set "CP=%%c"
  set "CP=!CP: =!"
  if not "!CP!"=="65001" set "UNICODE="
)
if "%II_FASTFETCH_ASCII%"=="1" set "UNICODE="
if not defined UNICODE if exist "%FF%\ii-logo-ascii.txt" set "LOGO=%FF%\ii-logo-ascii.txt"
"%FF%\fastfetch.exe" -c "!CFG!" --logo "!LOGO!" %*
exit /b !errorlevel!
