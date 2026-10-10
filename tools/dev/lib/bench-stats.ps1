# Parsing and statistics for the startup timeline (B02). Dot-source.

# "bench: +123.4 ms monitor-covered 1" lines of host.log -> @{ event; detail; ms } in file order.
function Read-IiBenchLog([string]$Path) {
    $events = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $events }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match 'bench: \+([\d.]+) ms (\S+)(?: (.*))?$') {
            $events += [pscustomobject]@{ event = $Matches[2]; detail = ([string]$Matches[3]).Trim(); ms = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
        }
    }
    $events
}

# The timeline of one run is only trustworthy if time never goes backwards.
function Test-IiBenchMonotonic($Events) {
    $last = -1.0
    foreach ($e in $Events) {
        if ($e.ms -lt $last) { return $false }
        $last = $e.ms
    }
    $true
}

# Nearest-rank percentile: the smallest value with at least p % of the data at or below it.
function Get-IiPercentile([double[]]$Values, [double]$Percent) {
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = $Values | Sort-Object
    $rank = [math]::Ceiling($Percent / 100.0 * $sorted.Count)
    if ($rank -lt 1) { $rank = 1 }
    [double]$sorted[[int]$rank - 1]
}

# runs: array of event arrays. Per "event detail" key: n, min, p50, p95, p99, max over the runs.
function Get-IiBenchSummary($Runs) {
    $byKey = [ordered]@{}
    foreach ($run in $Runs) {
        foreach ($e in $run) {
            $key = if ($e.detail) { "$($e.event) $($e.detail)" } else { $e.event }
            if (-not $byKey.Contains($key)) { $byKey[$key] = New-Object System.Collections.Generic.List[double] }
            $byKey[$key].Add($e.ms)
        }
    }
    foreach ($key in $byKey.Keys) {
        $v = [double[]]$byKey[$key].ToArray()
        [pscustomobject]@{
            event = $key; n = $v.Count
            min = ($v | Measure-Object -Minimum).Minimum
            p50 = Get-IiPercentile $v 50; p95 = Get-IiPercentile $v 95; p99 = Get-IiPercentile $v 99
            max = ($v | Measure-Object -Maximum).Maximum
        }
    }
}
