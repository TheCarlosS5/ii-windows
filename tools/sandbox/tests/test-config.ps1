# D01: config.json is checked against a schema generated from ii's own Config.qml, a damaged file is kept
# aside and the last good one put back before the shell starts, the last good copy is only stored after
# a start that worked, and settings can be exported/imported without credentials.
# Everything runs in throwaway folders (II_CONFIG_DIR / II_DATA_DIR): the real config.json is only READ,
# as an oracle for the schema (a copy of it is validated), and never written.
# Needs: cmake --build host\build --target ii-config-test ii-host ii-fake-shell ;
#        cmake --build host\build-clang --target ii-shim
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

# ---- A: the tool's own checks (JSON reader, validation, guard, last-good, export, import) --------
$exe = Join-Path $repo 'host\build\ii-config-test.exe'
if (-not (Test-Path $exe)) { Skip-Test 'host\build\ii-config-test.exe is not built' }
$text = & $exe | Out-String
Assert-True ($LASTEXITCODE -eq 0 -and $text -match ' 0 failed') "the config tools' own checks pass ($($text.Trim().Split("`n")[-1].Trim()))"

# ---- B: the schema in the repository is the one the staged Config.qml gives ----------------------
if (Test-Path (Join-Path $repo 'upstream\dots\.config\quickshell\ii')) {
    $stage = Join-Path $env:TEMP ('ii-config-stage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\stage-ii.ps1') -Dest $stage | Out-Null
        Assert-Equal $LASTEXITCODE 0 'staging works'
        $out = & python -I (Join-Path $repo 'tools\dev\gen-config-schema.py') --stage $stage --check 2>&1 | Out-String
        Assert-True ($LASTEXITCODE -eq 0) "shared/config-schema.json and host/src/config_schema.inc are current with Config.qml ($($out.Trim()))"
        $cfg = Get-Content (Join-Path $stage 'modules\common\Config.qml') -Raw
        Assert-True ($cfg -match 'property int configVersion: 1') 'the staged Config.qml declares configVersion'
        Assert-True ($cfg -match 'property bool removeEmptyDesktops: false') 'and still has ii-windows'' own options (R09) in the schema source'
    }
    finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---- C: through ii-shim, on copies ----------------------------------------------------------------
$shim = Join-Path $repo 'host\build-clang\ii-shim.exe'
$base = New-IiTestDir 'ii-config'
$cleanup = @()
try {
    if (Test-Path $shim) {
        $cdir = Join-Path $base 'c-config'
        New-Item -ItemType Directory -Force $cdir | Out-Null
        $env:II_CONFIG_DIR = $cdir
        try {
            $where = & $shim config where | Out-String
            Assert-True ($where -match [regex]::Escape($cdir)) 'ii-shim config where honours II_CONFIG_DIR (so a test can never hit the real folder)'

            # The real file as an oracle for the schema: a COPY is validated, the original is only read.
            $live = Join-Path $env:LOCALAPPDATA 'quickshell\illogical-impulse\config.json'
            if (Test-Path $live) {
                $copy = Join-Path $base 'live-copy.json'
                Copy-Item $live $copy
                $out = & $shim config check --file $copy | Out-String
                Assert-True ($LASTEXITCODE -eq 0) "the schema accepts a real, long-used config.json without errors ($((($out -split "`r?`n") | Where-Object { $_ -match '^(warning|error)' }).Count) notes)"
                Assert-True ($out -notmatch '(?m)^error ') 'and reports no error for it'
            }

            # guard on a truncated file with a last good one
            $good = '{"configVersion": 1, "bar": {"workspaces": {"shown": 12}}}'
            Set-Content (Join-Path $cdir 'config.last-good.json') $good -NoNewline
            Set-Content (Join-Path $cdir 'config.json') '{"configVersion": 1, "bar": {"works' -NoNewline
            $out = & $shim config guard | Out-String
            Assert-Equal $LASTEXITCODE 0 'guard succeeds'
            Assert-True ($out -match 'last good one was put back') "guard says what it did: $($out.Trim().Split("`n")[0])"
            Assert-Equal (Get-Content (Join-Path $cdir 'config.json') -Raw) $good 'config.json is the last good copy again'
            Assert-Equal @(Get-ChildItem $cdir -Filter 'config.json.invalid-*').Count 1 'the damaged file was kept'

            # export / import through the CLI: the sentinel never reaches the pack
            Set-Content (Join-Path $cdir 'config.json') '{"configVersion": 1, "bar": {"workspaces": {"shown": 7}}, "sidebar": {"booru": {"gelbooru": {"apiKey": "SENTINEL-KEY-123"}}}}' -NoNewline
            $pack = Join-Path $base 'pack.json'
            $null = & $shim config export $pack
            Assert-Equal $LASTEXITCODE 0 'export succeeds'
            Assert-True ((Get-Content $pack -Raw) -notmatch 'SENTINEL') 'the exported pack has no credential'
            $before = (Get-Content (Join-Path $cdir 'config.json') -Raw)
            $out = & $shim config import $pack | Out-String
            Assert-True ($out -match 'preview only') 'import previews by default'
            Assert-Equal (Get-Content (Join-Path $cdir 'config.json') -Raw) $before 'and the preview changed nothing'
        }
        finally { Remove-Item Env:\II_CONFIG_DIR -ErrorAction SilentlyContinue }
    } else { Write-Output 'ii-shim.exe not built: the CLI checks were not run' }

    # ---- D: the host runs the guard before the shell and remembers the last good one after it is up ------
    Require-IiHostBuild
    $cleanup = @()
    $goodText = '{"configVersion": 1, "bar": {"workspaces": {"shown": 11}}}'

    # D1: damaged config + last good -> restored before the shell starts; the host logs it; the
    #     last good copy is left as it was (the restored file is the same bytes)
    $data = Join-Path $base 'd1-data'; $cfgDir = Join-Path $base 'd1-config'
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    Set-Content (Join-Path $cfgDir 'config.last-good.json') $goodText -NoNewline
    Set-Content (Join-Path $cfgDir 'config.json') '{"configVersion": 1, "bar": {' -NoNewline
    $shell = New-IiFakeShell (Join-Path $base 'd1-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'window' $data @{ II_CONFIG_DIR = $cfgDir; II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'D1: the host reaches active'
    $log = Get-IiHostLog $data
    Assert-True ($log -match 'config: config\.json was damaged .* last good one was put back') 'D1: the host logged that it restored the last good config'
    Assert-True ($log.IndexOf('config: config.json was damaged') -lt $log.IndexOf('phase: launching -> awaiting-ready')) 'D1: and did it before the shell was started'
    Assert-Equal (Get-Content (Join-Path $cfgDir 'config.json') -Raw) $goodText 'D1: config.json is the last good one'
    Assert-True ((Get-IiHostLog $data) -match 'config: \(no UI\) ii: your settings file was checked') 'D1: the user would be told (suppressed here because tests run without UI)'
    Assert-True ((Send-IiWmClose $p.Id) -ge 1) 'D1: host window found'
    Assert-Equal (Wait-IiExit $p 20) 0 'D1: clean stop'

    # D2: a valid config -> after the shell is up it becomes the last good copy, once
    $data = Join-Path $base 'd2-data'; $cfgDir = Join-Path $base 'd2-config'
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    Set-Content (Join-Path $cfgDir 'config.json') $goodText -NoNewline
    $shell = New-IiFakeShell (Join-Path $base 'd2-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'window' $data @{ II_CONFIG_DIR = $cfgDir; II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'D2: the host reaches active'
    Assert-True (Wait-IiLog $data 'config: config\.json remembered as the last good copy' 10) 'D2: the working config was remembered'
    Assert-Equal (Get-Content (Join-Path $cfgDir 'config.last-good.json') -Raw) $goodText 'D2: config.last-good.json holds it'
    # while it runs, a bad edit does not replace the last good copy (and nothing is saved per change)
    Set-Content (Join-Path $cfgDir 'config.json') '{"configVersion": 1, "bar": {"workspaces": {"shown": "x"}}}' -NoNewline
    Start-Sleep -Seconds 2
    Assert-Equal (Get-Content (Join-Path $cfgDir 'config.last-good.json') -Raw) $goodText 'D2: a later bad edit does not touch the last good copy'
    $null = Send-IiWmClose $p.Id
    Assert-Equal (Wait-IiExit $p 20) 0 'D2: clean stop'
    Assert-Equal (Get-Content (Join-Path $cfgDir 'config.last-good.json') -Raw) $goodText 'D2: nor does stopping with a wrong-typed config'

    # D3: an isolated test host (II_DATA_DIR only) never looks at the real user's config
    $data = Join-Path $base 'd3-data'
    $shell = New-IiFakeShell (Join-Path $base 'd3-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'window' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'D3: the host reaches active'
    Assert-True ((Get-IiHostLog $data) -notmatch 'config:') 'D3: without II_CONFIG_DIR an isolated host does not touch any config'
    $null = Send-IiWmClose $p.Id
    Assert-Equal (Wait-IiExit $p 20) 0 'D3: clean stop'
}
finally {
    Stop-IiStragglers $cleanup
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
