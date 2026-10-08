# INSIDE the sandbox: a middle click moves a tray icon between ii's overflow menu (the arrow) and
# the bar, and the choice is kept (tray.shownItems / hiddenItems); a double click reaches the
# app as a double click.
#   -Clicks "x,y[,Button];..."  clicks after opening, each followed by a capture
param([string]$Clicks = '')
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$out\tray-clicks.txt" -ErrorAction SilentlyContinue
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep 14
$app = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\tray-app.ps1', '-Seconds', '80', '-Name', 'prueba' -PassThru -WindowStyle Hidden
Start-Sleep 6
& "$dev\screenshot.ps1" -Out "$out\tp-0-bar.png" -X 1000 -W 520 -H 200 | Out-Null
$n = 1
foreach ($c in ($Clicks.Split(';') | Where-Object { $_ })) {
    $xy = $c.Split(',')
    if ($xy[2] -eq 'Double') {
        & "$dev\click.ps1" -X ([int]$xy[0]) -Y ([int]$xy[1]) -Button Left
        & "$dev\click.ps1" -X ([int]$xy[0]) -Y ([int]$xy[1]) -Button Left
    } else {
        & "$dev\click.ps1" -X ([int]$xy[0]) -Y ([int]$xy[1]) -Button ($(if ($xy.Count -gt 2) { $xy[2] } else { 'Left' }))
    }
    Start-Sleep 2
    & "$dev\screenshot.ps1" -Out "$out\tp-$n.png" -X 1000 -W 520 -H 200 | Out-Null
    $n++
}
"--- clicks the app received"
Get-Content "$out\tray-clicks.txt" -ErrorAction SilentlyContinue
"--- config"
(Get-Content "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -Raw | ConvertFrom-Json).tray | ConvertTo-Json -Compress
$app | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-Process -Id $p.Id -Force
