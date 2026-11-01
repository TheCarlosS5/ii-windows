# Opens Configuración on each page by name (II_SETTINGS_PAGE, plan 2026-10-31 C5) and lists the QML errors and
# warnings each page produces, plus how long the page took to load (II_SETTINGS_BENCH). No clicks on the screen
# (settings-pages.ps1 clicks fixed coordinates). The settings window shows for a few seconds per page.
#   settings-check.ps1 [-Runtime <folder with quickshell.exe>] [-Pages quick,appearance,...] [-Wait 7]
# Exit 1 if any page has an error. Reads the real config; changes nothing.
param([string]$Runtime = '', [string[]]$Pages = @(), [int]$Wait = 7)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Runtime) { $Runtime = "$root\dist\quickshell" }
if (-not (Test-Path "$Runtime\quickshell.exe")) { throw "no quickshell.exe in $Runtime (tools\dev\deploy.ps1)" }
$Pages = @($Pages | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if (-not $Pages.Count) {
    $settings = Get-Content "$root\build\ii\settings.qml" -Raw
    $Pages = [regex]::Matches($settings, 'component: "modules/settings/([A-Za-z]+)\.qml"') | ForEach-Object { $_.Groups[1].Value.ToLower() }
}
$pattern = 'ReferenceError|TypeError|is not defined|Cannot assign|Cannot read|unavailable|non-existent|Binding loop|Unable to assign|is not a type|failed to load|ERROR|WARN scene'
$failures = 0
foreach ($page in $Pages) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo "$Runtime\quickshell.exe", "-p `"$root\build\ii\settings.qml`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.EnvironmentVariables['II_SETTINGS_PAGE'] = $page
    $psi.EnvironmentVariables['II_SETTINGS_BENCH'] = '1'
    $psi.EnvironmentVariables['PATH'] = "$Runtime\bin;" + $psi.EnvironmentVariables['PATH']
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds $Wait
    try { $p.Kill() } catch {}
    $p.WaitForExit(3000) | Out-Null
    $lines = ($out.Result + "`n" + $err.Result) -split "`r?`n"
    $bad = @($lines | Where-Object { $_ -match $pattern } | Select-Object -Unique)
    $bench = $lines | Where-Object { $_ -match 'settings-bench' } | Select-Object -Last 1
    "{0,-18} {1,3} problem(s)  {2}" -f $page, $bad.Count, ($bench -replace '^.*settings-bench:\s*', '')
    $bad | Select-Object -First 12 | ForEach-Object { "    $($_.Trim())" }
    if ($bad.Count) { $failures++ }
}
if ($failures) { exit 1 }
