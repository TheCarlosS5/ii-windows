# Every QML file that the overlay adds or the patches change must at least parse. Stages the tree into
# a temp folder, picks the files that differ from pristine upstream, and runs Qt's qmllint on them,
# failing on syntax-level errors (imports of Quickshell/ii modules can't be resolved by a linter that
# does not know them: those are warnings and are ignored). This is NOT a behaviour test.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$upstream = Join-Path $repo 'upstream\dots\.config\quickshell\ii'
if (-not (Test-Path $upstream)) { Skip-Test 'upstream checkout missing' }
$qmllint = @("$env:USERPROFILE\dev\Qt\bin\qmllint.exe", (Get-Command qmllint -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $qmllint) { Skip-Test 'qmllint not found (Qt bin folder)' }

$dest = Join-Path $env:TEMP ('ii-lint-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\stage-ii.ps1') -Dest $dest | Out-Null
    Assert-Equal $LASTEXITCODE 0 'staging works'
    $changed = @(Get-ChildItem $dest -Recurse -Filter *.qml -File | Where-Object {
        $rel = $_.FullName.Substring($dest.Length + 1)
        $orig = Join-Path $upstream $rel
        -not (Test-Path $orig) -or ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $orig).Hash)
    })
    Assert-True ($changed.Count -gt 20) "$($changed.Count) QML files differ from upstream (overlay + patches)"
    $bad = @()
    foreach ($f in $changed) {
        $out = & $qmllint $f.FullName 2>&1 | Out-String
        $errors = @($out -split "`r?`n" | Where-Object { $_ -match '^Error' -or $_ -match '\[syntax\]|Syntax error|Unexpected token|Expected token' })
        if ($errors.Count -gt 0) { $bad += "$($f.FullName.Substring($dest.Length + 1)): $($errors[0])" }
    }
    Assert-True ($bad.Count -eq 0) ("no syntax errors in the changed files" + $(if ($bad.Count) { ': ' + ($bad -join ' | ') } else { '' }))
}
finally {
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
