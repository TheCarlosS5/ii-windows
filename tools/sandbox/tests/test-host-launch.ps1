# R02 + R05: launching the shell is a recoverable operation, and rescue/guard stop only the
# shell they supervise. Runs real ii-host.exe instances in isolation (see lib\ii-host.ps1): own data
# folder, no message boxes, nothing hidden, Explorer untouched. Needs: cmake --build host\build
# --target ii-host ii-fake-shell.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

$base = New-IiTestDir 'ii-launch'
$cleanup = @()
try {
    # ---- R02-a: the shell executable does not exist: nothing is started, nothing is touched ----
    $data = Join-Path $base 'a-data'
    $p = Start-IiHost (Join-Path $base 'nope\quickshell.exe') 'window' $data
    $code = Wait-IiExit $p 20
    Assert-Equal $code 1 'a missing shell executable makes the host exit with 1'
    $log = Get-IiHostLog $data
    Assert-True ($log -match 'shell executable not found') 'the refusal is logged with the reason'
    Assert-True ($log -notmatch 'phase: \w+(-\w+)* -> launching') 'it never got as far as launching'

    # ---- R02-b: the file exists but cannot be started: bounded retries, then rollback ----------
    $data = Join-Path $base 'b-data'
    # A folder named quickshell.exe: it exists (so the pre-check passes) but CreateProcess fails
    # at once. (A file that is not a PE image fails too, but Defender can take tens of seconds
    # to scan it first, which would make the timing meaningless.)
    $bad = Join-Path $base 'b-shell\quickshell.exe'
    New-Item -ItemType Directory -Force $bad | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-IiHost $bad 'window' $data
    $code = Wait-IiExit $p 60
    $elapsed = $sw.Elapsed.TotalSeconds
    Assert-Equal $code 2 'a shell that cannot be created ends the host with 2, not a host that keeps running'
    $log = Get-IiHostLog $data
    Assert-True (([regex]::Matches($log, 'shell: CreateProcess failed')).Count -ge 3) 'CreateProcess was attempted 3 times'
    Assert-True ($log -match 'launch failed.*attempt 1 of 3') 'the first failure is retried with a delay'
    Assert-True ($log -match 'giving up') 'then it gives up'
    Assert-True ($log -match 'restoreAll') 'and restores through the common path'
    Assert-Equal (Get-IiState $data 'hostClean') '1' 'state.ini says the host ended clean'
    Assert-True ($elapsed -gt 2.5 -and $elapsed -lt 30) "retries are spaced by backoff, not a tight loop ($([int]$elapsed) s)"

    # ---- R02-c: the shell dies at once, every time -------------------------------------------
    $data = Join-Path $base 'c-data'
    $shell = New-IiFakeShell (Join-Path $base 'c-shell')
    $p = Start-IiHost $shell 'exit:5' $data
    $code = Wait-IiExit $p 90
    Assert-Equal $code 2 'a shell that keeps exiting with 5 ends the host with 2'
    $log = Get-IiHostLog $data
    Assert-True (([regex]::Matches($log, 'shell: exited with code 5')).Count -ge 3) 'three early exits were seen'
    Assert-True ($log -match 'giving up: .*varias veces') 'and the host stops trying'
    Assert-True ($log -match 'restoreAll') 'rollback ran'

    # ---- R02-d: the shell starts but never shows anything ------------------------------------
    $data = Join-Path $base 'd-data'
    $shell = New-IiFakeShell (Join-Path $base 'd-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'hang' $data @{ II_TEST_READY_TIMEOUT_MS = 1500; II_TEST_WATCHDOG_MS = 400 }
    $code = Wait-IiExit $p 120
    Assert-Equal $code 2 'a shell that never becomes ready is restarted a few times and then abandoned'
    $log = Get-IiHostLog $data
    Assert-True ($log -match 'giving Explorer back') 'the first failed start gives Explorer back while it retries'
    Assert-True ($log -match 'giving up: .*colgada') 'after the retries the host gives up (as stuck, not as crashed)'
    Start-Sleep -Milliseconds 500
    Assert-Equal (Get-IiProcessesAt $shell).Count 0 'no hung shell is left behind'

    # ---- R02-e: a healthy shell: ready on every monitor, then a clean stop --------------------
    $data = Join-Path $base 'e-data'
    $shell = New-IiFakeShell (Join-Path $base 'e-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'window' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the host reaches active once the shell covers the monitors'
    Assert-True ((Get-IiHostLog $data) -match 'shell: ready after \d+ ms on \d+ monitor') 'readiness was judged per monitor'
    Assert-Equal (Get-IiState $data 'shellPid') (@(Get-IiProcessesAt $shell)[0].Id.ToString()) 'the supervised shell is recorded by pid'
    Assert-True ((Send-IiWmClose $p.Id) -ge 1) 'the host window was found'
    $code = Wait-IiExit $p 20
    Assert-Equal $code 0 'WM_CLOSE ends the host normally'
    Start-Sleep -Milliseconds 500
    Assert-Equal (Get-IiProcessesAt $shell).Count 0 'the shell went with it'
    Assert-True ((Get-IiHostLog $data) -match 'phase: restoring -> recovered|phase: \w+ -> recovered') 'the log shows restoring -> recovered'
    Assert-Equal (Get-IiState $data 'shellPid') $null 'the shell record is cleared'

    # ---- R05-a: rescue stops the recorded shell and host, never a look-alike -----------------
    $data = Join-Path $base 'f-data'
    $shell = New-IiFakeShell (Join-Path $base 'f-shell')
    $decoy = New-IiFakeShell (Join-Path $base 'f-decoy')   # another quickshell.exe, not ours
    $cleanup += $shell; $cleanup += $decoy
    $decoyProc = Start-IiProcess $decoy @('-p', 'hang') (Join-Path $base 'f-decoy-data')
    $p = Start-IiHost $shell 'window' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'host up for the rescue test'
    $rescue = Start-IiProcess $script:IiHostExe @('--rescue') $data
    Assert-Equal (Wait-IiExit $rescue 30) 0 'the rescue finishes'
    [void](Wait-IiExit $p 10)
    Start-Sleep -Milliseconds 500
    Assert-Equal (Get-IiProcessesAt $shell).Count 0 'the supervised shell is stopped'
    Assert-True $p.HasExited 'the supervised host is stopped'
    Assert-True (-not $decoyProc.HasExited) 'an unrelated quickshell.exe from another folder is untouched'

    # ---- R05-b: a stale record (PID reused) authorises nothing -------------------------------
    $data = Join-Path $base 'g-data'
    New-Item -ItemType Directory -Force $data | Out-Null
    $ini = "[instance]`r`nshellPid=$($decoyProc.Id)`r`nshellCreated=123456789`r`nshellPath=$decoy`r`n"
    [IO.File]::WriteAllText((Join-Path $data 'state.ini'), $ini, [Text.Encoding]::Unicode)
    $rescue = Start-IiProcess $script:IiHostExe @('--rescue') $data
    Assert-Equal (Wait-IiExit $rescue 30) 0 'rescue with a stale record finishes'
    Assert-True (-not $decoyProc.HasExited) 'a process that merely has the recorded PID is left alone'
    Assert-True ((Get-IiHostLog $data) -match 'not running any more \(or the PID was reused\)') 'the log explains why it was not touched'

    # ---- R05-c: no record at all: only the exact executable of this installation -------------
    $data = Join-Path $base 'h-data'
    $inst = Join-Path $base 'h-install'
    New-Item -ItemType Directory -Force $inst | Out-Null
    Copy-Item $script:IiHostExe (Join-Path $inst 'ii-host.exe')
    $ours = New-IiFakeShell (Join-Path $inst 'quickshell')     # <install>\quickshell\quickshell.exe
    $cleanup += $ours
    $oursProc = Start-IiProcess $ours @('-p', 'hang') $data
    Start-Sleep -Milliseconds 700
    $rescue = Start-IiProcess (Join-Path $inst 'ii-host.exe') @('--rescue') $data
    Assert-Equal (Wait-IiExit $rescue 30) 0 'rescue without a record finishes'
    Start-Sleep -Milliseconds 500
    Assert-True $oursProc.HasExited 'the shell that is exactly <install>\quickshell\quickshell.exe is stopped'
    Assert-True (-not $decoyProc.HasExited) 'the look-alike elsewhere is still untouched'
}
finally {
    Stop-IiStragglers $cleanup
    Get-Process ii-host -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -like "$base*" -or $_.Path -ieq $script:IiHostExe } catch { $false } } | ForEach-Object { try { $_.Kill() } catch {} }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
