# Plan 2026-10-31, E3: the class timetable. Always: its logic under Node (tests\timetable\test.js). With -EndToEnd:
# tests\timetable\timetable-e2e.qml on the staged tree writes a class that starts in 5 minutes into config.json, shows
# the Hoy tab (screenshot with -Shot <png>) and checks that the reminder reaches the notification server through
# ii-shim notify-send with its Join button (host command class-join). config.json and the saved notification list are
# copied first and put back byte for byte; the timetable state file it leaves is removed.
param([switch]$EndToEnd, [string]$Shot = '', [string]$Quickshell = '')
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Skip-Test 'node not found' }
$text = & $node.Source "$repo\tests\timetable\test.js" 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "timetable_logic.js: $($text.Trim())"
if (-not $EndToEnd) { Complete-IiTest; return }

if (-not $Quickshell) { $Quickshell = "$repo\dist\quickshell\quickshell.exe" }
if (-not (Test-Path $Quickshell)) { Skip-Test 'no dist\quickshell\quickshell.exe (tools\dev\deploy.ps1)' }
if (-not (Test-Path "$repo\build\ii\services\Timetable.qml")) { Skip-Test 'no staged tree (tools\dev\stage-ii.ps1)' }
$files = @((Join-Path $env:LOCALAPPDATA 'quickshell\illogical-impulse\config.json'),
           (Join-Path $env:LOCALAPPDATA 'quickshell\cache\notifications\notifications.json'),
           (Join-Path $env:LOCALAPPDATA 'quickshell\State\timetable.json'))
$base = Join-Path $env:TEMP ('ii-timetable-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $base | Out-Null
$saved = @{}
for ($i = 0; $i -lt $files.Count; $i++) {
    if (Test-Path $files[$i]) { Copy-Item $files[$i] "$base\$i" -Force; $saved[$i] = (Get-FileHash $files[$i]).Hash }
}
$probeQml = "$repo\build\ii\timetable-e2e.qml"
Copy-Item "$repo\tests\timetable\timetable-e2e.qml" $probeQml -Force
$shell = $null
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $Quickshell, "-p `"$probeQml`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.Environment['PATH'] = (Join-Path (Split-Path $Quickshell) 'bin') + ';' + $psi.Environment['PATH']
    $shell = [Diagnostics.Process]::Start($psi)
    $out = $shell.StandardOutput.ReadToEndAsync(); $err = $shell.StandardError.ReadToEndAsync()
    if ($Shot) {
        Start-Sleep -Seconds 12
        & powershell.exe -NoProfile -File "$repo\tools\dev\screenshot.ps1" -Out $Shot | Out-Null
    }
    Assert-True ($shell.WaitForExit(60000)) 'the probe finished'
} finally {
    if ($shell -and -not $shell.HasExited) { $shell.Kill(); $shell.WaitForExit(5000) | Out-Null }
    Remove-Item $probeQml -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt $files.Count; $i++) {
        if ($saved.ContainsKey($i)) { Copy-Item "$base\$i" $files[$i] -Force } else { Remove-Item $files[$i] -Force -ErrorAction SilentlyContinue }
    }
}
foreach ($i in $saved.Keys) { Assert-Equal (Get-FileHash $files[$i]).Hash $saved[$i] "$(Split-Path $files[$i] -Leaf) is exactly as it was" }
$log = ($out.Result + "`n" + $err.Result) -split "`r?`n"
$line = ($log | Where-Object { $_ -match 'TT next=' } | Select-Object -First 1) -replace '^.*TT ', ''
Write-Output $line
Assert-True ($line -match 'next=Programación minutes=[45] ') "the Hoy tab knows the next class: $line"
Assert-True ($line -match 'notice=Programación en [45] min') "the reminder arrived: $line"
Assert-True ($line -match 'host:class-join:Unirme') "with its Join button: $line"
Assert-True (-not ($log -match '(ReferenceError|TypeError).*(Timetable|Today|timetable_logic)')) 'no script errors'
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
Complete-IiTest
