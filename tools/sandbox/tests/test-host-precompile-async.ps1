# Real host + slow fake compiler, isolated from the user's Explorer and ii session.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild
$base = New-IiTestDir 'ii-precompile-async'
$shell = New-IiFakeShell (Join-Path $base 'shell')
$p = $null
try {
    $data = Join-Path $base 'cancel'
    $envs = @{ II_TEST_PRECOMPILE = 1; II_FAKE_PRECOMPILE_MS = 20000; QML_DISK_CACHE_PATH = "$base\empty" }
    $p = Start-IiHost $shell 'window' $data $envs
    Assert-True (Wait-IiLog $data 'compiling the QML first' 10) 'the slow compiler started'
    Start-Sleep -Milliseconds 300
    Assert-True ((Get-IiHostLog $data) -notmatch 'shell: started pid') 'the shell waits for compilation'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Assert-True ((Send-IiWmClose $p.Id) -ge 1) 'the host still accepts close during compilation'
    Assert-Equal (Wait-IiExit $p 4) 0 'close finishes without waiting for the compiler'
    Assert-True ($sw.Elapsed.TotalSeconds -lt 4) 'the message loop remains responsive'
    Start-Sleep -Milliseconds 300
    Assert-Equal (Get-IiProcessesAt $shell).Count 0 'cancellation leaves no compiler or shell'

    foreach ($case in @(@{ Name = 'ok'; Code = 0; Delay = 400; Timeout = 5000 },
                        @{ Name = 'failed'; Code = 7; Delay = 400; Timeout = 5000 },
                        @{ Name = 'timeout'; Code = 0; Delay = 20000; Timeout = 300 })) {
        $data = Join-Path $base $case.Name
        $envs.II_FAKE_PRECOMPILE_MS = $case.Delay
        $envs.II_FAKE_PRECOMPILE_EXIT = $case.Code
        $envs.II_TEST_PRECOMPILE_TIMEOUT_MS = $case.Timeout
        $p = Start-IiHost $shell 'window' $data $envs
        Assert-True (Wait-IiLog $data 'shell: started pid' 15) "$($case.Name): launch resumes"
        $log = Get-IiHostLog $data
        Assert-Equal ([regex]::Matches($log, 'compiling the QML first')).Count 1 "$($case.Name): one compile attempt"
        $state = Get-Content "$data\state.ini" -Raw
        Assert-Equal ([bool]($state -match 'compiledFor=window')) ($case.Name -eq 'ok') "$($case.Name): only success is remembered"
        Send-IiWmClose $p.Id | Out-Null
        Assert-Equal (Wait-IiExit $p 6) 0 "$($case.Name): clean shutdown"
        Start-Sleep -Milliseconds 200
        Assert-Equal (Get-IiProcessesAt $shell).Count 0 "$($case.Name): no leftover processes"
    }
}
finally {
    if ($p -and -not $p.HasExited) { $p.Kill() }
    Stop-IiStragglers @($shell)
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
