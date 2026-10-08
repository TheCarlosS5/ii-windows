# INSIDE the sandbox: ii's settings app shows only ii's own title bar (no Windows caption or
# buttons), its title bar drags the window, and a double click maximizes it.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class W {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    public struct RECT { public int L, T, R, B; }
}
'@
$p = Start-Process "$dist\quickshell.exe" -ArgumentList '-p', "`"$local\settings.qml`"" -PassThru
Start-Sleep 12
$h = [W]::FindWindow([NullString]::Value, 'illogical-impulse Settings')
Check 'settings window open' ($h -ne [IntPtr]::Zero)
$r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
$style = [W]::GetWindowLong($h, -16)
# The real frame stays (shadow, rounded corners, Snap); Quickshell only removes its caption area.
Check 'Windows frame kept' (($style -band 0xC00000) -eq 0xC00000) ('style=0x{0:x}' -f $style)
$client = New-Object W+RECT; [void][W]::GetClientRect($h, [ref]$client)
Check 'no Windows caption: content starts at the top' (($r.B - $r.T) - ($client.B - $client.T) -le 12) "(window $($r.B - $r.T), client $($client.B - $client.T))"
Check 'still resizable' (($style -band 0x40000) -ne 0)
& "$dev\screenshot.ps1" -Out "$out\settings-0.png" | Out-Null
"window at $($r.L),$($r.T) $($r.R - $r.L)x$($r.B - $r.T)"
# Drag by ii's title bar (left part, away from the close button).
$x = $r.L + 300; $y = $r.T + 30
& "$dev\drag.ps1" -X1 $x -Y1 $y -X2 ($x + 150) -Y2 ($y + 80) 2>$null
if (-not $?) { "no drag.ps1" }
Start-Sleep 1
$r2 = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r2)
Check 'title bar drags the window' (($r2.L - $r.L) -gt 100 -and ($r2.T - $r.T) -gt 50) "($($r.L),$($r.T) -> $($r2.L),$($r2.T))"
& "$dev\click.ps1" -X ($r2.L + 300) -Y ($r2.T + 30) -Button Left
Start-Sleep -Milliseconds 80
& "$dev\click.ps1" -X ($r2.L + 300) -Y ($r2.T + 30) -Button Left
Start-Sleep 1
Check 'double click maximizes' ([W]::IsZoomed($h))
& "$dev\screenshot.ps1" -Out "$out\settings-1-max.png" | Out-Null
Stop-Process -Id $p.Id -Force
"fails: $script:fails"
