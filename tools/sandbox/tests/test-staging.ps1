# B00: the runnable QML tree is "upstream untouched + overlay + patches", and that recipe is
# reproducible and fails loudly when the base moves.
#   1. staging twice into clean folders gives byte-identical trees (same tree hash)
#   2. upstream itself is left untouched by staging
#   3. a patch whose expected text is gone from upstream exits non-zero and names the file
# Never touches build\ii or the installed runtime: everything goes to temp folders.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$upstream = Join-Path $repo 'upstream\dots\.config\quickshell\ii'
if (-not (Test-Path $upstream)) { Skip-Test "upstream checkout missing: git clone end-4/dots-hyprland into $repo\upstream (README)" }

function Get-TreeHash([string]$Dir) {
    $root = (Resolve-Path $Dir).Path.TrimEnd('\')
    $lines = Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $_.FullName.Substring($root.Length + 1).Replace('\', '/')
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))) -replace '-', '')
    [pscustomobject]@{ Files = @($lines).Count; Hash = $hash }
}

$base = Join-Path $env:TEMP ('ii-staging-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $base | Out-Null
try {
    $upstreamBefore = Get-TreeHash $upstream

    $a = Join-Path $base 'a'
    $b = Join-Path $base 'b'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\stage-ii.ps1') -Dest $a | Out-Null
    Assert-Equal $LASTEXITCODE 0 'staging into a clean folder succeeds'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\stage-ii.ps1') -Dest $b | Out-Null
    Assert-Equal $LASTEXITCODE 0 'staging again into another clean folder succeeds'
    $ha = Get-TreeHash $a
    $hb = Get-TreeHash $b
    Assert-True ($ha.Files -gt 800) "the staged tree is a full tree ($($ha.Files) files)"
    Assert-Equal $ha.Hash $hb.Hash 'two clean stagings are byte-identical'
    $upstreamAfter = Get-TreeHash $upstream
    Assert-Equal $upstreamAfter.Hash $upstreamBefore.Hash 'upstream was not modified by staging'
    Assert-True ($ha.Files -gt $upstreamBefore.Files) 'the overlay added files on top of upstream'

    # A base that moved: copy upstream, break the text the lock patch looks for, run the patch.
    $moved = Join-Path $base 'moved'
    & robocopy $upstream $moved /E /NFL /NDL /NJH /NJS /NP /XD .git | Out-Null
    $target = Join-Path $moved 'modules\common\panels\lock\LockScreen.qml'
    Assert-PathExists $target 'fixture: the file the patch edits'
    $text = [IO.File]::ReadAllText($target)
    Assert-True ($text.Contains('WlSessionLock {')) 'fixture: the expected text is present before the change'
    [IO.File]::WriteAllText($target, $text.Replace('WlSessionLock {', 'WlSessionLockMoved {'))
    $env:II_STAGE_DIR = $moved
    $out = & python -I (Join-Path $repo 'tools\port\patch_ii_lock.py') 2>&1 | Out-String
    $code = $LASTEXITCODE
    Remove-Item Env:II_STAGE_DIR
    Assert-True ($code -ne 0) "an incompatible upstream makes the patch fail (exit $code)"
    Assert-True ($out -match 'LockScreen\.qml') 'and the message names the file that no longer matches'
    Assert-True ($out -match 'expected 1 match') 'and says what was expected'
    Write-Output ("tree hash {0} ({1} files)" -f $ha.Hash, $ha.Files)
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
