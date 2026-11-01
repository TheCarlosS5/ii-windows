# Plan 2026-10-31, H1: every text of the modules ii-windows uses has its Spanish (needs a staged tree: tools\dev\stage-ii.ps1).
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path "$repo\build\ii\translations\es_MX.json")) { Skip-Test 'no staged tree (tools\dev\stage-ii.ps1)' }
$out = & python -I "$repo\tools\dev\find-untranslated.py" 2>&1
$out | Select-Object -Last 20 | ForEach-Object { Write-Output $_ }
Assert-Equal $LASTEXITCODE 0 'no text without Spanish'
Complete-IiTest
