# Host-side driver for the test sandbox.
#   sbx.ps1 start                 open the sandbox (if not running) and wait for the agent
#   sbx.ps1 run <script.ps1> [-Timeout 120]   run a script inside, print its output
#   sbx.ps1 stop                  close the sandbox (discarding everything inside)
param([Parameter(Mandatory, Position = 0)][string]$Action, [Parameter(Position = 1)][string]$Script = '', [int]$Timeout = 180)
$x = 'C:\Users\Calos\sbx-xchg'
$wsb = 'C:\Users\Calos\Desktop\ii-windows\tools\sandbox\ii-test.wsb'

function Test-Agent {
    $hb = Join-Path $x 'outbox\_heartbeat.txt'
    if (-not (Test-Path $hb)) { return $false }
    return ((Get-Date) - (Get-Item $hb).LastWriteTime).TotalSeconds -lt 5
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
        while (-not (Test-Path "$x\outbox\$name.done")) {
            if ($sw.Elapsed.TotalSeconds -gt $Timeout) { "timeout after $Timeout s"; break }
            Start-Sleep -Milliseconds 500
        }
        Get-Content "$x\outbox\$name.txt" -ErrorAction SilentlyContinue
    }
    'stop' {
        Get-Process WindowsSandbox, WindowsSandboxClient, WindowsSandboxRemoteSession -ErrorAction SilentlyContinue | Stop-Process -Force
        'stopped'
    }
}
