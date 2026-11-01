# Plan 2026-10-31, C4/C8: how long Configuración takes to show each page when switching (the window already open),
# first visit and second visit. Opens the window, goes through every page twice with Ctrl+PageDown and prints
# II_SETTINGS_BENCH's times. The window has to get the keys: do not use the PC while it runs (~30 s).
#   settings-switch-bench.ps1 [-Runtime <folder with quickshell.exe>] [-Gap 1.2]
param([string]$Runtime = '', [double]$Gap = 1.2)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Runtime) { $Runtime = "$root\dist\quickshell" }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace IiBench -Name Mouse -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e);'
$settings = Get-Content "$root\build\ii\settings.qml" -Raw
$count = [regex]::Matches($settings, 'component: "modules/settings/[A-Za-z]+\.qml"').Count
$psi = New-Object System.Diagnostics.ProcessStartInfo "$Runtime\quickshell.exe", "-p `"$root\build\ii\settings.qml`""
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
$psi.EnvironmentVariables['II_SETTINGS_BENCH'] = '1'
$psi.EnvironmentVariables['II_SETTINGS_PAGE'] = '0'
$psi.EnvironmentVariables['PATH'] = "$Runtime\bin;" + $psi.EnvironmentVariables['PATH']
$p = [System.Diagnostics.Process]::Start($psi)
$out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
Start-Sleep 5
[IiBench.Mouse]::mouse_event(1, 1, 0, 0, 0); [IiBench.Mouse]::mouse_event(1, -1, 0, 0, 0)
for ($i = 0; $i -lt 2 * $count; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait('^{TAB}')
    Start-Sleep -Milliseconds ([int]($Gap * 1000))
}
try { $p.Kill() } catch {}
$p.WaitForExit(3000) | Out-Null
$lines = @((($out.Result + "`n" + $err.Result) -split "`r?`n") | Where-Object { $_ -match 'settings-bench:' } | ForEach-Object { $_ -replace '^.*settings-bench:\s*', '' })
$times = @{}
$n = 0
foreach ($l in $lines) {
    $m = [regex]::Match($l, '^(\S+) (\d+) ms')
    if (-not $m.Success) { continue }
    $visit = if ($n -lt $count) { 'first' } else { 'second' }
    if ($n -eq 0) { $visit = 'start' }
    "{0,-24} {1,-6} {2,5} ms" -f $m.Groups[1].Value, $visit, $m.Groups[2].Value
    $n++
}
if ($n -lt $count) { Write-Warning "only $n page loads seen (did the window have the keyboard?)" }
