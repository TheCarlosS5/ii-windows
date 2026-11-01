# Plan 2026-10-31, A3/A4: what ii-host does when its shell keeps crashing. A fake shell (mode crash:<ms>:<subsystem>)
# comes up, leaves a crash report like quickshell-windows' handler does and exits with 0xC0000005, again and again.
# Expected: the report is read and logged; 1st and 2nd crash restart; the 3rd in the same subsystem restarts with it
# switched off (II_DISABLE); the 4th restarts in safe mode (II_SAFE_MODE=1, basic render loop); the 5th gives up and
# restores. The choice is kept for this version only (state.ini [safety]), and "safe-mode-off" clears it.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

function Get-FakeEnvs([string]$DataDir) {
    @(Get-ChildItem $DataDir -Filter 'fake-env-*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime |
        ForEach-Object { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::Unicode) })
}

$base = New-IiTestDir 'ii-crash-policy'
try {
    # ---- a: five crashes of mpris, 2.5 s apart ---------------------------------------------------------------------
    $data = Join-Path $base 'a-data'
    $shell = New-IiFakeShell (Join-Path $base 'a-shell')
    $p = Start-IiHost $shell 'crash:2500:mpris' $data @{ II_TEST_WATCHDOG_MS = 400 }
    $code = Wait-IiExit $p 120
    $log = Get-IiHostLog $data
    Assert-Equal $code 2 'after five crashes the host gives up (exit 2)'
    Assert-True ($log -match 'crash: quickshell\.exe\+0x19ed74 \(0xC0000005, exception\) in mpris') 'the crash report is read and logged'
    Assert-True ($log -match 'crash: 1 in 30 minutes, restarting') '1st crash: restart'
    Assert-True ($log -match 'crash: 2 in 30 minutes, restarting') '2nd crash: restart'
    Assert-True ($log -match 'crash: 3 in 30 minutes, 3 of them in mpris: it starts switched off') '3rd in mpris: mpris off'
    Assert-True ($log -match 'shell: starts with mpris off') 'the next shell is started without mpris'
    Assert-True ($log -match 'crash: 4 in 30 minutes: safe mode') '4th: safe mode'
    Assert-True ($log -match 'shell: starts with safe mode, mpris off') 'the next shell starts in safe mode'
    Assert-True ($log -match 'giving up: the shell crashed 5 times') '5th: give up'
    Assert-True ($log -match 'restoreAll') 'and everything is restored'
    $envs = Get-FakeEnvs $data
    Assert-Equal $envs.Count 5 'five shells were started'
    if ($envs.Count -eq 5) {
        Assert-True ($envs[0] -match 'disable=\r?\n' -and $envs[0] -match 'safe=\r?\n') 'the first shell starts with everything on'
        Assert-True ($envs[3] -match 'disable=mpris' -and $envs[3] -match 'safe=\r?\n') 'the 4th shell has II_DISABLE=mpris'
        Assert-True ($envs[4] -match 'safe=1' -and $envs[4] -match 'render=basic') 'the 5th shell has II_SAFE_MODE=1 and the basic render loop'
        Assert-True ($envs[0] -match 'version=dev') 'the shell is told the version (II_VERSION)'
    }
    Assert-Equal (Get-IiState $data 'lastSessionTrouble') '1' 'the next start knows this session had trouble'
    $ini = Get-Content (Join-Path $data 'state.ini') -Raw
    Assert-True ($ini -match '(?m)^disabled=mpris' -and $ini -match '(?m)^safe=1') 'safe mode is kept in state.ini [safety]'

    # ---- b: the next start of the same version keeps safe mode; safe-mode-off clears it -------------------------------
    $p = Start-IiHost $shell 'beat' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'safety: this version starts with safe mode, mpris off' 20) 'a new start keeps safe mode for this version'
    Assert-True (Wait-IiLog $data '(?s)safety: this version.*phase: awaiting-ready -> active' 30) 'the shell comes up'
    Add-Type -Namespace IiTest -Name Copy -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct COPYDATASTRUCT { public System.IntPtr dwData; public int cbData; public System.IntPtr lpData; }
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr SendMessage(System.IntPtr h, uint msg, System.IntPtr w, ref COPYDATASTRUCT d);
'@ -ErrorAction SilentlyContinue
    $hostWindow = [IntPtr]::Zero
    $cb = [IiTest.Win+EnumProc] { param($h, $l)
        $pid2 = 0; [void][IiTest.Win]::GetWindowThreadProcessId($h, [ref]$pid2)
        $sb = New-Object System.Text.StringBuilder 64; [void][IiTest.Win]::GetClassName($h, $sb, 64)
        if ($pid2 -eq $p.Id -and $sb.ToString().StartsWith('IiHostWindow')) { $script:hostWindow = $h }
        $true }
    [void][IiTest.Win]::EnumWindows($cb, [IntPtr]::Zero)
    Assert-True ($script:hostWindow -ne [IntPtr]::Zero) 'the host window is found'
    $text = 'safe-mode-off'
    $buf = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($text)
    $cds = New-Object IiTest.Copy+COPYDATASTRUCT
    $cds.dwData = [IntPtr]0x49490040; $cds.cbData = ($text.Length + 1) * 2; $cds.lpData = $buf
    $r = [IiTest.Copy]::SendMessage($script:hostWindow, 0x4A, [IntPtr]::Zero, [ref]$cds)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
    Assert-Equal ([int64]$r) 1 'the host accepts the command'
    Assert-True (Wait-IiLog $data 'safety: every part on again \(user\)' 10) 'safe-mode-off clears the safety settings'
    Assert-True (Wait-IiLog $data '(?s)every part on again.*shell: started pid' 20) 'and starts a fresh shell'
    $ini = Get-Content (Join-Path $data 'state.ini') -Raw
    Assert-True (-not ($ini -match '(?m)^disabled=\S') -and -not ($ini -match '(?m)^safe=1')) 'state.ini has nothing off'
    Assert-True ((Send-IiWmClose $p.Id) -ge 1) 'the host window closes'
    Assert-Equal (Wait-IiExit $p 20) 0 'the host ends normally'

    # ---- c: a different version starts with everything on ---------------------------------------------------------------
    $data = Join-Path $base 'c-data'
    New-Item -ItemType Directory -Force $data | Out-Null
    Set-Content (Join-Path $data 'state.ini') "[safety]`r`nversion=0.0.1-old`r`ndisabled=mpris`r`nsafe=1`r`n" -Encoding Unicode
    $p = Start-IiHost $shell 'beat' $data @{ II_TEST_WATCHDOG_MS = 400 }
    Assert-True (Wait-IiLog $data 'safety: new version dev, every part on again' 20) 'another version''s safe mode is dropped'
    Assert-True (Wait-IiLog $data 'phase: awaiting-ready -> active' 30) 'the shell comes up'
    Assert-True (-not ((Get-IiHostLog $data) -match 'shell: starts with')) 'and starts with nothing off'
    [void](Send-IiWmClose $p.Id)
    [void](Wait-IiExit $p 20)
} finally {
    Stop-IiStragglers @((Join-Path $base 'a-shell\quickshell.exe'))
}
Complete-IiTest
