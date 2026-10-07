Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
if ($env:II_LOOP) { $env:QSG_RENDER_LOOP = $env:II_LOOP }
$env:QSG_INFO = '1'
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16
& C:\ii\tools\dev\send-shortcut.ps1 -Name overviewWorkspacesToggle
foreach ($t in 1..4) { Start-Sleep -Milliseconds 700; & C:\ii\tools\dev\screenshot.ps1 -Out "C:\xchg\outbox\anim-$t.png" -H 420 | Out-Null }
# move the mouse over the overview: if frames only render on input, this changes things
Add-Type -Namespace M -Name C -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);'
[M.C]::SetCursorPos(760, 40) | Out-Null; Start-Sleep -Milliseconds 300; [M.C]::SetCursorPos(780, 60) | Out-Null; Start-Sleep 1
& C:\ii\tools\dev\screenshot.ps1 -Out "C:\xchg\outbox\anim-5-mouse.png" -H 420 | Out-Null
Stop-Process -Id $p.Id -Force
'done'
