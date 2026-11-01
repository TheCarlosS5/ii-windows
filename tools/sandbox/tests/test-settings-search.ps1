# Plan 2026-10-31, C3/C8: Configuración's search finds what people type (tests\settings-search\terms.json, >= 95 %), and
# its index covers the pages (needs a staged tree: tools\dev\stage-ii.ps1).
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path "$repo\build\ii\modules\settings\settings-index.js")) { Skip-Test 'no staged tree (tools\dev\stage-ii.ps1)' }
$env:PYTHONIOENCODING = 'utf-8'
$out = & python -I "$repo\tools\dev\check-settings-search.py" 2>&1
$out | Select-Object -Last 20 | ForEach-Object { Write-Output $_ }
Assert-Equal $LASTEXITCODE 0 'search finds 95 % of the terms'
$count = [int](([regex]::Match(($out -join "`n"), '(\d+) entries')).Groups[1].Value)
Assert-True ($count -ge 250) "index has $count entries (>= 250)"
Complete-IiTest
