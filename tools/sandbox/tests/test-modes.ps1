# Plan 2026-10-31, E2: modes. Always: their decisions under Node (tests\modes\test.js: hours across midnight, an app
# over the hours, by hand over everything, off by hand until the reason ends, only what is unchanged goes back).
# With -EndToEnd: the service on the staged tree with a test mode that turns on No molestar while a powershell.exe
# window is open (tests\modes\modes-e2e.qml). It writes the test mode into the real config.json (Quickshell has no
# other place for it), so config.json is copied first and put back byte for byte afterwards, and the modes state
# file it leaves is removed. Shows a small window for a few seconds.
param([switch]$EndToEnd, [string]$Quickshell = '')
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Skip-Test 'node not found' }
$text = & $node.Source "$repo\tests\modes\test.js" 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "modes_logic.js: $($text.Trim())"
if (-not $EndToEnd) { Complete-IiTest; return }

if (-not $Quickshell) { $Quickshell = "$repo\dist\quickshell\quickshell.exe" }
if (-not (Test-Path $Quickshell)) { Skip-Test 'no dist\quickshell\quickshell.exe (tools\dev\deploy.ps1)' }
if (-not (Test-Path "$repo\build\ii\services\Modes.qml")) { Skip-Test 'no staged tree (tools\dev\stage-ii.ps1)' }
$cfg = Join-Path $env:LOCALAPPDATA 'quickshell\illogical-impulse\config.json'
$state = Join-Path $env:LOCALAPPDATA 'quickshell\State\modes.json'
$base = Join-Path $env:TEMP ('ii-modes-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $base | Out-Null
$hadCfg = Test-Path $cfg
if ($hadCfg) { Copy-Item $cfg "$base\config.json" -Force; $hash = (Get-FileHash $cfg).Hash }
$hadState = Test-Path $state
if ($hadState) { Copy-Item $state "$base\modes.json" -Force }
Set-Content "$base\window.ps1" 'Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.Form; $f.Text = "ii-e2-probe"; $f.Show(); for ($i=0; $i -lt 80; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }; $f.Close()'
$probeQml = "$repo\build\ii\modes-e2e.qml"
Copy-Item "$repo\tests\modes\modes-e2e.qml" $probeQml -Force
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
    # The window through cmd with no console: powershell -WindowStyle Hidden would hide the form too.
    $wpsi = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', "/c powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$base\window.ps1`""
    $wpsi.UseShellExecute = $false; $wpsi.CreateNoWindow = $true
    [Diagnostics.Process]::Start($wpsi) | Out-Null
    Assert-True ($shell.WaitForExit(45000)) 'the probe went through every step'
} finally {
    if ($shell -and -not $shell.HasExited) { $shell.Kill(); $shell.WaitForExit(5000) | Out-Null }
    Remove-Item $probeQml -Force -ErrorAction SilentlyContinue
    if ($hadCfg) { Copy-Item "$base\config.json" $cfg -Force } else { Remove-Item $cfg -Force -ErrorAction SilentlyContinue }
    if ($hadState) { Copy-Item "$base\modes.json" $state -Force } else { Remove-Item $state -Force -ErrorAction SilentlyContinue }
}
if ($hadCfg) { Assert-Equal (Get-FileHash $cfg).Hash $hash 'config.json is exactly as it was' }
$log = ($out.Result + "`n" + $err.Result) -split "`r?`n"
function Step([string]$name) { ($log | Where-Object { $_ -match "E2E $name " } | Select-Object -First 1) -replace '^.*E2E ', '' }
Assert-True ((Step 'start') -match "silent=false active=''") "at first nothing: $(Step 'start')"
Assert-True ((Step 'open') -match "silent=true active='prueba' reason=app detail=powershell") "its app opens: on, with No molestar: $(Step 'open')"
Assert-True ((Step 'dismissed') -match "silent=false active=''") "off by hand: No molestar back as it was: $(Step 'dismissed')"
Assert-True ((Step 'manual') -match "silent=true active='prueba' reason=manual") "on by hand: $(Step 'manual')"
Assert-True ((Step 'manualoff') -match "silent=false active=''") "off by hand with its app still open: stays off: $(Step 'manualoff')"
Assert-True ((Step 'closed') -match "silent=false active=''") "its app closed: off: $(Step 'closed')"
Assert-True (-not ($log -match '(ReferenceError|TypeError).*(Modes|modes_logic)')) 'no script errors in the modes'
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
Complete-IiTest
