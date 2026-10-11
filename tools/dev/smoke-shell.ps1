# Starts the real shell on the real ii QML and reports whether the configuration loads, then stops it.
#   smoke-shell.ps1 [-Quickshell <exe>] [-Config <ii dir>] [-TimeoutSec 60]
# Default: dist\quickshell\quickshell.exe on build\ii (what make-package packages).
# It creates the shell's panels for a moment, so run it when you do not mind them flashing (it does
# not hide the taskbar, change settings or touch the ii that is installed). Exit 0 = "Configuration
# Loaded", 1 = the load failed (the reason is printed), 2 = timeout/crash.
param([string]$Quickshell = '', [string]$Config = '', [int]$TimeoutSec = 60, [switch]$ShowLog)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Quickshell) { $Quickshell = "$root\dist\quickshell\quickshell.exe" }
if (-not $Config) { $Config = "$root\build\ii" }
$bin = Join-Path (Split-Path $Quickshell) 'bin'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Quickshell
$psi.Arguments = "-p `"$Config`""
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
$psi.EnvironmentVariables['PATH'] = "$bin;" + $psi.EnvironmentVariables['PATH']
$lines = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$handler = { if ($EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } }
$e1 = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $lines
$e2 = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $handler -MessageData $lines
[void]$proc.Start(); $proc.BeginOutputReadLine(); $proc.BeginErrorReadLine()
$all = ''
$result = 2
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $l = $null
        while ($lines.TryDequeue([ref]$l)) { $all += $l + "`n" }
        if ($all -match 'Configuration Loaded') { $result = 0; break }
        if ($all -match 'Failed to load configuration') { Start-Sleep -Milliseconds 300; $result = 1; break }
        if ($proc.HasExited) { Start-Sleep -Milliseconds 300; $result = if ($all -match 'Configuration Loaded') { 0 } else { 2 }; break }
        Start-Sleep -Milliseconds 100
    }
    $l = $null
    while ($lines.TryDequeue([ref]$l)) { $all += $l + "`n" }
}
finally {
    if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
    Unregister-Event -SourceIdentifier $e1.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $e2.Name -ErrorAction SilentlyContinue
    if ($all -match 'cache/by-shell/([0-9a-f]{32})/') { $cacheId = $Matches[1] }
}
if ($ShowLog) { ($all -split "`n" | Select-Object -Last 25) -join "`n" }
if ($result -eq 0) { "shell configuration loaded in $([int]$sw.Elapsed.TotalSeconds) s" }
elseif ($result -eq 1) { ($all -split "`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -First 12) -join "`n" }
else { "no 'Configuration Loaded' (exited: $($proc.HasExited), exit code $(if ($proc.HasExited) { $proc.ExitCode } else { "-" })); last lines:`n" + (($all -split "`n" | Select-Object -Last 8) -join "`n") }
exit $result
