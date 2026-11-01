# Plan 2026-10-31, F2/F14: ii-host looks at Windows' state on its own thread (an update waiting for a restart, the
# system drive's free space), writes <data>\system-status.json for the shell and says something when it matters: a
# nearly full drive (II_TEST_SYSHEALTH_FREE_GB=1 plays one) gets one notice a day, not one per look. "system-check"
# looks again at once; "ms-settings" opens only the Windows Settings pages on its list.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

Add-Type -Namespace IiSysTest -Name Copy -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct COPYDATASTRUCT { public System.IntPtr dwData; public int cbData; public System.IntPtr lpData; }
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr SendMessageTimeout(System.IntPtr h, uint msg, System.IntPtr w, ref COPYDATASTRUCT d, uint flags, uint timeout, out System.IntPtr result);
'@
# A host command (ii-shim host <command>): WM_COPYDATA 0x49490040 to the host's own window (class IiHostWindow*).
function Send-HostCommand([int]$HostPid, [string]$Text) {
    $script:hostWindow = [IntPtr]::Zero
    $cb = [IiTest.Win+EnumProc] { param($h, $l)
        $owner = [uint32]0; [void][IiTest.Win]::GetWindowThreadProcessId($h, [ref]$owner)
        $sb = New-Object System.Text.StringBuilder 64; [void][IiTest.Win]::GetClassName($h, $sb, 64)
        if ($owner -eq $HostPid -and $sb.ToString().StartsWith('IiHostWindow')) { $script:hostWindow = $h }
        $true }
    [void][IiTest.Win]::EnumWindows($cb, [IntPtr]::Zero)
    if ($script:hostWindow -eq [IntPtr]::Zero) { return -1 }
    $buf = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Text)
    $cds = New-Object IiSysTest.Copy+COPYDATASTRUCT
    $cds.dwData = [IntPtr]0x49490040; $cds.cbData = ($Text.Length + 1) * 2; $cds.lpData = $buf
    $result = [IntPtr]::Zero
    [void][IiSysTest.Copy]::SendMessageTimeout($script:hostWindow, 0x4A, [IntPtr]::Zero, [ref]$cds, 2, 5000, [ref]$result)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
    [int64]$result
}

$base = New-IiTestDir 'ii-syshealth'
$shellExe = $null
try {
    $data = Join-Path $base 'data'
    $shellExe = New-IiFakeShell (Join-Path $base 'shell')
    $p = Start-IiHost $shellExe 'beat' $data @{ II_TEST_WATCHDOG_MS = 400; II_TEST_SYSHEALTH_FIRST_MS = 500; II_TEST_SYSHEALTH_FREE_GB = 1 }
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 30) 'the shell comes up'
    Assert-True (Wait-IiLog $data 'notices: C: has \d+ bytes free' 30) 'a nearly full drive is noticed'
    $statusFile = Join-Path $data 'system-status.json'
    Assert-PathExists $statusFile 'system-status.json is written for the shell'
    $status = Get-Content $statusFile -Raw | ConvertFrom-Json
    Assert-True ($status.lowDisk -eq $true) 'it says the disk is low'
    Assert-Equal $status.drive 'C:' 'for the system drive'
    Assert-True ($status.totalBytes -gt 0) 'with its size'
    Write-Output ("Windows Update answered: {0}, restart pending: {1}" -f $status.rebootKnown, $status.rebootRequired)
    Assert-True ($status.rebootKnown -eq $true) 'Windows Update answered whether it waits for a restart'
    $written = (Get-Item $statusFile).LastWriteTimeUtc

    Start-Sleep -Milliseconds 1200
    Assert-Equal (Send-HostCommand $p.Id 'system-check') 1 'the host takes "system-check"'
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Item $statusFile).LastWriteTimeUtc -eq $written -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    Assert-True ((Get-Item $statusFile).LastWriteTimeUtc -gt $written) 'it looks again at once'
    Start-Sleep -Milliseconds 500
    $count = ([regex]::Matches((Get-IiHostLog $data), 'notices: C: has')).Count
    Assert-Equal $count 1 'the low disk notice is given once a day, not on every look'

    # The command is posted (WM_COPYDATA answers 1 for any command): the refusal shows in the log.
    Assert-Equal (Send-HostCommand $p.Id ('ms-settings' + [char]0x1f + 'not-a-page')) 1 'the host takes "ms-settings"'
    Assert-True (Wait-IiLog $data 'ms-settings page not allowed: not-a-page' 10) 'an unknown Windows Settings page is refused'

    Assert-True ((Send-IiWmClose $p.Id) -ge 1) 'the host window closes'
    Assert-Equal (Wait-IiExit $p 20) 0 'the host ends normally'
} finally {
    # A failed assertion must not leave the host running (it would hold the console and the test would never end).
    if ($p -and -not $p.HasExited) { [void](Send-IiWmClose $p.Id); if (-not $p.WaitForExit(10000)) { $p.Kill() } }
    if ($shellExe) { Stop-IiStragglers @($shellExe) }
}
Complete-IiTest
