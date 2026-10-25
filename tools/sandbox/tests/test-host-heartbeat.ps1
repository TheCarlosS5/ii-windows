# Plan 2026-10-24, 0.1: a shell that is alive but frozen (its GUI thread stands still) or that lost its windows is
# noticed by its missing heartbeat: Windows' UI comes back first, then exactly that shell is ended and a new one
# starts. Runs real ii-host.exe instances in isolation (see lib\ii-host.ps1). Needs: cmake --build host\build-clang
# --target ii-host ii-fake-shell.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

# Time of the first log line matching $Pattern (host.log lines start with "yyyy-MM-dd HH:mm:ss.fff").
function Get-IiLogTime([string]$DataDir, [string]$Pattern) {
    foreach ($line in (Get-IiHostLog $DataDir) -split "`r?`n") {
        if ($line -match $Pattern -and $line -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})') {
            return [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
        }
    }
    $null
}

$base = New-IiTestDir 'ii-heartbeat'
$cleanup = @()
try {
    # ---- a: the GUI thread freezes after 3 beats: detected in under 6 s, Explorer first, then a new shell --------------
    $data = Join-Path $base 'a-data'
    $shell = New-IiFakeShell (Join-Path $base 'a-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'freeze:3' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the frozen-to-be shell first comes up'
    Assert-True (Wait-IiLog $data 'hang: the shell.s GUI thread has been silent' 30) 'its silence is noticed'
    $active = Get-IiLogTime $data 'phase: awaiting-ready -> active'
    $hang = Get-IiLogTime $data 'hang: the shell.s GUI thread'
    # Frozen at the 3rd beat (about 3 s after start, which is also about when it became active).
    $after = ($hang - $active).TotalSeconds
    Assert-True ($after -lt 3 + 6) "the freeze is acted on within 6 s of the last beat ($([math]::Round($after, 1)) s after it came up)"
    $log = Get-IiHostLog $data
    Assert-True ($log -match 'hang: .*in front: ') 'the log records what was in front'
    $exposed = Get-IiLogTime $data 'giving Explorer back'
    Assert-True ($null -ne $exposed -and $exposed -ge $hang) 'Windows UI is given back as part of handling the freeze'
    Assert-True (Wait-IiLog $data '(?s)hang: .*shell: started pid' 20) 'a new shell is started after the frozen one'
    Assert-True ((([regex]::Matches((Get-IiHostLog $data), 'shell: started pid')).Count) -ge 2) 'two shells were started in total'
    Assert-True ((Send-IiWmClose $p.Id) -ge 1) 'the host window was found'
    Assert-Equal (Wait-IiExit $p 20) 0 'the host still ends normally'
    Start-Sleep -Milliseconds 500
    Assert-Equal (Get-IiProcessesAt $shell).Count 0 'no frozen shell is left behind'

    # ---- b: it keeps freezing with no game in front: after 3 freezes the host gives up and restores ----------------
    $data = Join-Path $base 'b-data'
    $shell = New-IiFakeShell (Join-Path $base 'b-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'freeze:2' $data @{ II_TEST_WATCHDOG_MS = 400; II_TEST_HEARTBEAT_MS = 1500 }
    $code = Wait-IiExit $p 90
    Assert-Equal $code 2 'a shell that freezes again and again ends the host with 2'
    $log = Get-IiHostLog $data
    Assert-True (([regex]::Matches($log, 'hang: the shell')).Count -ge 3) 'three freezes were seen'
    Assert-True ($log -match 'giving up: .*congel') 'then the host stops trying'
    Assert-True ($log -match 'restoreAll') 'and rolls everything back'
    Start-Sleep -Milliseconds 500
    Assert-Equal (Get-IiProcessesAt $shell).Count 0 'no frozen shell is left behind'

    # ---- c: a healthy beating shell is left alone ---------------------------------------------------------------------
    $data = Join-Path $base 'c-data'
    $shell = New-IiFakeShell (Join-Path $base 'c-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'beat' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the shell comes up'
    Start-Sleep -Seconds 9
    Assert-True ((Get-IiHostLog $data) -notmatch 'hang:') 'no freeze is reported while it beats'
    Assert-Equal (([regex]::Matches((Get-IiHostLog $data), 'shell: started pid')).Count) 1 'it is never restarted'
    Send-IiWmClose $p.Id | Out-Null
    Assert-Equal (Wait-IiExit $p 20) 0 'clean stop'

    # ---- d: an older shell that never beats is not taken for a frozen one --------------------------------------------
    $data = Join-Path $base 'd-data'
    $shell = New-IiFakeShell (Join-Path $base 'd-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'window' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the shell comes up'
    Start-Sleep -Seconds 8
    Assert-True ((Get-IiHostLog $data) -notmatch 'hang:') 'no heartbeat at all is not a freeze'
    Send-IiWmClose $p.Id | Out-Null
    Assert-Equal (Wait-IiExit $p 20) 0 'clean stop'

    # ---- d2: a GUI thread that is silent because it is working (processor time rising) is waited for -------------
    $data = Join-Path $base 'd2-data'
    $shell = New-IiFakeShell (Join-Path $base 'd2-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'busy:3' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the shell comes up'
    Assert-True (Wait-IiLog $data 'silent for \d+ ms but working' 30) 'the long silence is seen as work, not a freeze'
    Start-Sleep -Seconds 8
    Assert-True ((Get-IiHostLog $data) -notmatch 'hang:') 'a busy GUI thread is not restarted'
    Send-IiWmClose $p.Id | Out-Null
    Assert-Equal (Wait-IiExit $p 20) 0 'clean stop'

    # ---- e: the shell keeps beating but its windows are gone: restarted after 20 s -----------------------------------
    $data = Join-Path $base 'e-data'
    $shell = New-IiFakeShell (Join-Path $base 'e-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'nowin:3' $data @{ II_TEST_WATCHDOG_MS = 1000 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the shell comes up'
    Assert-True (Wait-IiLog $data 'hang: no window of the shell on any screen' 45) 'a shell with no window left is noticed'
    Assert-True (Wait-IiLog $data '(?s)hang: no window.*shell: started pid' 20) 'and replaced'
    Send-IiWmClose $p.Id | Out-Null
    Assert-Equal (Wait-IiExit $p 20) 0 'clean stop'
}
finally {
    Stop-IiStragglers $cleanup
    Get-Process ii-host -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -ieq $script:IiHostExe } catch { $false } } | ForEach-Object { try { $_.Kill() } catch {} }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
