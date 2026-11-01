# Plan 2026-10-31, E13: the look that follows the day. The decisions under Node (tests\dailylook\test.js) and, with
# -Network, Bing's image of the day downloaded by ii-shim (saved in a temporary folder, the wallpaper is not changed).
param([switch]$Network)
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Skip-Test 'node not found' }
$text = & $node.Source "$repo\tests\dailylook\test.js" 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "dailylook_logic.js: $($text.Trim())"
if ($Network) {
    $shim = Get-IiShim
    $out = Join-Path $env:TEMP "ii-test-bing-$PID"
    try {
        $log = & $shim randomwall bing --no-apply --out $out 2>&1 | Out-String
        Assert-True ($LASTEXITCODE -eq 0) "randomwall bing: $($log.Trim())"
        $file = Get-ChildItem $out -Filter 'bing_wallpaper*.jpg' -ErrorAction SilentlyContinue | Select-Object -First 1
        Assert-True ($null -ne $file -and $file.Length -gt 100KB) "the image of the day was saved ($($file.Length) bytes)"
        if ($file) {
            $head = [System.IO.File]::ReadAllBytes($file.FullName)[0..1]
            Assert-True ($head[0] -eq 0xFF -and $head[1] -eq 0xD8) 'it is a JPEG'
        }
    } finally { Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue }
}
Complete-IiTest
