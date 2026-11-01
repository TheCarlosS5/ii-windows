# Plan 2026-10-31, D1: the window tracker follows windows event by event. Starts quickshell.exe on a config that
# watches the window list (tests\toplevels), opens a probe window that changes its title and moves 50 times a second,
# and checks that the probe appears, its last title arrives, minimizing it is seen and closing it removes it. Prints
# the CPU time quickshell.exe spent while the probe churned (-Compare <exe>: the same with another quickshell.exe,
# e.g. the previous build in dist\quickshell, to see the difference).
#   test-toplevels.ps1 [-Seconds 15] [-Quickshell <exe>] [-Compare <exe>] [-Extra <n>: that many more still windows,
#   like a busy desktop]
# Shows a small window in the top-left corner while it runs.
param([int]$Seconds = 15, [string]$Quickshell = '', [string]$Compare = '', [int]$Extra = 0)
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not $Quickshell) {
    $Quickshell = @("$repo\quickshell\build\quickshell.exe", "$repo\quickshell\build-r\quickshell.exe", "$repo\dist\quickshell\quickshell.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Quickshell) { Skip-Test 'no quickshell.exe (cmake --build quickshell\build)' }
$qtBin = @("$env:QTDIR\bin", "$env:USERPROFILE\dev\Qt\6.12.0-msvc2022_64\bin") | Where-Object { $_ -and (Test-Path "$_\Qt6Core.dll") } | Select-Object -First 1

$probeScript = @'
param([int]$Seconds, [int]$Extra)
Add-Type -AssemblyName System.Windows.Forms
$others = @()
for ($i = 0; $i -lt $Extra; $i++) {
    $o = New-Object System.Windows.Forms.Form
    $o.Text = "ii-toplevels-extra $i"
    $o.StartPosition = 'Manual'
    $o.Location = New-Object System.Drawing.Point((400 + 30 * $i), (20 + 20 * $i))
    $o.Size = New-Object System.Drawing.Size(240, 100)
    $o.Show()
    $others += $o
}
$form = New-Object System.Windows.Forms.Form
$form.Text = 'ii-toplevels-probe start'
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(20, 20)
$form.Size = New-Object System.Drawing.Size(320, 120)
$form.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Seconds 2
Write-Output 'churn-start'
$end = (Get-Date).AddSeconds($Seconds)
$n = 0
while ((Get-Date) -lt $end) {
    $n++
    $form.Text = "ii-toplevels-probe $n"
    $form.Location = New-Object System.Drawing.Point((20 + ($n % 2) * 40), 20)
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 20
}
Write-Output "churn-end $n"
$form.Text = 'ii-toplevels-probe final'
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 1500
$form.WindowState = 'Minimized'
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 1500
# Ask for attention like a chat app does (F17): flash the taskbar button while not in front.
Add-Type -Namespace Probe -Name Flash -MemberDefinition @"
[StructLayout(LayoutKind.Sequential)] public struct FLASHWINFO { public uint cbSize; public System.IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
[DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
"@
$fi = New-Object Probe.Flash+FLASHWINFO
$fi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($fi); $fi.hwnd = $form.Handle; $fi.dwFlags = 3; $fi.uCount = 3
[Probe.Flash]::FlashWindowEx([ref]$fi) | Out-Null
for ($i = 0; $i -lt 15; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
$form.Close()
foreach ($o in $others) { $o.Close() }
Start-Sleep -Milliseconds 1500
Write-Output 'probe-done'
'@

function Invoke-Run([string]$exe) {
    $base = Join-Path $env:TEMP ('ii-toplevels-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $base | Out-Null
    Set-Content -Path "$base\probe.ps1" -Value $probeScript -Encoding UTF8
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe, "-p `"$repo\tests\toplevels`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.Environment['QS_TOPLEVELS_STATS'] = '1'
    $binDir = Join-Path (Split-Path $exe) 'bin'
    $paths = @($binDir, $qtBin) | Where-Object { $_ -and (Test-Path $_) }
    if ($paths) { $psi.Environment['PATH'] = ($paths -join ';') + ';' + $psi.Environment['PATH'] }
    $shell = [Diagnostics.Process]::Start($psi)
    $out = $shell.StandardOutput.ReadToEndAsync(); $err = $shell.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 4
    # No console window, and nothing that would hide the form (-WindowStyle Hidden hides a process' first window).
    $ppsi = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', "/c powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$base\probe.ps1`" $Seconds $Extra > `"$base\probe.txt`""
    $ppsi.UseShellExecute = $false; $ppsi.CreateNoWindow = $true
    $probe = [Diagnostics.Process]::Start($ppsi)
    # CPU while the probe churns (from its "churn-start" to "churn-end").
    $deadline = (Get-Date).AddSeconds(15)
    while (-not ((Get-Content "$base\probe.txt" -Raw -ErrorAction SilentlyContinue) -match 'churn-start') -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    $shell.Refresh(); $cpu0 = $shell.TotalProcessorTime
    $deadline = (Get-Date).AddSeconds($Seconds + 15)
    while (-not ((Get-Content "$base\probe.txt" -Raw -ErrorAction SilentlyContinue) -match 'churn-end') -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    $shell.Refresh(); $cpu1 = $shell.TotalProcessorTime
    $probe.WaitForExit(20000) | Out-Null
    Start-Sleep -Seconds 1
    $alive = -not $shell.HasExited
    try { $shell.Kill() } catch {}
    $shell.WaitForExit(5000) | Out-Null
    $log = ($out.Result + "`n" + $err.Result)
    Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
    [pscustomobject]@{ Alive = $alive; Cpu = ($cpu1 - $cpu0).TotalMilliseconds; Log = $log; Probe = (Get-Content "$base\probe.txt" -Raw -ErrorAction SilentlyContinue) }
}

$run = Invoke-Run $Quickshell
Write-Output ("{0}: {1:N0} ms of CPU during {2} s of title changes and moves" -f $Quickshell, $run.Cpu, $Seconds)
$run.Log -split "`r?`n" | Where-Object { $_ -match 'toplevels|probe |WARN|ERROR' } | Select-Object -Last 12 | ForEach-Object { "  $($_.Trim())" }
Assert-True $run.Alive 'the shell is alive at the end'
Assert-True ($run.Log -match 'probe added') 'the probe window appeared in the list'
Assert-True ($run.Log -match 'probe title=ii-toplevels-probe final') 'its last title arrived'
Assert-True ($run.Log -match 'probe minimized=true') 'minimizing it was seen'
Assert-True ($run.Log -match 'probe urgent=true') 'its asking for attention (taskbar flash) was seen'
$urgentAt = $run.Log.IndexOf('probe urgent=true'); $minimizedAt = $run.Log.IndexOf('probe minimized=true')
Assert-True ($urgentAt -gt $minimizedAt) 'only the flash made it urgent (not the title changes before it)'
Assert-True ($run.Log -match 'probe removed') 'closing it removed it'
if ($Compare) {
    $other = Invoke-Run $Compare
    Write-Output ("{0}: {1:N0} ms of CPU (compare)" -f $Compare, $other.Cpu)
    if ($other.Cpu -gt 0) { Write-Output ("this build uses {0:N0} % of the other's CPU" -f (100 * $run.Cpu / $other.Cpu)) }
}
Complete-IiTest
