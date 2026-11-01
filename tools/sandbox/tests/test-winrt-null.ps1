# Plan 2026-10-31, A6: no WinRT object used without a null check in the native code (the bug class of the 0.6.0 crash).
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$out = & python -I "$repo\tools\dev\check-winrt-null.py" 2>&1
$out | ForEach-Object { Write-Output $_ }
Assert-Equal $LASTEXITCODE 0 'every WinRT object a getter returns is checked before use'
Complete-IiTest
