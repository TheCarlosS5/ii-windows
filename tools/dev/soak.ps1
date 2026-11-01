# Plan 2026-10-31, D8: does ii's memory stay flat over a long session? Samples quickshell.exe and ii-host.exe every
# -Every seconds for -Hours (private memory, working set, handles, threads, GDI and USER objects) into a CSV, and ends
# with a verdict: after the first hour (start-up and caches), each process' private memory should stay within ±10 %.
#   soak.ps1 [-Hours 8] [-Every 300] [-Out soak.csv] [-Process quickshell,ii-host]
# Use the PC normally meanwhile (browser with videos, music, two desktops, notifications). Ctrl+C stops it; -Report
# <csv> gives the verdict of a run that was stopped.
param([double]$Hours = 8, [int]$Every = 300, [string]$Out = '', [string[]]$Process = @('quickshell', 'ii-host'),
      [string]$Report = '')
$ErrorActionPreference = 'Stop'
Add-Type -Namespace IiSoak -Name Gui -MemberDefinition @'
[DllImport("user32.dll")] public static extern uint GetGuiResources(System.IntPtr process, uint flags);
'@

function Show-Verdict([string]$Csv) {
    $rows = Import-Csv $Csv
    if (-not $rows) { 'no samples'; return }
    $start = [datetime]$rows[0].time
    foreach ($group in ($rows | Group-Object process)) {
        $settled = @($group.Group | Where-Object { ([datetime]$_.time - $start).TotalMinutes -ge 60 })
        if ($settled.Count -lt 2) { "{0}: under an hour of samples, no verdict" -f $group.Name; continue }
        $private = $settled | ForEach-Object { [double]::Parse($_.privateMB, [Globalization.CultureInfo]::InvariantCulture) }
        $first = $private[0]; $last = $private[-1]
        $max = ($private | Measure-Object -Maximum).Maximum; $min = ($private | Measure-Object -Minimum).Minimum
        $handles = $settled | ForEach-Object { [int]$_.handles }
        $flat = $first -gt 0 -and ($max - $min) / $first -le 0.10
        "{0}: private {1:N0} -> {2:N0} MB (min {3:N0}, max {4:N0}) after the first hour; handles {5} -> {6}; {7}" -f $group.Name,
            $first, $last, $min, $max, $handles[0], $handles[-1], $(if ($flat) { 'FLAT (ok)' } else { 'GROWS: look at images without sourceSize, DWM thumbnails, models that only grow' })
    }
}

if ($Report) { Show-Verdict $Report; return }
if (-not $Out) { $Out = Join-Path (Get-Location) ("soak-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmm')) }
'time,process,pid,privateMB,workingSetMB,handles,threads,gdi,user' | Set-Content $Out -Encoding UTF8
$end = (Get-Date).AddHours($Hours)
"soak: every $Every s until $end -> $Out"
while ((Get-Date) -lt $end) {
    foreach ($name in $Process) {
        foreach ($p in @(Get-Process $name -ErrorAction SilentlyContinue)) {
            try {
                $gdi = [IiSoak.Gui]::GetGuiResources($p.Handle, 0); $user = [IiSoak.Gui]::GetGuiResources($p.Handle, 1)
            } catch { $gdi = -1; $user = -1 }
            # Invariant numbers: a Spanish Windows would write 147,7 and break the CSV.
            $line = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0},{1},{2},{3:F1},{4:F1},{5},{6},{7},{8}',
                (Get-Date -Format 's'), $name, $p.Id, ($p.PrivateMemorySize64 / 1MB), ($p.WorkingSet64 / 1MB), $p.HandleCount,
                $p.Threads.Count, $gdi, $user)
            Add-Content $Out $line
        }
    }
    Start-Sleep -Seconds $Every
}
Show-Verdict $Out
