# Starts the shell on the staged QML (no host) and prints every log line with the time since launch, to see
# where start-up goes. It does not hide the taskbar or change settings; it flashes ii's panels for a moment.
#   startup-trace.ps1 [-Seconds 14] [-Runtime <dir>] [-Filter <regex>]
param([int]$Seconds = 14, [string]$Runtime = "$env:USERPROFILE\dev\ii-dev-runtime", [string]$Filter = '')
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$exe = "$Runtime\quickshell\quickshell.exe"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.Arguments = "-p `"$root\build\ii`""
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
$psi.EnvironmentVariables['PATH'] = "$Runtime\quickshell\bin;" + $psi.EnvironmentVariables['PATH']
$lines = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
$global:iiSw = [Diagnostics.Stopwatch]::StartNew()
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$handler = { if ($EventArgs.Data) { $Event.MessageData.Enqueue(("{0,7:N0} ms  {1}" -f $global:iiSw.Elapsed.TotalMilliseconds, $EventArgs.Data)) } }
$e1 = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $lines
$e2 = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $handler -MessageData $lines
[void]$proc.Start(); $proc.BeginOutputReadLine(); $proc.BeginErrorReadLine()
Start-Sleep -Seconds $Seconds
try { $proc.Kill() } catch {}
Start-Sleep -Milliseconds 300
Unregister-Event -SourceIdentifier $e1.Name -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier $e2.Name -ErrorAction SilentlyContinue
$l = $null
while ($lines.TryDequeue([ref]$l)) { if (-not $Filter -or $l -match $Filter) { $l } }
