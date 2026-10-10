# Test helpers. Dot-source from a test script:   . "$PSScriptRoot\lib\ii-test.ps1"
# A test finishes in one of four ways the runner understands:
#   exit 0                 passed (and, with -RequireAssertions, at least one Assert-* ran)
#   exit non-zero / throw  failed
#   Skip-Test 'reason'     skipped (exit code 77): never counted as a pass
#   no exit within timeout timeout (the runner kills the test's process tree)
# Assert-* throw on failure, so a failed check ends the script with a non-zero exit code.
$script:IiAssertions = 0
$script:IiAssertionLog = New-Object System.Collections.Generic.List[string]

function Assert-True([bool]$Condition, [string]$Message = 'condition is false') {
    $script:IiAssertions++
    if (-not $Condition) { $script:IiAssertionLog.Add("FAIL: $Message"); Write-IiTestResult; throw "ASSERT FAILED: $Message" }
    $script:IiAssertionLog.Add("ok: $Message")
}

function Assert-Equal($Actual, $Expected, [string]$Message = '') {
    $label = if ($Message) { $Message } else { 'values are equal' }
    $script:IiAssertions++
    if ($Actual -ne $Expected) {
        $script:IiAssertionLog.Add("FAIL: $label (expected '$Expected', got '$Actual')")
        Write-IiTestResult
        throw "ASSERT FAILED: $label (expected '$Expected', got '$Actual')"
    }
    $script:IiAssertionLog.Add("ok: $label")
}

function Assert-PathExists([string]$Path, [string]$Message = '') {
    Assert-True (Test-Path -LiteralPath $Path) $(if ($Message) { $Message } else { "exists: $Path" })
}

function Assert-PathMissing([string]$Path, [string]$Message = '') {
    Assert-True (-not (Test-Path -LiteralPath $Path)) $(if ($Message) { $Message } else { "does not exist: $Path" })
}

function Skip-Test([string]$Reason) {
    Write-IiTestResult -Skipped $Reason
    Write-Output "SKIPPED: $Reason"
    exit 77
}

# The runner sets II_TEST_RESULT to a per-test file; the assertion count goes there so the
# aggregate can tell "ran N checks" from "ran nothing and exited 0".
function Write-IiTestResult([string]$Skipped = '') {
    if (-not $env:II_TEST_RESULT) { return }
    $o = [ordered]@{ assertions = $script:IiAssertions; skipped = $Skipped; log = @($script:IiAssertionLog) }
    $o | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $env:II_TEST_RESULT -Encoding UTF8
}

function Complete-IiTest { Write-IiTestResult; Write-Output "assertions: $script:IiAssertions"; exit 0 }
