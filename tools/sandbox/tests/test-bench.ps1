# B02: the benchmark harness itself. It proves the harness, not ii's speed:
#   - percentiles / summary are right on data with a known answer
#   - a non-monotonic timeline is detected
#   - the manifest has the fields the protocol asks for and none of the person's identity
#   - a real (inert, isolated) run of ii-host against the fake shell produces an ordered timeline
#     with per-monitor marks, and runs do not leak into each other's logs
# Numbers from the fake shell are NOT a baseline of the real shell.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
. "$PSScriptRoot\..\..\dev\lib\bench-stats.ps1"
Require-IiHostBuild

# --- statistics on known data -----------------------------------------------------------------
$v = [double[]](1..100)
Assert-Equal (Get-IiPercentile $v 50) 50 'p50 of 1..100 is 50 (nearest rank)'
Assert-Equal (Get-IiPercentile $v 95) 95 'p95 of 1..100 is 95'
Assert-Equal (Get-IiPercentile $v 99) 99 'p99 of 1..100 is 99'
Assert-Equal (Get-IiPercentile ([double[]]@(7)) 99) 7 'a single value is every percentile'
Assert-Equal $null (Get-IiPercentile ([double[]]@()) 50) 'no data gives no percentile, not zero'

$runA = @([pscustomobject]@{ event = 'ready'; detail = ''; ms = 100 }, [pscustomobject]@{ event = 'monitor-covered'; detail = '0'; ms = 80 })
$runB = @([pscustomobject]@{ event = 'ready'; detail = ''; ms = 300 }, [pscustomobject]@{ event = 'monitor-covered'; detail = '0'; ms = 90 })
$all = New-Object System.Collections.ArrayList
[void]$all.Add($runA)
[void]$all.Add($runB)
$s = @(Get-IiBenchSummary $all)
$ready = $s | Where-Object event -eq 'ready'
Assert-True ($ready.n -eq 2 -and $ready.min -eq 100 -and $ready.max -eq 300 -and $ready.p50 -eq 100) 'summary groups by event and keeps min/max/p50'
Assert-True (($s | Where-Object event -eq 'monitor-covered 0').n -eq 2) 'events with a detail (the monitor index) are separate series'

Assert-True (-not (Test-IiBenchMonotonic $runA)) 'a timeline whose clock went backwards is flagged'
Assert-True (Test-IiBenchMonotonic @([pscustomobject]@{ ms = 1 }, [pscustomobject]@{ ms = 1 }, [pscustomobject]@{ ms = 2 })) 'equal and increasing times are fine'

# --- the manifest -----------------------------------------------------------------------------
$tmp = New-IiTestDir 'ii-bench'
try {
    $manifestPath = Join-Path $tmp 'manifest.json'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:IiRepo 'tools\dev\bench-manifest.ps1') -Out $manifestPath -Cache warm | Out-Null
    Assert-PathExists $manifestPath 'the manifest was written'
    $raw = Get-Content $manifestPath -Raw
    $m = $raw | ConvertFrom-Json
    Assert-True ($m.commits.ii.head.Length -eq 40) 'it records the ii commit'
    Assert-True ($m.hardware.cpu -and $m.hardware.ramGiB -gt 0 -and @($m.hardware.displays).Count -ge 1) 'CPU, RAM and displays are recorded'
    Assert-True ($m.windows.build -match '^\d+\.\d+') 'the Windows build is recorded'
    Assert-Equal $m.protocol.cache 'warm' 'cache state is whatever the caller declared'
    Assert-True ($raw -notmatch [regex]::Escape($env:USERNAME)) 'the user name is not in the manifest'
    Assert-True ($raw -notmatch [regex]::Escape($env:COMPUTERNAME)) 'the computer name is not in the manifest'

    # --- a real inert run ---------------------------------------------------------------------
    $shell = New-IiFakeShell (Join-Path $tmp 'shell')
    $out = Join-Path $tmp 'out'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:IiRepo 'tools\dev\bench-startup.ps1') `
        -HostExe $script:IiHostExe -ShellExe $shell -Config window -Runs 3 -Cache warm -Inert -OutDir $out -ReadyTimeoutSec 90 | Out-Null
    Assert-Equal $LASTEXITCODE 0 'the harness ran'
    $bench = Get-Content (Join-Path $out 'bench.json') -Raw | ConvertFrom-Json
    Assert-Equal $bench.runs 3 'three runs were measured'
    $events = @($bench.summary | ForEach-Object { $_.event })
    Assert-True ($events -contains 'shell-launched' -and $events -contains 'ready') 'the timeline has launch and ready'
    Assert-True (@($events | Where-Object { $_ -like 'monitor-covered *' }).Count -ge 1) 'and a mark for every monitor the shell covered'
    foreach ($run in $bench.raw) {
        $names = @($run.events | ForEach-Object { $_.event })
        Assert-True ($names.IndexOf('shell-launched') -lt $names.IndexOf('ready')) "run $($run.run): launch comes before ready"
        Assert-True (Test-IiBenchMonotonic @($run.events)) "run $($run.run): timestamps never go backwards"
    }
    $logs = @(Get-ChildItem $out -Recurse -Filter host.log)
    Assert-Equal $logs.Count 3 'each run has its own log, so a result cannot come from another run'
    $r = $bench.summary | Where-Object event -eq 'ready'
    Assert-True ($r.n -eq 3 -and $r.p50 -gt 0 -and $r.p50 -lt 60000) 'ready has a plausible distribution over the 3 runs'
    Assert-True ((Test-Path (Join-Path $out 'manifest.json'))) 'the run directory carries its manifest'
}
finally {
    Stop-IiStragglers @((Join-Path $tmp 'shell\quickshell.exe'))
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
