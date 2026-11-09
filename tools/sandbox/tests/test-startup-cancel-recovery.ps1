# Pending rollout + real host + fake slow compiler. No real installation or Explorer changes.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
. "$PSScriptRoot\..\..\package\ii-runtime.ps1"
Require-IiHostBuild
$base = New-IiTestDir 'ii-cancel-recovery'
$root = Join-Path $base 'install'
$version = "$root\versions\new"
New-Item -ItemType Directory -Force $version, "$root\versions\old", "$base\data" | Out-Null
Copy-Item "$script:IiHostBuild\ii-launcher.exe" $root
Copy-Item $script:IiHostExe $version
Copy-Item $script:IiFakeShell "$root\versions\old\ii-host.exe"
$shell = New-IiFakeShell "$version\quickshell"
$envs = @{ II_TEST_PRECOMPILE = 1; II_FAKE_PRECOMPILE_MS = 20000; QML_DISK_CACHE_PATH = "$base\empty" }
$launcher = $null; $hostProcess = $null
try {
    foreach ($i in 0..3) {
        $data = "$base\cancel-$i"
        Write-IiCurrent $root 'new' 'old' 'pending' 0
        $launcher = Start-IiProcess "$root\ii-launcher.exe" (@('--shell', $shell, '--config', 'window') + $script:InertFlags) $data $envs
        Assert-True (Wait-IiLog $data 'compiling the QML first' 10) 'pending version reached cancellable precompile'
        $hostProcess = Get-Process -Id ([int](Get-IiState $data 'hostPid'))
        if ($i % 2) { Send-IiMessage $hostProcess.Id 'IiHostWindow' 0x312 1 | Out-Null }
        else { Send-IiWmClose $hostProcess.Id | Out-Null }
        Assert-True ($hostProcess.WaitForExit(5000)) 'the cancelled host exits promptly'
        Assert-Equal (Wait-IiExit $launcher 5) 0 'the launcher accepts cancellation'
        Assert-True ((Get-IiHostLog $data) -match 'startup: cancelled by the user') 'the host distinguishes voluntary cancellation'
        $current = Read-IiCurrent $root
        Assert-True ($current.active -eq 'new' -and $current.state -eq 'pending' -and $current.attempts -eq 0) 'cancellation preserves version and attempt budget'
        Assert-PathMissing "$root\last-failure.txt" 'cancellation creates no rollback diagnosis'
    }

    foreach ($choice in @(@{ Name = 'safe'; Button = 101 }, @{ Name = 'not-today'; Button = 102 })) {
        $data = "$base\$($choice.Name)"
        New-Item -ItemType Directory -Force $data | Out-Null
        Set-Content "$data\state.ini" "[restore]`nlastSessionTrouble=1"
        $envs.II_TEST_RECOVERY = 1
        $envs.II_FAKE_PRECOMPILE_MS = 300
        Write-IiCurrent $root 'new' 'old' 'pending' 0
        $launcher = Start-IiProcess "$root\ii-launcher.exe" (@('--shell', $shell, '--config', 'window') + $script:InertFlags) $data $envs
        Assert-True (Wait-IiLog $data 'recovery: choices available independently' 10) 'recovery survives removal of the loading cover'
        Assert-True (Wait-IiLog $data 'QML compiled' 10) 'the compiler can finish while recovery waits'
        Assert-True ((Get-IiHostLog $data) -notmatch 'shell: started pid') 'the shell waits for a recovery decision'
        $hostProcess = Get-Process -Id ([int](Get-IiState $data 'hostPid'))
        Assert-Equal (Send-IiMessage $hostProcess.Id 'IiRecoveryChoices' 0x111 $choice.Button) 1 'recovery choice is available in its own native window'
        if ($choice.Name -eq 'safe') {
            Assert-True (Wait-IiLog $data 'shell: started pid' 10) 'safe mode resumes startup'
            Assert-True ((Get-IiHostLog $data) -match 'starts with safe mode') 'the shell inherits the chosen safe mode'
            Send-IiWmClose $hostProcess.Id | Out-Null
            Wait-IiExit $hostProcess 5 | Out-Null
        } else {
            Assert-True ($hostProcess.WaitForExit(5000)) 'not today cancels the pending startup'
            Assert-True ((Get-IiHostLog $data) -notmatch 'shell: started pid') 'not today never starts the shell'
        }
        Assert-Equal (Wait-IiExit $launcher 5) 0 'recovery choice causes no rollback'
        Assert-Equal (Read-IiCurrent $root).active 'new' 'the pending update remains selected'
    }
}
finally {
    if ($hostProcess -and -not $hostProcess.HasExited) { $hostProcess.Kill() }
    if ($launcher -and -not $launcher.HasExited) { $launcher.Kill() }
    Stop-IiStragglers @($shell, "$version\ii-host.exe", "$root\versions\old\ii-host.exe")
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
