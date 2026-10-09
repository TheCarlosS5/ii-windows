# INSIDE the sandbox: Win+Shift+C (through ii-host) opens the color picker over the screen; a
# click copies that pixel's #RRGGBB; Esc cancels. Also the translator through ii's bash path.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KP {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static void Chord(params ushort[] keys) {
        var a = new IN[keys.Length * 2];
        for (int i = 0; i < keys.Length; i++) foreach (var up in new[] { false, true }) {
            int idx = up ? keys.Length * 2 - 1 - i : i;
            a[idx].type = 1; a[idx].ki.vk = keys[i]; a[idx].ki.scan = (ushort)MapVirtualKey(keys[i], 0);
            a[idx].ki.flags = (up ? 2u : 0u) | (keys[i] == 0x5B ? 1u : 0u);
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
}
'@
[void][KP]::SetProcessDPIAware()
function PixelAt($x, $y) {
    $b = New-Object System.Drawing.Bitmap 1, 1
    $g = [System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size 1, 1)); $g.Dispose()
    $c = $b.GetPixel(0, 0); $b.Dispose(); return ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
}

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 28
$x = 300; $y = 500
$expected = PixelAt $x $y
Set-Clipboard -Value 'nothing'
[KP]::Chord(0x5B, 0x10, 0x43)   # Win+Shift+C
Start-Sleep 2
Check 'picker opened' ([bool](Get-Process hyprpicker -ErrorAction SilentlyContinue))
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ($x + 3), ($y + 3)
Start-Sleep -Milliseconds 400
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $x, $y
Start-Sleep -Milliseconds 600
& "$dev\screenshot.ps1" -Out "$out\picker-1.png" | Out-Null
& "$dev\click.ps1" -X $x -Y $y -Button Left
Start-Sleep 1
$got = (Get-Clipboard) -join ''
Check 'click copies that pixel''s color' ($got -ieq $expected) "(got $got, screen $expected)"
Check 'picker closed after picking' (-not (Get-Process hyprpicker -ErrorAction SilentlyContinue))
# Esc cancels
[KP]::Chord(0x5B, 0x10, 0x43)
Start-Sleep 2
[KP]::Chord(0x1B)
Start-Sleep 1
Check 'Esc cancels' (-not (Get-Process hyprpicker -ErrorAction SilentlyContinue))

$t = & "$dist\bin\bash.exe" -c 'trans -brief :es "good night"'
Check 'translator (ii''s bash path) answers' ($LASTEXITCODE -eq 0 -and $t) "($t)"
& "$hostDir\ii-host.exe" --rescue
"fails: $script:fails"
