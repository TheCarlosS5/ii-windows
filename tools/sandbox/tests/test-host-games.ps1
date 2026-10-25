# Plan 2026-10-24, review: ii-host with a game in front. Runs real ii-host.exe instances in isolation (lib\ii-host.ps1).
# No game is put on the tester's screen: II_TEST_FULLSCREEN makes the host act as if one filled it, II_TEST_GAME_PID
# names the process standing for it, and a test host never injects keys (II_NO_UI). Needs: cmake --build
# host\build-clang --target ii-host ii-fake-shell.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

$WM_II_LONE_WIN = 0x8004       # WM_APP + 4: the hook saw a lone Win press go to ii's search
$WM_FAKE_LAUNCHER = 0x801E     # WM_APP + 30: the fake shell shows its "search" on top, without the foreground
$WM_FAKE_LAYER = 0x801F        # WM_APP + 31: a full-screen layer of the shell on top that is not the search
$startLine = "ii did not show for the Win key"
$shownLine = "ii's search shows over the window in front"

$base = New-IiTestDir 'ii-games'
$cleanup = @()
try {
    # ---- a: lone Win over a game, ii shows nothing: Windows' Start instead ------------------------------------------
    $data = Join-Path $base 'a-data'
    $shell = New-IiFakeShell (Join-Path $base 'a-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'window' $data @{ II_TEST_WATCHDOG_MS = 400; II_TEST_FULLSCREEN = 1 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'the shell comes up'
    Assert-Equal (Send-IiMessage $p.Id 'IiHostWindow' $WM_II_LONE_WIN) 1 'the lone Win press reaches the host'
    Assert-True (Wait-IiLog $data $startLine 10) 'with nothing of ii on screen, Windows Start opens instead'

    # ---- a2: another full-screen layer of ii's on top (the minimize animation) is not the search: Start still opens -
    Start-Sleep -Seconds 1
    $shellProc = @(Get-IiProcessesAt $shell)[0]
    Assert-True ((Send-IiMessage $shellProc.Id 'IiFakeShell' $WM_FAKE_LAYER) -ge 1) 'an unmarked layer of the shell is on top'
    $before = ([regex]::Matches((Get-IiHostLog $data), [regex]::Escape($startLine))).Count
    Send-IiMessage $p.Id 'IiHostWindow' $WM_II_LONE_WIN | Out-Null
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and ([regex]::Matches((Get-IiHostLog $data), [regex]::Escape($startLine))).Count -le $before) { Start-Sleep -Milliseconds 200 }
    Assert-True (([regex]::Matches((Get-IiHostLog $data), [regex]::Escape($startLine))).Count -gt $before) 'it does not count as an answer: Start opens'

    # ---- b: ii's search shows (on top) but Windows keeps the game in front: no Start on top of it -------------------
    Start-Sleep -Seconds 1
    $before = ([regex]::Matches((Get-IiHostLog $data), [regex]::Escape($startLine))).Count
    Send-IiMessage $p.Id 'IiHostWindow' $WM_II_LONE_WIN | Out-Null
    Start-Sleep -Milliseconds 150
    $shellProc = @(Get-IiProcessesAt $shell)[0]
    Assert-True ((Send-IiMessage $shellProc.Id 'IiFakeShell' $WM_FAKE_LAUNCHER) -ge 1) 'the fake search is shown'
    Assert-True (Wait-IiLog $data ([regex]::Escape($shownLine)) 10) 'the search on screen counts as an answer'
    Assert-Equal ([regex]::Matches((Get-IiHostLog $data), [regex]::Escape($startLine))).Count $before 'and Start is not opened over it'

    # ---- c: the search is already showing: this press closes it, and Start does not open ---------------------------
    $logBefore = (Get-IiHostLog $data).Length
    Send-IiMessage $p.Id 'IiHostWindow' $WM_II_LONE_WIN | Out-Null
    Start-Sleep -Seconds 2
    $tail = (Get-IiHostLog $data).Substring($logBefore)
    Assert-True ($tail -notmatch [regex]::Escape($startLine) -and $tail -notmatch [regex]::Escape($shownLine)) 'a press that closes the search is left alone'
    Send-IiWmClose $p.Id | Out-Null
    Assert-Equal (Wait-IiExit $p 20) 0 'clean stop'

    # ---- d: freezes with a game whose handle is denied: ii follows it by pid and waits for it to end ----------------
    $game = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -WindowStyle Hidden -PassThru
    $data = Join-Path $base 'd-data'
    $shell = New-IiFakeShell (Join-Path $base 'd-shell')
    $cleanup += $shell
    $p = Start-IiHost $shell 'freeze:2' $data @{ II_TEST_WATCHDOG_MS = 400; II_TEST_HEARTBEAT_MS = 1500; II_TEST_FULLSCREEN = 1
                                                II_TEST_GAME_PID = $game.Id; II_TEST_GAME_NO_HANDLE = 1 }
    Assert-True (Wait-IiLog $data 'following it by its pid' 90) 'without a handle on the game it is followed by its pid'
    Assert-True (Wait-IiLog $data 'ii waits until it ends' 10) 'and ii waits for the game'
    $started = ([regex]::Matches((Get-IiHostLog $data), 'shell: started pid')).Count
    Start-Sleep -Seconds 6
    Assert-Equal ([regex]::Matches((Get-IiHostLog $data), 'shell: started pid')).Count $started 'no new shell while the game runs'
    Assert-True (-not $p.HasExited) 'the host keeps running (Windows UI given back), it does not give up'
    Stop-Process -Id $game.Id -Force
    Assert-True (Wait-IiLog $data 'hang: the game ended, starting ii again' 15) 'once the game ends ii comes back'
    Assert-True (Wait-IiLog $data "(?s)the game ended.*shell: started pid" 15) 'with a new shell'
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
finally {
    if ($game -and -not $game.HasExited) { Stop-Process -Id $game.Id -Force -ErrorAction SilentlyContinue }
    Stop-IiStragglers $cleanup
    Get-Process ii-host -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -ieq $script:IiHostExe } catch { $false } } | ForEach-Object { try { $_.Kill() } catch {} }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
