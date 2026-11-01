# Plan 2026-10-31, E1: "Buscar todo". The logic (search_plus.js) under Node, then the launcher itself on the staged tree:
# tests\search-plus\launcher-probe.qml (copied into build\ii) types queries and prints the first rows, and the first row
# must be the right one: a command, a Windows setting, an ii setting, a conversion, the time in Tokyo, an open window
# (a probe window this test shows for a few seconds). Nothing here needs the network (no currency).
# Needs node, a staged tree (tools\dev\stage-ii.ps1) and dist\quickshell (tools\dev\deploy.ps1).
param([string]$Quickshell = '')
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $text = & $node.Source "$repo\tests\search-plus\test.js" 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "search_plus.js: $($text.Trim())"
} else { Write-Output 'node not found: the logic checks were not run' }

if (-not $Quickshell) { $Quickshell = "$repo\dist\quickshell\quickshell.exe" }
if (-not (Test-Path $Quickshell)) { Skip-Test 'no dist\quickshell\quickshell.exe (tools\dev\deploy.ps1)' }
if (-not (Test-Path "$repo\build\ii\services\SearchPlus.qml")) { Skip-Test 'no staged tree (tools\dev\stage-ii.ps1)' }

$title = 'ii-e1-ventana-de-prueba'
$expect = [ordered]@{
    'bloquear'                 = '^\[(Acción rápida|Quick action)\] (Bloquear el equipo|Lock the PC)$'
    'bluetooth'                = '^\[(Ajustes de Windows|Windows settings)\] Bluetooth'
    'audifonos'                = '^\[(Ajustes de Windows|Windows settings)\] Bluetooth'
    'segundero'                = '^\[(Ajuste de ii|ii setting) · .*\] (Segundero|Second hand)$'
    '5 km a millas'            = '^\[(Conversión|Conversion)\] 5 km = 3[,.]11 mi$'
    '15% de 230'               = '^\[(Porcentaje|Percentage)\] 15 % (de|of) 230 = 34[,.]50?$'
    '20 c a f'                 = '^\[(Conversión|Conversion)\] 20 °C = 68 °F$'
    'hora en tokio'            = '^\[(Hora|Time) · .*\] Tokio: \d\d:\d\d'
    'no molestar 1'            = '^\[(Acción rápida|Quick action)\] .*1 (hora|hour)$'
    'ventana-de-prueba'        = "^\[(Ventana abierta|Open window).*\] $title$"
}

$probeQml = "$repo\build\ii\launcher-probe.qml"
Copy-Item "$repo\tests\search-plus\launcher-probe.qml" $probeQml -Force
$base = Join-Path $env:TEMP ('ii-search-plus-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $base | Out-Null
# A window to find: shown while the probe types (the probe asks for it last).
Set-Content "$base\window.ps1" @"
Add-Type -AssemblyName System.Windows.Forms
`$form = New-Object System.Windows.Forms.Form
`$form.Text = '$title'
`$form.Show()
for (`$i = 0; `$i -lt 300; `$i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
`$form.Close()
"@ -Encoding UTF8
$shell = $null; $window = $null
try {
    $wpsi = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', "/c powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$base\window.ps1`""
    $wpsi.UseShellExecute = $false; $wpsi.CreateNoWindow = $true
    $window = [Diagnostics.Process]::Start($wpsi)
    Start-Sleep -Seconds 3
    $psi = New-Object System.Diagnostics.ProcessStartInfo $Quickshell, "-p `"$probeQml`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.Environment['PATH'] = (Join-Path (Split-Path $Quickshell) 'bin') + ';' + $psi.Environment['PATH']
    $psi.Environment['E1_QUERIES'] = ($expect.Keys -join '|')
    $shell = [Diagnostics.Process]::Start($psi)
    $out = $shell.StandardOutput.ReadToEndAsync(); $err = $shell.StandardError.ReadToEndAsync()
    Assert-True ($shell.WaitForExit(60000)) 'the probe went through every query'
} finally {
    if ($shell -and -not $shell.HasExited) { $shell.Kill(); $shell.WaitForExit(5000) | Out-Null }
    if ($window -and -not $window.HasExited) { & taskkill /T /F /PID $window.Id 2>&1 | Out-Null }
    Remove-Item $probeQml -Force -ErrorAction SilentlyContinue
}
$log = ($out.Result + "`n" + $err.Result) -split "`r?`n"
Assert-True (-not ($log -match 'Binding loop detected for property "results"')) 'no binding loop in the launcher results'
Assert-True (-not ($log -match '(ReferenceError|TypeError).*(SearchPlus|search_plus|LauncherSearch)')) 'no script errors in the search'
foreach ($q in $expect.Keys) {
    $line = $log | Where-Object { $_ -match "E1PROBE $([regex]::Escape($q)) => " } | Select-Object -First 1
    $first = if ($line) { (($line -split ' => ', 2)[1] -split ' \| ')[0].Trim() } else { '(no line)' }
    Assert-True ($first -match $expect[$q]) "'$q' → first row: $first"
}
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
Complete-IiTest
