# R07: installing and updating the runtime never leaves a half-replaced installation, and a new
# version that fails to start is rolled back by the launcher. Builds small "installations" in a temp
# folder out of the fake host/shell binaries; the real install folder is never touched.
#   - clean install, update, hash-mismatching and incomplete payloads
#   - faults: interrupted copy, full disk, locked file, failure after staging / after the rename /
#     before the pointer, and a killed installer (journal recovery)
#   - the launcher: verified version starts and exits; pending version that crashes / never verifies
#     / is already running; falling back keeps a diagnosis and the failed version on disk
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
. "$PSScriptRoot\..\..\package\ii-runtime.ps1"
Require-IiHostBuild
$launcherExe = Join-Path $script:IiRepo 'host\build\ii-launcher.exe'
if (-not (Test-Path $launcherExe)) { Skip-Test 'ii-launcher.exe not built: cmake --build host\build --target ii-launcher' }

$base = New-IiTestDir 'ii-runtime'

function New-FakePayload([string]$Name, [string]$Version) {
    $d = Join-Path $base "payload-$Name"
    New-Item -ItemType Directory -Force "$d\quickshell", "$d\ii", "$d\rescue" | Out-Null
    Copy-Item $script:IiFakeShell "$d\ii-host.exe"            # the fake host (it is named ii-host.exe)
    Copy-Item $script:IiFakeShell "$d\quickshell\quickshell.exe"
    Set-Content "$d\ii\shell.qml" "// $Name"
    Set-Content "$d\VERSION" $Version
    Set-Content "$d\rescue\note.txt" $Name
    [void](New-IiPayloadManifest $d)
    $d
}
function New-Root([string]$Name) {
    $r = Join-Path $base $Name
    New-Item -ItemType Directory -Force $r | Out-Null
    Copy-Item $launcherExe (Join-Path $r 'ii-launcher.exe')
    $r
}
function Get-VersionDirs([string]$Root) { @(Get-ChildItem (Join-Path $Root 'versions') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object) }
function Get-TreeHash([string]$Dir) {
    $lines = Get-ChildItem -LiteralPath $Dir -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName).Hash + (Get-IiRelativePath $Dir $_.FullName) }
    $sha = [Security.Cryptography.SHA256]::Create(); [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join '|'))))
}
function Run-Launcher([string]$Root, [hashtable]$Env, [int]$TimeoutSec = 60) {
    $p = Start-IiProcess (Join-Path $Root 'ii-launcher.exe') @() (Join-Path $Root 'data') $Env
    $code = Wait-IiExit $p $TimeoutSec
    Start-Sleep -Milliseconds 700   # let a detached host finish what it does
    $code
}

try {
    $p1 = New-FakePayload 'v1' '1.0.0'
    $p2 = New-FakePayload 'v2' '2.0.0'
    $p3 = New-FakePayload 'v3' '3.0.0'
    $p4 = New-FakePayload 'v4' '4.0.0'

    # ---- clean install ----------------------------------------------------------------------------
    $root = New-Root 'main'
    $r = Install-IiRuntime -Payload $p1 -Root $root -VersionId 'v1'
    $cur = Read-IiCurrent $root
    Assert-True ($cur.active -eq 'v1' -and $cur.previous -eq 'none' -and $cur.state -eq 'pending') 'a clean install activates v1 as pending, with no previous'
    Assert-True ((Get-VersionDirs $root) -join ',' -eq 'v1') 'only the finished version folder exists (no staging left)'
    Assert-PathMissing (Join-Path $root 'journal.txt') 'and the journal is closed'
    Assert-True (Test-IiPayload (Join-Path $root 'versions\v1')).Ok 'the installed copy matches its manifest'

    # the launcher starts it and waits; the host verifies; the launcher leaves
    $code = Run-Launcher $root @{ II_FAKE_HOST = 'ok'; II_FAKE_HOST_LIFETIME_MS = 800 }
    Assert-Equal $code 0 'the launcher exits 0 once the pending version verified'
    Assert-Equal (Read-IiCurrent $root).state 'verified' 'v1 is verified (written by the host, atomically)'
    Assert-Equal (Read-IiCurrent $root).attempts '0' 'attempts reset'

    # ---- update to v2: v1 is never written to ------------------------------------------------------
    $v1Before = Get-TreeHash (Join-Path $root 'versions\v1')
    [void](Install-IiRuntime -Payload $p2 -Root $root -VersionId 'v2')
    $cur = Read-IiCurrent $root
    Assert-True ($cur.active -eq 'v2' -and $cur.previous -eq 'v1' -and $cur.state -eq 'pending') 'update: v2 pending, v1 kept as the way back'
    Assert-Equal (Get-TreeHash (Join-Path $root 'versions\v1')) $v1Before 'the active version was not touched while v2 was prepared'

    # ---- v2 crashes on its first start: the launcher goes back to v1 and says why ----------------------------
    $code = Run-Launcher $root @{ II_FAKE_HOST = 'crash' }
    Assert-Equal $code 0 'the launcher still ends well: it started the previous version'
    $cur = Read-IiCurrent $root
    Assert-True ($cur.active -eq 'v1' -and $cur.previous -eq 'v2' -and $cur.state -eq 'rolled-back') 'rolled back to v1; the failed v2 stays on disk'
    Assert-PathExists (Join-Path $root 'versions\v2\ii-host.exe') 'v2 is still there for diagnosis'
    $failure = Get-Content (Join-Path $root 'last-failure.txt') -Raw
    Assert-True ($failure -match 'version=v2' -and $failure -match 'exitCode=3') 'last-failure.txt names the version and the exit code'
    Assert-True ((Get-Content (Join-Path $root 'launcher.log') -Raw) -match 'fell back to v1') 'launcher.log records the fall back'

    # ---- v3 never verifies (hangs): timeout, rescue, fall back ----------------------------------------------
    [void](Install-IiRuntime -Payload $p3 -Root $root -VersionId 'v3')
    $code = Run-Launcher $root @{ II_FAKE_HOST = 'hang'; II_LAUNCHER_VERIFY_TIMEOUT_MS = 2000 }
    Assert-Equal $code 0 'a version that never verifies is abandoned'
    $cur = Read-IiCurrent $root
    Assert-True ($cur.active -eq 'v1' -and $cur.state -eq 'rolled-back') 'back on v1'
    Assert-PathExists (Join-Path $root 'versions\v3\rescue-ran.txt') 'and the hung version got a --rescue to put Windows back'
    Assert-True ((Get-Content (Join-Path $root 'last-failure.txt') -Raw) -match 'did not verify') 'the diagnosis says it did not verify in time'

    # ---- another host already running is not a failure ----------------------------------------------------------
    [void](Install-IiRuntime -Payload $p4 -Root $root -VersionId 'v4')
    $code = Run-Launcher $root @{ II_FAKE_HOST = 'already' }
    $cur = Read-IiCurrent $root
    Assert-True ($cur.active -eq 'v4' -and $cur.state -eq 'pending') 'exit 17 (a host is already running) does not roll the new version back'
    Assert-Equal (Invoke-IiRollback $root) 'v1' 'a manual rollback goes to the previous version'
    Assert-Equal (Read-IiCurrent $root).state 'rolled-back' 'and says so'

    # ---- too many launches of a pending version ---------------------------------------------------------------------
    Write-IiCurrent $root 'v4' 'v1' 'pending' 3
    [void](Run-Launcher $root @{ II_FAKE_HOST = 'ok' })
    Assert-Equal (Read-IiCurrent $root).active 'v1' 'a pending version launched too many times without verifying is dropped'

    # ---- old versions are cleaned only after verification, keeping active + previous ----------------------------------
    Write-IiCurrent $root 'v1' 'v4' 'verified' 0
    $removed = @(Remove-IiOldVersions $root)
    Assert-True ((Get-VersionDirs $root) -join ',' -eq 'v1,v4') 'only the active and the previous version remain'
    Write-IiCurrent $root 'v1' 'v4' 'pending' 0
    Assert-Equal @(Remove-IiOldVersions $root).Count 0 'while a version is still pending, nothing is deleted'

    # ---- legacy layout (no current.txt): a flat install is started as it is ---------------------------------------------
    $legacy = New-Root 'legacy'
    Copy-Item $script:IiFakeShell (Join-Path $legacy 'ii-host.exe')
    New-Item -ItemType Directory -Force (Join-Path $legacy 'quickshell') | Out-Null
    $code = Run-Launcher $legacy @{ II_FAKE_HOST = 'ok'; II_FAKE_HOST_LIFETIME_MS = 500 }
    Assert-Equal $code 0 'with no current.txt the launcher starts the flat install'
    Assert-True ((Get-Content (Join-Path $legacy 'launcher.log') -Raw) -match 'started .*legacy') 'from the install folder itself'
    $legacyUpdate = Install-IiRuntime -Payload $p1 -Root $legacy -VersionId 'v1'
    Assert-Equal $legacyUpdate.Previous 'legacy' 'the first versioned install keeps the flat one as its way back'

    # ---- payloads that are not what they claim --------------------------------------------------------------------------
    $rootBad = New-Root 'bad'
    $tampered = New-FakePayload 'tampered' '9'
    Add-Content (Join-Path $tampered 'ii\shell.qml') 'extra byte after the manifest'
    $threw = $false; try { Install-IiRuntime -Payload $tampered -Root $rootBad -VersionId 'bad1' } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True ($threw -and $msg -match 'hash differs') 'a payload whose file hash differs is refused'
    Assert-True (-not (Get-VersionDirs $rootBad).Count) 'and nothing was created'
    $incomplete = New-FakePayload 'incomplete' '9'
    Remove-Item (Join-Path $incomplete 'quickshell\quickshell.exe')
    $threw = $false; try { Install-IiRuntime -Payload $incomplete -Root $rootBad -VersionId 'bad2' } catch { $threw = $true }
    Assert-True $threw 'a payload with a missing required file is refused'
    $threw = $false; try { Install-IiRuntime -Payload $p1 -Root $rootBad -VersionId '..\evil' } catch { $threw = $true }
    Assert-True $threw 'a version id that tries to leave versions\ is refused'

    # ---- injected faults: the active version stays selectable, nothing half-made stays -----------------------------------
    foreach ($fault in 'copy-interrupted', 'disk-full', 'file-locked', 'after-staged', 'after-rename', 'before-pointer') {
        $rf = New-Root "fault-$fault"
        [void](Install-IiRuntime -Payload $p1 -Root $rf -VersionId 'v1')
        Write-IiCurrent $rf 'v1' 'none' 'verified' 0
        $before = Get-Content (Join-Path $rf 'current.txt') -Raw
        $env:II_TEST_FAULT = $fault
        $threw = $false; try { [void](Install-IiRuntime -Payload $p2 -Root $rf -VersionId 'v2') } catch { $threw = $true }
        Remove-Item Env:II_TEST_FAULT
        Assert-True $threw "fault '$fault': the install fails loudly"
        $cur = Read-IiCurrent $rf
        Assert-True ($cur.active -eq 'v1' -and $cur.state -eq 'verified') "fault '$fault': v1 is still the selected, verified version"
        Assert-True ((Get-Content (Join-Path $rf 'current.txt') -Raw) -eq $before) "fault '$fault': current.txt is byte-identical"
        Assert-True ((Test-IiPayload (Join-Path $rf 'versions\v1')).Ok) "fault '$fault': v1 is intact"
        Assert-True (@(Get-VersionDirs $rf | Where-Object { $_ -like '*staging*' }).Count -eq 0) "fault '$fault': no staging copy left"
        # and the next, healthy attempt works
        [void](Install-IiRuntime -Payload $p2 -Root $rf -VersionId 'v2')
        Assert-Equal (Read-IiCurrent $rf).active 'v2' "fault '$fault': a later install succeeds"
    }

    # ---- the installer itself is killed in the middle ---------------------------------------------------------------------
    $rk = New-Root 'killed'
    [void](Install-IiRuntime -Payload $p1 -Root $rk -VersionId 'v1')
    Write-IiCurrent $rk 'v1' 'none' 'verified' 0
    $script = Join-Path $base 'killed-install.ps1'
    Set-Content $script ". '$PSScriptRoot\..\..\package\ii-runtime.ps1'`n`$env:II_TEST_FAULT = 'hang-after-staged'`nInstall-IiRuntime -Payload '$p2' -Root '$rk' -VersionId 'v2'"
    # a hang fault: sleeps right after the staged journal entry
    $killedProc = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script -PassThru -WindowStyle Hidden
    $sw = [Diagnostics.Stopwatch]::StartNew(); $seen = $false
    while ($sw.Elapsed.TotalSeconds -lt 60) { $j = Read-IiJournal $rk; if ($j -and $j.step -eq 'staged') { $seen = $true; break }; Start-Sleep -Milliseconds 100 }
    try { $killedProc.Kill() } catch {}
    Assert-True $seen 'the installer reached the staged step'
    Assert-True (@(Get-VersionDirs $rk | Where-Object { $_ -like '*staging*' }).Count -ge 1) 'its staging copy is on disk after the kill'
    Assert-Equal (Read-IiCurrent $rk).active 'v1' 'but the active version is still v1'
    $notes = @(Resolve-IiRuntimeJournal $rk)
    Assert-True ($notes.Count -ge 2) 'the next run understands the interruption and cleans up'
    Assert-True (@(Get-VersionDirs $rk | Where-Object { $_ -like '*staging*' }).Count -eq 0) 'the staging copy is gone'
    Assert-PathMissing (Join-Path $rk 'journal.txt') 'the journal is cleared'
    Assert-Equal (Read-IiCurrent $rk).active 'v1' 'v1 still selected'
}
finally {
    Remove-Item Env:II_TEST_FAULT -ErrorAction SilentlyContinue
    Get-Process -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -like "$base*" } catch { $false } } | ForEach-Object { try { $_.Kill() } catch {} }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
