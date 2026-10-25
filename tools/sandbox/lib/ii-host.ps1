# Helpers for tests that run a real ii-host.exe as an isolated, inert instance:
#   - its own data folder (II_DATA_DIR): own state.ini, host.log, mutex and window class, so it
#     never reads or changes what the ii that is really running keeps
#   - II_NO_UI=1: no message boxes, and restoreAll leaves Explorer's taskbar and icons alone
#   - all the hiding switches off (--no-taskbar --no-icons ...), so nothing on screen changes
# Dot-source after lib\ii-test.ps1.
Add-Type -Namespace IiTest -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr l);
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
'@

$script:IiRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
# The newest host build (host\build, or host\build-clang where the host is compiled with clang-cl).
$script:IiHostBuild = @('host\build', 'host\build-clang') | ForEach-Object { Join-Path $script:IiRepo $_ } |
    Where-Object { Test-Path (Join-Path $_ 'ii-host.exe') } | Sort-Object { (Get-Item (Join-Path $_ 'ii-host.exe')).LastWriteTime } |
    Select-Object -Last 1
if (-not $script:IiHostBuild) { $script:IiHostBuild = Join-Path $script:IiRepo 'host\build' }
$script:IiHostExe = Join-Path $script:IiHostBuild 'ii-host.exe'
$script:IiFakeShell = Join-Path $script:IiHostBuild 'ii-fake-shell.exe'
$script:InertFlags = @('--no-taskbar', '--no-icons', '--no-hook', '--keep-banners', '--no-theme', '--no-nightlight', '--no-splash')

function Require-IiHostBuild {
    if (-not (Test-Path $script:IiHostExe) -or -not (Test-Path $script:IiFakeShell)) {
        Skip-Test "host not built: run cmake --build host\build --target ii-host ii-fake-shell ($script:IiHostExe)"
    }
}

function New-IiTestDir([string]$Prefix = 'ii-host') {
    $d = Join-Path $env:TEMP ($Prefix + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $d | Out-Null
    $d
}

# A copy of the fake shell under the name and folder the host will be told to run.
function New-IiFakeShell([string]$Dir, [string]$Name = 'quickshell.exe') {
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $p = Join-Path $Dir $Name
    Copy-Item $script:IiFakeShell $p -Force
    $p
}

function Start-IiProcess([string]$Exe, [string[]]$Arguments, [string]$DataDir, [hashtable]$Env = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['II_DATA_DIR'] = $DataDir
    $psi.EnvironmentVariables['II_NO_UI'] = '1'
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    [System.Diagnostics.Process]::Start($psi)
}

function Start-IiHost([string]$ShellExe, [string]$Mode, [string]$DataDir, [hashtable]$Env = @{}, [string[]]$Extra = @()) {
    $args = @('--shell', $ShellExe, '--config', $Mode) + $script:InertFlags + $Extra
    Start-IiProcess $script:IiHostExe $args $DataDir $Env
}

function Get-IiHostLog([string]$DataDir) {
    $f = Join-Path $DataDir 'host.log'
    if (Test-Path $f) { Get-Content $f -Raw -Encoding UTF8 } else { '' }
}

function Wait-IiLog([string]$DataDir, [string]$Pattern, [int]$TimeoutSec = 20) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ((Get-IiHostLog $DataDir) -match $Pattern) { return $true }
        Start-Sleep -Milliseconds 200
    }
    $false
}

# Waits for exit; returns the exit code, or $null (and kills it) on timeout.
function Wait-IiExit($Process, [int]$TimeoutSec = 30) {
    if ($Process.WaitForExit($TimeoutSec * 1000)) { return $Process.ExitCode }
    try { $Process.Kill() } catch {}
    $null
}

function Send-IiWmClose([int]$ProcessId) {
    $found = New-Object System.Collections.Generic.List[IntPtr]
    $cb = [IiTest.Win+EnumProc]{
        param($h, $l)
        $pid2 = [uint32]0
        [void][IiTest.Win]::GetWindowThreadProcessId($h, [ref]$pid2)
        if ($pid2 -eq $ProcessId) {
            $sb = New-Object System.Text.StringBuilder 64
            [void][IiTest.Win]::GetClassName($h, $sb, 64)
            if ($sb.ToString().StartsWith('IiHostWindow')) { $found.Add($h) }
        }
        $true
    }
    [void][IiTest.Win]::EnumWindows($cb, [IntPtr]::Zero)
    foreach ($h in $found) { [void][IiTest.Win]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) }
    $found.Count
}

# Processes whose executable is exactly this path.
function Get-IiProcessesAt([string]$ExePath) {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch {}
        $p -and ($p -ieq $ExePath)
    })
}

function Get-IiState([string]$DataDir, [string]$Key) {
    $f = Join-Path $DataDir 'state.ini'
    if (-not (Test-Path $f)) { return $null }
    $m = Select-String -Path $f -Pattern "^$Key=(.*)$" | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { $null }
}

function Stop-IiStragglers([string[]]$ExePaths) {
    foreach ($p in $ExePaths) { Get-IiProcessesAt $p | ForEach-Object { try { $_.Kill() } catch {} } }
}
