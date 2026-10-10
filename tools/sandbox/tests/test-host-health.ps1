# R01 (host side): Windows' notification banners are switched off only while the shell's listener
# is confirmed, and come back when it is not. A fake shell reports the listener's health the way
# the real one does (protocol v1, host/src/health.cpp); the host runs as an isolated instance that
# never touches the real notification settings (II_NO_UI). Invariants:
#   - permission denied / revoked, a wrong instance id, an unknown protocol version, a message from
#     a process that is not the supervised shell, or a listener that stops reporting NEVER leave
#     banners off (a real channel for notifications is kept)
#   - only a fresh, granted, subscribed, available report from this shell switches them off
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

$base = New-IiTestDir 'ii-health'
$cleanup = @()

function Run-Variant([string]$Name, [string]$Variant, [scriptblock]$WaitFor, [int]$SecondsAfter = 4) {
    $data = Join-Path $base "$Name-data"
    $shell = New-IiFakeShell (Join-Path $base "$Name-shell")
    $script:cleanup += $shell
    # Banner handling stays on (no --keep-banners): that is what is under test.
    $args = @('--shell', $shell, '--config', "hb:$Variant", '--no-taskbar', '--no-icons', '--no-hook', '--no-theme', '--no-nightlight', '--no-splash')
    $p = Start-IiProcess $script:IiHostExe $args $data @{ II_TEST_READY_TIMEOUT_MS = 60000; II_TEST_WATCHDOG_MS = 500 }
    $ready = Wait-IiLog $data 'phase: awaiting-ready -> active' 60
    if ($WaitFor) { & $WaitFor $data }
    Start-Sleep -Seconds $SecondsAfter
    $log = Get-IiHostLog $data
    [void](Send-IiWmClose $p.Id)
    [void](Wait-IiExit $p 20)
    Stop-IiStragglers @($shell)
    [pscustomobject]@{ Ready = $ready; Log = $log }
}

try {
    # A healthy listener switches banners off, once, and says why.
    $r = Run-Variant 'ok' 'ok' { param($d) [void](Wait-IiLog $d "banners: Windows' own switched off" 15) }
    Assert-True $r.Ready 'the host reached active with the health-reporting shell'
    Assert-True ($r.Log -match 'health: notifications available, permission granted, subscribed 1') 'a fresh granted report is accepted'
    Assert-True ($r.Log -match "banners: Windows' own switched off \(listener available\)") 'banners go off only after that report'
    Assert-Equal ([regex]::Matches($r.Log, "switched off").Count) 1 'and the switch is made once, not on every heartbeat'

    # Permission denied: the system banners stay on.
    $r = Run-Variant 'denied' 'denied' { param($d) [void](Wait-IiLog $d 'health: notifications permission-required' 15) }
    Assert-True ($r.Log -match 'health: notifications permission-required, permission denied, subscribed 0') 'the denial is seen and logged'
    Assert-True ($r.Log -notmatch 'switched off') 'denied permission never switches banners off'

    # A report for another instance id (replay, or a different shell) is ignored.
    $r = Run-Variant 'badinstance' 'badinstance' { param($d) [void](Wait-IiLog $d 'wrong instance id' 15) }
    Assert-True ($r.Log -match 'wrong instance id or type ignored') 'a wrong instance id is rejected'
    Assert-True ($r.Log -notmatch 'switched off') 'and does not switch banners off'

    # A protocol version the host does not speak must not enable anything.
    $r = Run-Variant 'badversion' 'badversion' { param($d) [void](Wait-IiLog $d 'protocol version 99' 15) }
    Assert-True ($r.Log -match 'protocol version 99 is not understood') 'an unknown protocol version is reported'
    Assert-True ($r.Log -notmatch 'switched off') 'and enables nothing'

    # The listener hangs: heartbeats stop, banners come back on their own.
    $r = Run-Variant 'silent' 'silent2' { param($d) [void](Wait-IiLog $d "banners: Windows' own back on" 20) } 1
    Assert-True ($r.Log -match "switched off") 'banners were off while it reported'
    Assert-True ($r.Log -match "banners: Windows' own back on \(the shell stopped reporting\)") 'a silent shell hands banners back (expiry 3 s)'

    # Permission revoked during the session.
    $r = Run-Variant 'revoked' 'revoke2' { param($d) [void](Wait-IiLog $d "banners: Windows' own back on" 20) } 1
    Assert-True ($r.Log -match "switched off") 'banners were off while access was granted'
    Assert-True ($r.Log -match "back on \(Windows has not granted access to notifications\)") 'revocation hands banners back at once'

    # A process that is not the supervised shell reports "all good": ignored.
    $data = Join-Path $base 'foreign-data'
    $shell = New-IiFakeShell (Join-Path $base 'foreign-shell')
    $decoyExe = New-IiFakeShell (Join-Path $base 'foreign-decoy')
    $cleanup += $shell; $cleanup += $decoyExe
    $args = @('--shell', $shell, '--config', 'window', '--no-taskbar', '--no-icons', '--no-hook', '--no-theme', '--no-nightlight', '--no-splash')
    $p = Start-IiProcess $script:IiHostExe $args $data @{ II_TEST_READY_TIMEOUT_MS = 60000; II_TEST_WATCHDOG_MS = 500 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 60) 'host up for the foreign-sender test'
    # The decoy knows where the host window is, but is not the shell the host started.
    $hostHwnd = [string][int64](Get-Process -Id $p.Id).MainWindowHandle
    $found = New-Object System.Collections.Generic.List[IntPtr]
    $cb = [IiTest.Win+EnumProc]{ param($h, $l) $x = [uint32]0; [void][IiTest.Win]::GetWindowThreadProcessId($h, [ref]$x); if ($x -eq $p.Id) { $sb = New-Object Text.StringBuilder 64; [void][IiTest.Win]::GetClassName($h, $sb, 64); if ($sb.ToString().StartsWith('IiHostWindow')) { $found.Add($h) } }; $true }
    [void][IiTest.Win]::EnumWindows($cb, [IntPtr]::Zero)
    Assert-True ($found.Count -ge 1) 'found the host window for the decoy'
    $decoy = Start-IiProcess $decoyExe @('-p', 'hb:foreign') (Join-Path $base 'foreign-decoy-data') @{ II_HOST_HWND = [string][int64]$found[0]; II_INSTANCE_ID = '{11111111-1111-1111-1111-111111111111}' }
    Start-Sleep -Seconds 4
    $log = Get-IiHostLog $data
    [void](Send-IiWmClose $p.Id)
    [void](Wait-IiExit $p 20)
    try { $decoy.Kill() } catch {}
    Assert-True ($log -match 'health: message from process \d+ ignored') 'a report from a process that is not the shell is ignored'
    Assert-True ($log -notmatch 'switched off') 'and cannot switch banners off'
}
finally {
    Stop-IiStragglers $cleanup
    Get-Process ii-host -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -ieq $script:IiHostExe } catch { $false } } | ForEach-Object { try { $_.Kill() } catch {} }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
