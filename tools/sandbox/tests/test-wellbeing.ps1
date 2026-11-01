# Plan 2026-10-31, E11: wellbeing's decisions under Node (tests\wellbeing\test.js): daily limits once a day, eye breaks
# every 20 min of use, the week's summary. (Checked end to end by hand: both notices reach the notification server.)
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Skip-Test 'node not found' }
$text = & $node.Source "$repo\tests\wellbeing\test.js" 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "wellbeing_logic.js: $($text.Trim())"
Complete-IiTest
