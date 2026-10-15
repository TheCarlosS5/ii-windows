param([int]$Seconds = 16, [string]$Runtime = "$env:USERPROFILE\dev\ii-dev-runtime")
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$Runtime\quickshell\quickshell.exe"
$psi.Arguments = "-p `"$root\build\ii`""
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
$psi.EnvironmentVariables['PATH'] = "$Runtime\quickshell\bin;" + $psi.EnvironmentVariables['PATH']
$p = [System.Diagnostics.Process]::Start($psi)
$t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
Start-Sleep -Seconds $Seconds
try { $p.Kill() } catch {}
Start-Sleep -Milliseconds 500
foreach ($l in (($out.Result + "`n" + $err.Result) -split "`n")) {
    if ($l -match '\[t\] (.+?) (\d{13})\s*$') { "{0,7} ms  {1}" -f ([int64]$Matches[2] - $t0), $Matches[1] }
    elseif ($l -match 'Configuration Loaded') { "        (Configuration Loaded)" }
}
