# Opens the settings window, visits every page and prints the QML errors/warnings the pages produce
# (a page only loads when it is opened, so the smoke test of the shell does not see them).
#   settings-pages.ps1 [-Runtime <dir>] [-Shots <dir>]
param([string]$Runtime = "$env:USERPROFILE\dev\ii-dev-runtime", [string]$Shots = '')
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$Runtime\quickshell\quickshell.exe"
$psi.Arguments = "-p `"$root\build\ii\settings.qml`""
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
$psi.EnvironmentVariables['PATH'] = "$Runtime\quickshell\bin;" + $psi.EnvironmentVariables['PATH']
$p = [System.Diagnostics.Process]::Start($psi)
$out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
Start-Sleep -Seconds 12
$ys = 342, 398, 454, 510, 566, 622, 678, 734, 790, 846
$names = 'Inicio', 'Apariencia', 'Barra', 'Dock', 'Escritorio', 'Paneles', 'General', 'Servicios', 'Avanzado', 'Acerca'
for ($i = 0; $i -lt $ys.Count; $i++) {
    & "$PSScriptRoot\click.ps1" -X 495 -Y $ys[$i]
    Start-Sleep -Milliseconds 1800
    if ($Shots) { & "$PSScriptRoot\screenshot.ps1" -Out (Join-Path $Shots "page-$($names[$i]).png") -X 410 -Y 120 -W 1100 -H 780 | Out-Null }
}
try { $p.Kill() } catch {}
Start-Sleep -Milliseconds 500
$all = ($out.Result + "`n" + $err.Result) -split "`n"
$bad = $all | Where-Object { $_ -match 'ReferenceError|TypeError|is not defined|Cannot assign|Cannot read|unavailable|Type .* unavailable|non-existent|Binding loop|ERROR' }
"{0} lines, {1} problems" -f $all.Count, @($bad).Count
$bad | Select-Object -Unique | Select-Object -First 30
