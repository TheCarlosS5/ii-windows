# Startup benchmark (B02): launches ii-host N times and turns the "bench:" timeline marks in each
# run's host.log into per-phase distributions (min / p50 / p95 / p99 / max), with the raw data.
#
#   bench-startup.ps1 -HostExe <ii-host.exe> -ShellExe <quickshell.exe> -Config <dir> -Runs 5 -Cache warm
#   bench-startup.ps1 -ParseOnly -Logs a\host.log,b\host.log        summarize logs already collected
#   -Inert  isolated instance that hides nothing (II_DATA_DIR + II_NO_UI + all hiding switches off):
#           for validating this harness or the timeline marks, NOT a baseline of the real thing
#
# A real run (no -Inert) hides the taskbar and starts a real shell: it refuses to run while ii or
# any quickshell.exe is already running, because two shells on one desktop measure nothing useful
# and fight over the same screen. Close ii first, on a test machine.
# "cold" = the caller made it cold (cleared the QML cache of a test profile, rebooted, ...): this
# script does not clear anyone's cache; it records what the caller says in the manifest.
param(
    [string]$HostExe, [string]$ShellExe, [string]$Config, [int]$Runs = 5,
    [ValidateSet('cold', 'warm', 'unknown')][string]$Cache = 'unknown',
    [string]$OutDir = '', [string[]]$HostArgs = @(), [switch]$Inert, [switch]$Boot,
    [switch]$ParseOnly, [string[]]$Logs = @(), [int]$ReadyTimeoutSec = 120
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\bench-stats.ps1"
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('ii-bench-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$allRuns = @()
if ($ParseOnly) {
    foreach ($l in $Logs) { $allRuns += , @(Read-IiBenchLog $l) }
} else {
    if (-not (Test-Path $HostExe) -or -not (Test-Path $ShellExe)) { throw 'HostExe and ShellExe must exist' }
    if (-not $Inert) {
        $running = Get-Process -Name ii-host, quickshell -ErrorAction SilentlyContinue
        if ($running) { throw "ii or a quickshell is running ($($running.ProcessName -join ', ')): close it first, a real run needs the desktop to itself" }
    }
    Add-Type -Namespace IiBenchRun -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr l);
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
'@
    for ($i = 1; $i -le $Runs; $i++) {
        $dataDir = Join-Path $OutDir "run$i-data"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $HostExe
        $argList = @('--shell', $ShellExe)
        if ($Config) { $argList += @('--config', $Config) }
        if ($Boot) { $argList += '--boot' }
        if ($Inert) {
            $argList += @('--no-taskbar', '--no-icons', '--no-hook', '--keep-banners', '--no-theme', '--no-nightlight', '--no-splash')
            $psi.EnvironmentVariables['II_NO_UI'] = '1'
        }
        if ($Inert -or $true) { $psi.EnvironmentVariables['II_DATA_DIR'] = $dataDir } # every run: its own log, never mixed with an older one
        $psi.Arguments = (($argList + $HostArgs) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $log = Join-Path $dataDir 'host.log'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ready = $false
        while ($sw.Elapsed.TotalSeconds -lt $ReadyTimeoutSec -and -not $p.HasExited) {
            if ((Test-Path $log) -and ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match '(?m)bench: \+[\d.]+ ms ready(-partial)?\s*$')) { $ready = $true; break }
            Start-Sleep -Milliseconds 200
        }
        if ($ready) { Start-Sleep -Seconds 2 } # let the splash finish its fade
        # Normal close, so the host restores whatever it changed.
        $found = New-Object System.Collections.Generic.List[IntPtr]
        $cb = [IiBenchRun.Win+EnumProc]{
            param($h, $l)
            $x = [uint32]0
            [void][IiBenchRun.Win]::GetWindowThreadProcessId($h, [ref]$x)
            if ($x -eq $p.Id) { $sb = New-Object Text.StringBuilder 64; [void][IiBenchRun.Win]::GetClassName($h, $sb, 64); if ($sb.ToString().StartsWith('IiHostWindow')) { $found.Add($h) } }
            $true
        }
        [void][IiBenchRun.Win]::EnumWindows($cb, [IntPtr]::Zero)
        foreach ($h in $found) { [void][IiBenchRun.Win]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) }
        if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {} }
        $events = @(Read-IiBenchLog $log)
        if (-not $ready) { Write-Warning "run $i did not become ready in $ReadyTimeoutSec s" }
        if (-not (Test-IiBenchMonotonic $events)) { Write-Warning "run ${i}: timeline is not monotonic" }
        $allRuns += , $events
    }
}

$summary = @(Get-IiBenchSummary $allRuns)
$raw = for ($i = 0; $i -lt $allRuns.Count; $i++) { [ordered]@{ run = $i + 1; events = $allRuns[$i] } }
[ordered]@{ runs = $allRuns.Count; cache = $Cache; inert = [bool]$Inert; summary = $summary; raw = $raw } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'bench.json') -Encoding UTF8
& "$PSScriptRoot\bench-manifest.ps1" -Out (Join-Path $OutDir 'manifest.json') -Cache $Cache | Out-Null
$summary | Format-Table event, n, min, p50, p95, p99, max -AutoSize | Out-String -Width 200
"results: $OutDir"
