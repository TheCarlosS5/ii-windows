# Plan 2026-10-31, D2: the desktop knows at once when an app covers it, and its clock stops meanwhile.
# Runs quickshell.exe on tests\desktop-cover\desktop-cover-probe.qml (copied into the staged build\ii so it can use ii's
# services), maximizes a probe window, then minimizes it, and checks: covered (and the desktop clock stopped) within
# half a second of maximizing, uncovered (clock running, on time) within half a second of minimizing.
# Needs a staged tree (tools\dev\stage-ii.ps1) and dist\quickshell. Shows a window for a few seconds.
param([string]$Quickshell = '')
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not $Quickshell) { $Quickshell = "$repo\dist\quickshell\quickshell.exe" }
if (-not (Test-Path $Quickshell)) { Skip-Test 'no dist\quickshell\quickshell.exe (tools\dev\deploy.ps1)' }
if (-not (Test-Path "$repo\build\ii\services\DesktopTime.qml")) { Skip-Test 'no staged tree (tools\dev\stage-ii.ps1)' }

$probeQml = "$repo\build\ii\desktop-cover-probe.qml"
Copy-Item "$repo\tests\desktop-cover\desktop-cover-probe.qml" $probeQml -Force
$base = Join-Path $env:TEMP ('ii-desktop-cover-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $base | Out-Null
$probeScript = @'
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = 'ii-desktop-cover-probe'
$form.WindowState = 'Normal'
$form.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Seconds 2
Write-Output ("maximize " + [DateTimeOffset]::Now.ToUnixTimeMilliseconds())
$form.WindowState = 'Maximized'
for ($i = 0; $i -lt 40; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
Write-Output ("minimize " + [DateTimeOffset]::Now.ToUnixTimeMilliseconds())
$form.WindowState = 'Minimized'
for ($i = 0; $i -lt 40; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
$form.Close()
Write-Output 'done'
'@
Set-Content "$base\probe.ps1" $probeScript -Encoding UTF8
$shell = $null
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $Quickshell, "-p `"$probeQml`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.Environment['PATH'] = (Join-Path (Split-Path $Quickshell) 'bin') + ';' + $psi.Environment['PATH']
    $shell = [Diagnostics.Process]::Start($psi)
    $out = $shell.StandardOutput.ReadToEndAsync(); $err = $shell.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 4
    $ppsi = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', "/c powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$base\probe.ps1`" > `"$base\probe.txt`""
    $ppsi.UseShellExecute = $false; $ppsi.CreateNoWindow = $true
    $probe = [Diagnostics.Process]::Start($ppsi)
    $probe.WaitForExit(30000) | Out-Null
    Start-Sleep -Milliseconds 500
    Assert-True (-not $shell.HasExited) 'the probe shell is alive'
} finally {
    if ($shell -and -not $shell.HasExited) { $shell.Kill(); $shell.WaitForExit(5000) | Out-Null }
    Remove-Item $probeQml -Force -ErrorAction SilentlyContinue
}
$log = ($out.Result + "`n" + $err.Result) -split "`r?`n"
if ($env:II_TEST_VERBOSE) { $log | Where-Object { $_ -match 'cover|WARN|ERROR|error' } | Select-Object -First 60 | ForEach-Object { Write-Output "  $_" }; Get-Content "$base\probe.txt" }
$probeOut = Get-Content "$base\probe.txt" -Raw
$tMax = [int64]([regex]::Match($probeOut, 'maximize (\d+)').Groups[1].Value)
$tMin = [int64]([regex]::Match($probeOut, 'minimize (\d+)').Groups[1].Value)
$rows = foreach ($l in $log) {
    $m = [regex]::Match($l, 'cover covered=(.*?) all=(\w+) clock=(\w+) ticks=(\d+) t=(\d+)')
    if ($m.Success) { [pscustomobject]@{ All = $m.Groups[2].Value -eq 'true'; Clock = $m.Groups[3].Value -eq 'true'; Ticks = [int]$m.Groups[4].Value; T = [int64]$m.Groups[5].Value } }
}
Assert-True ($rows.Count -gt 10) "the probe logged ($($rows.Count) lines)"
$before = $rows | Where-Object { $_.T -lt $tMax } | Select-Object -Last 1
if ($before.All) { Skip-Test 'the desktop was already covered before the probe (a maximized window?)' }
$covered = $rows | Where-Object { $_.T -ge $tMax -and $_.All } | Select-Object -First 1
Assert-True ($null -ne $covered) 'maximizing the probe covers the desktop'
Write-Output ("covered {0} ms after maximizing" -f ($covered.T - $tMax))
Assert-True (($covered.T - $tMax) -lt 800) 'covered within 0.8 s (event, no 1 s timer)'
Assert-True (-not $covered.Clock) 'the desktop clock stops while covered'
$during = $rows | Where-Object { $_.T -ge ($covered.T + 300) -and $_.T -lt $tMin }
$tickSpan = ($during | Measure-Object Ticks -Maximum -Minimum)
Write-Output ("clock ticks while covered: {0}" -f ($tickSpan.Maximum - $tickSpan.Minimum))
Assert-True (($tickSpan.Maximum - $tickSpan.Minimum) -le 0) 'no clock tick while covered'
$uncovered = $rows | Where-Object { $_.T -ge $tMin -and -not $_.All } | Select-Object -First 1
Assert-True ($null -ne $uncovered) 'minimizing it uncovers the desktop'
Write-Output ("uncovered {0} ms after minimizing" -f ($uncovered.T - $tMin))
Assert-True (($uncovered.T - $tMin) -lt 800) 'uncovered within 0.8 s'
Assert-True $uncovered.Clock 'the desktop clock runs again'
$after = $rows | Where-Object { $_.T -ge ($uncovered.T + 1500) } | Select-Object -Last 1
Assert-True ($after.Ticks -gt $uncovered.Ticks) 'and ticks'
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
Complete-IiTest
