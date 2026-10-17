# Cold-ish start measurement: copy a version dir with unbuffered I/O (robocopy /J, so the copy is not in
# the file cache), start ii-host from it with its own data dir, wait for the splash to close, print timeline.
#   coldstart.ps1 [-Src <version dir>] [-Tag t] [-NoCopy] [-Slow 15 [-Cores 2]]
#   first run of a -Tag = first start of that version (QML compiled); -NoCopy again = a normal start.
#   -Slow N: quickshell in a Job with the CPU capped (Cores x N % of one core) to play a slow PC.
# A real run: hides the taskbar and starts a real shell; close ii first.
param([string]$Src = '',
      [string]$Tag = 'c1', [switch]$NoCopy, [switch]$Boot, [int]$Timeout = 150, [int]$Slow = 0, [int]$Cores = 2)
$ErrorActionPreference = 'Stop'
if (-not $Src) {
    $inst = "$env:LOCALAPPDATA\Programs\ii-windows"
    $Src = "$inst\versions\" + ((Get-Content "$inst\current.txt" | Where-Object { $_ -like 'active=*' }) -replace 'active=', '')
}
$root = "$env:TEMP\ii-coldstart\$Tag"
if (-not $NoCopy) {
    if (Test-Path $root) { Remove-Item -Recurse -Force $root }
    robocopy $Src "$root\v" /E /J /NFL /NDL /NJH /NJS /NP | Out-Null
}
$data = "$root\data-" + (Get-Date -Format 'HHmmss')
New-Item -ItemType Directory -Force $data | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$root\v\ii-host.exe"
$a = @('--shell', "`"$root\v\quickshell\quickshell.exe`"", '--config', "`"$root\v\ii`"")
if ($Boot) { $a += '--boot' }
$psi.Arguments = $a -join ' '
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.EnvironmentVariables['II_DATA_DIR'] = $data
$t0 = Get-Date
$p = [System.Diagnostics.Process]::Start($psi)
if ($Slow) { . "$PSScriptRoot\slowjob.ps1"; $job = New-SlowJob -CoreSpeed $Slow -Cores $Cores; Add-ToSlowJob $job $p.Id
    # the host nests the shell in its own job, where the parent's CPU cap does not reach: cap the shell directly
    $qsw = [Diagnostics.Stopwatch]::StartNew(); $qs = $null
    while (-not $qs -and $qsw.ElapsedMilliseconds -lt 8000) { $qs = Get-Process quickshell -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" }; if (-not $qs) { Start-Sleep -Milliseconds 5 } }
    if ($qs) { $job2 = New-SlowJob -CoreSpeed $Slow -Cores $Cores; Add-ToSlowJob $job2 $qs[0].Id; "shell capped after $($qsw.ElapsedMilliseconds) ms" } else { "shell not found to cap" }
    "slow PC: $Cores cores at $Slow %" }
$log = "$data\host.log"
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Timeout -and -not $p.HasExited) {
    if ((Test-Path $log) -and ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match 'splash-closed')) { break }
    Start-Sleep -Milliseconds 250
}
Start-Sleep -Seconds 3
$hostLog = Get-Content $log
$shellPid = ($hostLog | Select-String 'shell: started pid (\d+)' | Select-Object -First 1).Matches.Groups[1].Value
"--- host"
$hostLog | Where-Object { $_ -notmatch 'watch-tick' } | Select-Object -First 70
"--- shell $shellPid"
try { $qp = Get-Process -Id $shellPid; "shell cpu: {0:n1} s user+kernel, wall {1:n1} s, threads {2}" -f $qp.TotalProcessorTime.TotalSeconds, ((Get-Date) - $qp.StartTime).TotalSeconds, $qp.Threads.Count; $hp = Get-Process -Id $p.Id; "host cpu: {0:n1} s" -f $hp.TotalProcessorTime.TotalSeconds } catch { "cpu query failed: $_" }
$sl = "$env:TEMP\quickshell\by-pid\$shellPid\log.log"
if (Test-Path $sl) { Get-Content $sl | Where-Object { $_ -match 'Launching|Startup:|Scanner|QML tree|Configuration Loaded|Indexed|appbar: Registered|WARN|ERROR' } | Select-Object -First 40 }
# normal close so the host restores everything
Add-Type -Namespace ColdRun -Name W -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr l);
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
'@
$found = New-Object System.Collections.Generic.List[IntPtr]
$cb = [ColdRun.W+EnumProc]{ param($h, $l); $x = [uint32]0; [void][ColdRun.W]::GetWindowThreadProcessId($h, [ref]$x)
    if ($x -eq $p.Id) { $sb = New-Object Text.StringBuilder 64; [void][ColdRun.W]::GetClassName($h, $sb, 64); if ($sb.ToString().StartsWith('IiHostWindow')) { $found.Add($h) } }; $true }
[void][ColdRun.W]::EnumWindows($cb, [IntPtr]::Zero)
foreach ($h in $found) { [void][ColdRun.W]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) }
if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {}; "KILLED host" }
"--- exit host log tail"
Get-Content $log | Select-Object -Last 6
