# U01/U02: shared/actions.json is the one list of keyboard actions. The table ii-host swallows, the
# cheatsheet and docs/ATAJOS.md are generated from it, and every shell action it swallows a key for
# must have a listener in the staged QML (a key that is taken and does nothing is a bug). Also runs
# the keyboard router's own test (host\build\ii-keyrouter-test.exe) if it is built.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

& python -I (Join-Path $repo 'tools\dev\gen-actions.py') --check 2>&1 | Out-String | ForEach-Object { Write-Output $_.Trim() }
Assert-Equal $LASTEXITCODE 0 'host/src/shortcuts_table.inc, the cheatsheet and docs/ATAJOS.md are current with shared/actions.json'

if (Test-Path (Join-Path $repo 'upstream\dots\.config\quickshell\ii')) {
    $dest = Join-Path $env:TEMP ('ii-actions-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\stage-ii.ps1') -Dest $dest | Out-Null
        Assert-Equal $LASTEXITCODE 0 'staging works'
        $out = & python -I (Join-Path $repo 'tools\dev\gen-actions.py') --check --consumers $dest 2>&1 | Out-String
        Assert-True ($LASTEXITCODE -eq 0) "every shell action that swallows a key has a GlobalShortcut listener in the QML ($($out.Trim()))"
    }
    finally { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
}

# Catalog sanity beyond the generator: no key listed as swallowed that Windows needs for itself.
$catalog = Get-Content (Join-Path $repo 'shared\actions.json') -Raw | ConvertFrom-Json
$swallowed = @($catalog.actions | Where-Object { $_.target.kind -in 'shell', 'host' } | ForEach-Object { $a = $_; $_.keys | Where-Object { $_.swallow -ne $false } | ForEach-Object { [pscustomobject]@{ id = $a.id; mods = ($_.mods -join '+'); key = $_.key } } })
Assert-True ($swallowed.Count -gt 30) "$($swallowed.Count) key combinations are taken by ii"
foreach ($reserved in @(@('win', 'L'), @('ctrl+alt', 'Delete'), @('win', 'E'), @('win', 'P'), @('alt', 'Tab'), @('ctrl+shift', 'Escape'))) {
    $clash = @($swallowed | Where-Object { $_.mods -eq $reserved[0] -and $_.key -eq $reserved[1] })
    Assert-Equal $clash.Count 0 "$($reserved[0]) + $($reserved[1]) stays with Windows (not taken by ii)"
}
Assert-Equal @($catalog.actions | Where-Object { $_.support -ne 'available' -and -not $_.reason }).Count 0 'every limit is explained (no partial/external action without a reason)'

$test = Join-Path $repo 'host\build\ii-keyrouter-test.exe'
if (Test-Path $test) {
    $text = & $test | Out-String
    Assert-True ($LASTEXITCODE -eq 0 -and $text -match '0 failed') "the keyboard router's own checks pass ($($text.Trim().Split("`n")[-1].Trim()))"
} else { Write-Output 'ii-keyrouter-test.exe not built: the router checks were not run' }
Complete-IiTest
