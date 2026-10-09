# INSIDE the sandbox: a Win key-up that ii-host never sees must not turn later typing into Win
# shortcuts (bug fixed in 0.1.1: typing "n" or "a" opened the sidebars).
# The lost key-up is simulated with ii-host's own input tag, which its hook skips.
param([string]$Zip = '')
$ErrorActionPreference = 'Continue'
$out = 'C:\xchg\outbox'
if (-not $Zip) { $Zip = (Get-ChildItem C:\ii\out\ii-windows-*.zip | Sort-Object LastWriteTime | Select-Object -Last 1).FullName }
"package: $Zip"

$work = "$env:TEMP\ii-stalewin-$(Get-Random)"
Expand-Archive $Zip $work
$pkg = (Get-ChildItem $work -Directory | Select-Object -First 1).FullName
& powershell -NoProfile -ExecutionPolicy Bypass -File "$pkg\install.ps1" -Yes -NoAutostart -NoFastfetch -StartNow *> "$out\stalewin-install.txt"
Start-Sleep 25
"ii running: $([bool](Get-Process quickshell -ErrorAction SilentlyContinue))"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class SW {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
  [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Key(ushort vk, bool up, long extra) {
    var a = new IN[1]; a[0].type = 1; a[0].ki.vk = vk; a[0].ki.scan = (ushort)MapVirtualKey(vk, 0);
    a[0].ki.flags = (up ? 2u : 0u) | (vk == 0x5B ? 1u : 0u); a[0].ki.extra = (IntPtr)extra;
    SendInput(1, a, Marshal.SizeOf(typeof(IN)));
  }
}
'@
$form = New-Object Windows.Forms.Form -Property @{ Text = 'stale win test'; Width = 500; Height = 160; TopMost = $true }
$box = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Multiline = $true; Font = (New-Object Drawing.Font 'Segoe UI', 18) }
$form.Controls.Add($box)
$form.Show()
function Pump($ms) { $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.ElapsedMilliseconds -lt $ms) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 15 } }
Pump 500
[SW]::SetForegroundWindow($form.Handle) | Out-Null; $box.Focus() | Out-Null; Pump 500

# Win down (seen by ii-host), Win up tagged as ii-host's own input (skipped by its hook)
[SW]::Key(0x5B, $false, 0); Pump 80
[SW]::Key(0x5B, $true, 0x11A1D00D); Pump 400
# Windows may have opened Start for the lone Win press: close it and refocus the box
[SW]::Key(0x1B, $false, 0); [SW]::Key(0x1B, $true, 0); Pump 600
[SW]::SetForegroundWindow($form.Handle) | Out-Null; $box.Focus() | Out-Null; Pump 400
foreach ($vk in 0x4E, 0x4F, 0x54, 0x41) { [SW]::Key($vk, $false, 0); Pump 40; [SW]::Key($vk, $true, 0); Pump 120 }   # n o t a
Pump 1200
& C:\ii\tools\dev\screenshot.ps1 -Out "$out\stalewin.png" | Out-Null
$typed = $box.Text
$form.Close()
"typed: '$typed'"
if ($typed -eq 'nota') { 'PASS typing reaches the app after a lost Win key-up' } else { 'FAIL typing was swallowed as Win shortcuts' }

& powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ii-windows\uninstall.ps1" -Yes *> "$out\stalewin-uninstall.txt"
Start-Sleep 15
