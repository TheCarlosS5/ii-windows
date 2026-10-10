# Runs test scripts one by one, each in its own process, and reports per-test results.
#   run-tests.ps1 -Path tools\sandbox\tests\test-banners.ps1 [-Path ...]   single tests
#   run-tests.ps1 -Suite tools\sandbox\tests -Filter 'test-*.ps1'          a folder
#   -TimeoutSec 120  per test; the whole process tree of a test that exceeds it is killed
#   -RequireAssertions  a test that exits 0 without having run any Assert-* is a failure
#   -OutDir <dir>    where this run's results go (default: a new folder under %TEMP%\ii-tests)
#   -Shell powershell.exe|pwsh.exe  interpreter for the tests (default: Windows PowerShell 5.1)
# Exit code: 0 only if every selected test passed or was skipped; 1 if any failed, timed out or
# crashed; 2 if nothing was selected. A skipped test is reported as skipped, never as passed.
# Results live in <OutDir>\results.json (one object per test) and <OutDir>\<name>.log.
param(
    [string[]]$Path = @(),
    [string]$Suite = '',
    [string]$Filter = '*.ps1',
    [int]$TimeoutSec = 120,
    [switch]$RequireAssertions,
    [string]$OutDir = '',
    [string]$Shell = 'powershell.exe'
)
$ErrorActionPreference = 'Stop'

$tests = @()
# powershell -File passes "a","b" as the single string a,b: accept both forms.
foreach ($p in ($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) { $tests += (Resolve-Path -LiteralPath $p.Trim('"')).Path }
if ($Suite) { $tests += @(Get-ChildItem -LiteralPath $Suite -Filter $Filter -File | Sort-Object Name | ForEach-Object { $_.FullName }) }
if ($tests.Count -eq 0) { Write-Output 'no tests selected'; exit 2 }

# Every run gets a fresh folder: a result can only come from this run, never from older logs.
$runId = '{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), ([guid]::NewGuid().ToString('N').Substring(0, 6))
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP "ii-tests\$runId" }
if ((Test-Path -LiteralPath $OutDir) -and (Get-ChildItem -LiteralPath $OutDir -Force | Select-Object -First 1)) {
    throw "OutDir must be empty or new: $OutDir"
}
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Stop-ProcessTree([int]$RootPid) {
    # taskkill /T walks the tree of this test only; nothing else on the machine is touched.
    & taskkill.exe /PID $RootPid /T /F *> $null
}

$results = @()
foreach ($test in $tests) {
    $name = [IO.Path]::GetFileNameWithoutExtension($test)
    $log = Join-Path $OutDir "$name.log"
    $resultFile = Join-Path $OutDir "$name.result.json"
    $started = Get-Date
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = 'failed'
    $exitCode = $null
    $detail = ''

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Shell
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$test`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['II_TEST_RESULT'] = $resultFile
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        # Drain both pipes asynchronously: a chatty test must not block on a full pipe.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if ($proc.WaitForExit($TimeoutSec * 1000)) {
            $proc.WaitForExit() # flush async readers
            $exitCode = $proc.ExitCode
            if ($exitCode -eq 0) { $status = 'passed' }
            elseif ($exitCode -eq 77) { $status = 'skipped' }
            else { $status = 'failed'; $detail = "exit code $exitCode" }
        } else {
            $status = 'timeout'
            $detail = "no exit after $TimeoutSec s; process tree killed"
            Stop-ProcessTree $proc.Id
            [void]$proc.WaitForExit(5000)
        }
        $outText = if ($outTask.Wait(5000)) { $outTask.Result } else { '(unfinished)' }
        $errText = if ($errTask.Wait(5000)) { $errTask.Result } else { '(unfinished)' }
        Set-Content -LiteralPath $log -Value "--- stdout ---`r`n$outText`r`n--- stderr ---`r`n$errText" -Encoding UTF8
    } catch {
        $status = 'failed'
        $detail = "runner exception: $($_.Exception.Message)"
        Set-Content -LiteralPath $log -Value $detail -Encoding UTF8
    } finally {
        if ($proc) { $proc.Dispose() }
    }

    $assertions = 0
    $skipReason = ''
    if (Test-Path -LiteralPath $resultFile) {
        try {
            $r = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
            $assertions = [int]$r.assertions
            $skipReason = [string]$r.skipped
        } catch { $detail = ($detail + ' unreadable result file').Trim() }
    }
    if ($status -eq 'skipped' -and -not $skipReason) { $skipReason = 'skipped without a reason' }
    if ($status -eq 'passed' -and $RequireAssertions -and $assertions -eq 0) {
        $status = 'failed'
        $detail = 'exited 0 but ran no assertions'
    }

    $results += [pscustomobject]@{
        name = $name; script = $test; status = $status; exitCode = $exitCode; assertions = $assertions
        detail = $detail; skipReason = $skipReason
        started = $started.ToString('o'); durationMs = [int]$sw.ElapsedMilliseconds; log = $log
    }
    $note = if ($detail) { "  $detail" } elseif ($skipReason) { "  $skipReason" } else { '' }
    '{0,-8} {1}  ({2} ms){3}' -f $status.ToUpper(), $name, [int]$sw.ElapsedMilliseconds, $note
}

$counts = @{}
foreach ($s in 'passed', 'failed', 'timeout', 'skipped') { $counts[$s] = @($results | Where-Object { $_.status -eq $s }).Count }
$summary = [ordered]@{ runId = $runId; shell = $Shell; total = $results.Count; counts = $counts; results = $results }
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'results.json') -Encoding UTF8
'total {0}: {1} passed, {2} failed, {3} timeout, {4} skipped  -> {5}' -f $results.Count, $counts.passed, $counts.failed, $counts.timeout, $counts.skipped, $OutDir

if ($counts.failed -gt 0 -or $counts.timeout -gt 0) { exit 1 }
exit 0
