# INSIDE the sandbox: ii-desktop2 against a packaged build (out\ii-windows-<version>\app) instead of
# dist + build\ii, to tell new failures from old ones.
param([string]$Package = '')
if (-not $Package) { $Package = (Get-ChildItem C:\ii\out -Directory -Filter 'ii-windows-*' | Sort-Object Name | Select-Object -Last 1).FullName }
"package: $Package"
$app = Join-Path $Package 'app'
$test = Get-Content -Raw 'C:\ii\tools\sandbox\tests\ii-desktop2.ps1'
$test = $test.Replace('robocopy C:\ii\build\ii $local', "robocopy `"$app\ii`" `$local").Replace('robocopy C:\ii\dist\quickshell $dist', "robocopy `"$app\quickshell`" `$dist")
$tmp = Join-Path $env:TEMP 'ii-desktop2-pkg-run.ps1'
Set-Content -LiteralPath $tmp -Value $test -Encoding UTF8
& $tmp
