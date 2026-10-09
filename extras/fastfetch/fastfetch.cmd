@echo off
rem ii-windows: `fastfetch` with ii's config. Extra arguments are passed on (e.g. fastfetch --pipe).
"%~dp0..\fastfetch\fastfetch.exe" -c "%~dp0..\fastfetch\ii.jsonc" --logo "%~dp0..\fastfetch\ii-logo.txt" %*
