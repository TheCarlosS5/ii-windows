# Host-side driver for the test sandbox.
#   sbx.ps1 start                 open the sandbox (if not running) and wait for the agent
#   sbx.ps1 run <script.ps1> [-Timeout 120]   run a script inside, print its output
#   sbx.ps1 stop                  close the sandbox (discarding everything inside)
param([Parameter(Mandatory, Position = 0)][string]$Action, [Parameter(Position = 1)][string]$Script = '', [int]$Timeout = 180)
$x = "$env:USERPROFILE\sbx-xchg"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
# Windows Sandbox wants absolute folders: fill the template for this machine.
New-Item -ItemType Directory -Force "$x\inbox", "$x\outbox", "$x\done" | Out-Null
$wsb = Join-Path $x 'ii-test.wsb'
(Get-Content "$PSScriptRoot\ii-test.wsb.template" -Raw).Replace('{REPO}', $repo).Replace('{XCHG}', $x) | Set-Content $wsb -Encoding UTF8

function Test-Agent([int]$MaxAge = 900) {
    # The agent refreshes the heartbeat between scripts, so a long script makes it look stale;
    # also require the sandbox client to be running.
    $hb = Join-Path $x 'outbox\_heartbeat.txt'
    if (-not (Test-Path $hb)) { return $false }
    if (-not (Get-Process WindowsSandboxRemoteSession, WindowsSandboxClient -ErrorAction SilentlyContinue)) { return $false }
    return ((Get-Date) - (Get-Item $hb).LastWriteTime).TotalSeconds -lt $MaxAge
}

switch ($Action) {
    'start' {
        if (Test-Agent) { 'agent already running'; return }
        Remove-Item "$x\inbox\*", "$x\outbox\*", "$x\done\*" -Force -ErrorAction SilentlyContinue
        Start-Process $wsb
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Agent)) {
            if ($sw.Elapsed.TotalSeconds -gt 240) { 'sandbox agent did not start in 240 s'; exit 1 }
            Start-Sleep 2
        }
        Get-Content "$x\outbox\_agent.txt"
        "ready after {0:N0} s" -f $sw.Elapsed.TotalSeconds
    }
    'run' {
        if (-not (Test-Agent)) { 'agent not running (sbx.ps1 start)'; exit 1 }
        $name = '{0:yyyyMMdd-HHmmss-fff}-{1}' -f (Get-Date), [IO.Path]::GetFileNameWithoutExtension($Script)
        Copy-Item $Script "$x\inbox\$name.ps1"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false
        while (-not (Test-Path "$x\outbox\$name.done")) {
            if ($sw.Elapsed.TotalSeconds -gt $Timeout) { $timedOut = $true; break }
            Start-Sleep -Milliseconds 500
        }
        Get-Content "$x\outbox\$name.txt" -ErrorAction SilentlyContinue
        # A timeout or a failing script must reach the caller as a non-zero exit code, never as
        # a quiet end of output.
        if ($timedOut) { "timeout after $Timeout s"; exit 124 }
        $exitFile = "$x\outbox\$name.exit"
        if (-not (Test-Path $exitFile)) { 'sandbox agent did not report an exit code (outdated agent?)'; exit 125 }
        $code = [int](Get-Content $exitFile -Raw)
        if ($code -ne 0) { "script exited with code $code"; exit $code }
    }
    'stop' {
        Get-Process WindowsSandbox, WindowsSandboxClient, WindowsSandboxRemoteSession -ErrorAction SilentlyContinue | Stop-Process -Force
        Remove-Item (Join-Path $x 'outbox\_heartbeat.txt') -ErrorAction SilentlyContinue
        'stopped'
    }
}
