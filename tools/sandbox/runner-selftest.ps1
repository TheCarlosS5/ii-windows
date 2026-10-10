# Proves the test driver itself (B01): run-tests.ps1 must fail when a test fails, throws, exits
# non-zero or hangs, and must not call a skip or an assertion-free run a pass. It checks the exit
# codes a parent process really sees. It says nothing about ii's own modules.
#   runner-selftest.ps1 [-Shell pwsh.exe]      exit 0 only if every check below holds
param([string]$Shell = 'powershell.exe')
$ErrorActionPreference = 'Stop'
$fx = Join-Path $PSScriptRoot 'fixtures\runner'
$runner = Join-Path $PSScriptRoot 'run-tests.ps1'
$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Runner([string[]]$Fixtures, [string[]]$Extra = @()) {
    $out = Join-Path $env:TEMP ('ii-runner-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $files = $Fixtures | ForEach-Object { "`"$fx\$_.ps1`"" }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$runner`"", '-Shell', $Shell, '-OutDir', "`"$out`"") + $Extra
    $argList += @('-Path', ($files -join ','))
    $p = Start-Process -FilePath $Shell -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
    $results = $null
    if (Test-Path "$out\results.json") { $results = Get-Content "$out\results.json" -Raw | ConvertFrom-Json }
    [pscustomobject]@{ ExitCode = $p.ExitCode; Results = $results; Out = $out }
}

function Check([string]$What, [bool]$Ok) {
    if ($Ok) { "ok   $What" } else { "FAIL $What"; $failures.Add($What) }
}

$r = Invoke-Runner @('pass')
Check 'a passing test exits 0' ($r.ExitCode -eq 0)
Check 'it is reported as passed with 1 assertion' ($r.Results.results[0].status -eq 'passed' -and $r.Results.results[0].assertions -eq 1)

$r = Invoke-Runner @('exit7')
Check 'exit code 7 makes the runner exit non-zero' ($r.ExitCode -ne 0)
Check 'exit code 7 is reported as failed with the code' ($r.Results.results[0].status -eq 'failed' -and $r.Results.results[0].exitCode -eq 7)

$r = Invoke-Runner @('throw')
Check 'an exception makes the runner exit non-zero' ($r.ExitCode -ne 0)
Check 'the exception is reported as failed' ($r.Results.results[0].status -eq 'failed')

$r = Invoke-Runner @('assert-fail')
Check 'a failed assertion makes the runner exit non-zero' ($r.ExitCode -ne 0)
Check 'the failing check is in the assertion log' ((Get-Content "$($r.Out)\assert-fail.result.json" -Raw) -match 'second check must fail')

$r = Invoke-Runner @('hang') @('-TimeoutSec', '3')
Check 'a timeout makes the runner exit non-zero' ($r.ExitCode -ne 0)
Check 'the timeout is reported as timeout, not as a pass' ($r.Results.results[0].status -eq 'timeout')
Start-Sleep 1
$orphans = @(Get-CimInstance Win32_Process -Filter "Name like 'powershell%'" | Where-Object { $_.CommandLine -like '*ii-runner-fixture-child*' })
Check 'the timed-out test left no child process behind' ($orphans.Count -eq 0)
$orphans | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$r = Invoke-Runner @('skip')
Check 'a skipped test exits 0 but is reported as skipped' ($r.ExitCode -eq 0 -and $r.Results.results[0].status -eq 'skipped' -and $r.Results.counts.passed -eq 0)
Check 'the skip carries its reason' ($r.Results.results[0].skipReason -like '*hardware*')

$r = Invoke-Runner @('no-assertions') @('-RequireAssertions')
Check '-RequireAssertions fails a test that checked nothing' ($r.ExitCode -ne 0 -and $r.Results.results[0].detail -like '*no assertions*')
$r = Invoke-Runner @('no-assertions')
Check 'without -RequireAssertions the same test passes' ($r.ExitCode -eq 0)

$r = Invoke-Runner @('pass', 'exit7', 'pass')
Check 'one failure among passes fails the whole run' ($r.ExitCode -ne 0 -and $r.Results.counts.passed -eq 2 -and $r.Results.counts.failed -eq 1)

if ($failures.Count -gt 0) { "$($failures.Count) check(s) failed"; exit 1 }
'runner self-test: all checks passed'
exit 0
