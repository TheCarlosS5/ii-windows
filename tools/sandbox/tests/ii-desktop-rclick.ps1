# INSIDE the sandbox: what does a right click on empty desktop show while ii runs under ii-host?
param([int]$X = 760, [int]$Y = 420)
$out = 'C:\xchg\outbox'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
Add-Type -Namespace RC -Name W -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
[DllImport("user32.dll")] public static extern System.IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern int GetWindowLongW(System.IntPtr h, int i);
'@
$pt = New-Object RC.W+POINT; $pt.x = $X; $pt.y = $Y
$h = [RC.W]::WindowFromPoint($pt); $c = New-Object Text.StringBuilder 200; [void][RC.W]::GetClassNameW($h, $c, 200)
$procId = 0; [void][RC.W]::GetWindowThreadProcessId($h, [ref]$procId)
"window under ($X,$Y): $h class=$c process=$((Get-Process -Id $procId).ProcessName) exstyle=$('{0:X}' -f [RC.W]::GetWindowLongW($h, -20))"
& C:\ii\tools\dev\click.ps1 -X $X -Y $Y -Button Right
Start-Sleep 2
& C:\ii\tools\dev\screenshot.ps1 -Out "$out\rclick.png" | Out-Null
"done"
