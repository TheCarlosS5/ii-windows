# Plan 2026-10-31, A1/A8: the shell's media backend (MPRIS on Windows' GSMTC) must survive sessions that appear and
# vanish as fast as a browser feed makes them (the 0.6.0 crash: quickshell.exe+0x19ed74, mpris.cpp GetPlaybackInfo()
# returning null). Starts the real quickshell.exe on a config that reads every player property
# (tests\media\mpris-watch), runs ii-media-churn.exe (silent media sessions, 3 at once, 40-400 ms each) and checks:
# the shell is still alive, no crash report was written, players were seen and are all gone at the end.
#   test-mpris-stress.ps1 [-Seconds 90]
# Needs: cmake --build quickshell\build (quickshell.exe and ii-media-churn.exe). Nothing audible is played.
param([int]$Seconds = 90)
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$build = @("$repo\quickshell\build", "$repo\quickshell\build-r") | Where-Object { Test-Path "$_\ii-media-churn.exe" } | Select-Object -First 1
if (-not $build) { Skip-Test 'ii-media-churn.exe not built (cmake --build quickshell\build)' }
$qtBin = @("$env:QTDIR\bin", "$env:USERPROFILE\dev\Qt\6.12.0-msvc2022_64\bin") | Where-Object { $_ -and (Test-Path "$_\Qt6Core.dll") } | Select-Object -First 1
if (-not $qtBin -and -not (Test-Path "$build\Qt6Core.dll")) { Skip-Test 'Qt runtime not found (QTDIR)' }

$base = Join-Path $env:TEMP ('ii-mpris-stress-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$data = Join-Path $base 'data'
New-Item -ItemType Directory -Force $data | Out-Null
$shell = $null
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo "$build\quickshell.exe", "-p `"$repo\tests\media\mpris-watch`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['II_DATA_DIR'] = $data
    if ($qtBin) { $psi.Environment['PATH'] = "$qtBin;" + $psi.Environment['PATH'] }
    $shell = [Diagnostics.Process]::Start($psi)
    $out = $shell.StandardOutput.ReadToEndAsync()
    $err = $shell.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 3
    Assert-True (-not $shell.HasExited) 'the watcher shell starts'

    $churn = Start-Process "$build\ii-media-churn.exe" -ArgumentList '--seconds', $Seconds, '--parallel', 3 -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $base 'churn.txt') -RedirectStandardError (Join-Path $base 'churn-err.txt')
    $deadline = (Get-Date).AddSeconds($Seconds + 60)
    while (-not $churn.HasExited -and -not $shell.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    if (-not $churn.HasExited) { Stop-Process -Id $churn.Id -Force -ErrorAction SilentlyContinue }
    $churnText = Get-Content (Join-Path $base 'churn.txt') -Raw -ErrorAction SilentlyContinue
    Write-Output "churn: $churnText"
    Start-Sleep -Seconds 6 # the last sessions close, the backend notices

    $alive = -not $shell.HasExited
    if (-not $alive) { Write-Output ('shell exit code 0x{0:X8}' -f $shell.ExitCode) }
    Assert-True $alive "the shell survives $Seconds s of media session churn"
    $crashes = @(Get-ChildItem (Join-Path $data 'crashes') -Filter *.json -ErrorAction SilentlyContinue)
    foreach ($c in $crashes) { Write-Output (Get-Content $c.FullName -Raw) }
    Assert-Equal $crashes.Count 0 'no crash report was written'
    $created = if ($churnText -match 'created (\d+) sessions') { [int]$matches[1] } else { 0 }
    Assert-True ($created -ge $Seconds) "the churn made sessions ($created)"
    if ($alive) { Stop-Process -Id $shell.Id -Force; $shell.WaitForExit(5000) | Out-Null }
    $log = $out.Result + $err.Result
    $lines = @([regex]::Matches($log, 'mpris-watch players=(\d+) max=(\d+) titles=(\d+)'))
    Assert-True ($lines.Count -gt 0) 'the watcher reported'
    if ($lines.Count -gt 0) {
        $last = $lines[$lines.Count - 1]
        Write-Output "watcher: $($last.Value)"
        Assert-True ([int]$last.Groups[2].Value -ge 1) 'players were seen'
        Assert-True ([int]$last.Groups[3].Value -ge 10) 'track titles were read'
        Assert-Equal ([int]$last.Groups[1].Value) 0 'every churned player is gone at the end'
    }
} finally {
    if ($shell -and -not $shell.HasExited) { Stop-Process -Id $shell.Id -Force -ErrorAction SilentlyContinue }
    Get-Process ii-media-churn -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$build*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
