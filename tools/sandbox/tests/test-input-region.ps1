# A panel whose mask item is moved by a TRANSFORM (the slide-in of the sidebars) must accept clicks where
# it ends up. The fork once computed the input region only from the item's own geometry: a Translate that
# starts outside the window left the region outside it for good, the whole panel stayed click-through,
# and a click inside the left sidebar fell through to the window below - which closed the sidebar.
# Starts the real quickshell on a tiny config with one 300x200 panel at the bottom-left corner (visible for
# about 6 seconds) and checks, through Windows' own hit testing, that a point inside the moved item belongs
# to the panel and a point outside it does not. Needs dist\quickshell (tools\dev\deploy.ps1).
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$exe = Join-Path $repo 'dist\quickshell\quickshell.exe'
if (-not (Test-Path $exe)) { Skip-Test 'dist\quickshell\quickshell.exe is not deployed (tools\dev\deploy.ps1)' }

Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Text; using System.Runtime.InteropServices;
public static class RegionProbe {
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(PT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  public static void Init() { SetProcessDPIAware(); }
  // The visible 300x200-logical window of this process (any DPI): the tallest window narrower than 800 px.
  public static IntPtr FindPanel(uint pid, out RECT rect) {
    IntPtr found = IntPtr.Zero; RECT best = new RECT();
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != pid || !IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      int w = r.R - r.L, hh = r.B - r.T;
      if (w > 100 && w < 800 && hh > 100 && hh < 600) { found = h; best = r; }
      return true;
    }, IntPtr.Zero);
    rect = best; return found;
  }
  public static IntPtr RootAt(int x, int y) { PT p; p.X = x; p.Y = y; return GetAncestor(WindowFromPoint(p), 2); }
  public static void MoveTo(int x, int y) { SetCursorPos(x, y); }
  public static bool Transparent(IntPtr h) { return (GetWindowLong(h, -20) & 0x20) != 0; }
}
'@
[RegionProbe]::Init()

$base = Join-Path $env:TEMP ('ii-region-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$cfg = Join-Path $base 'cfg'
New-Item -ItemType Directory -Force $cfg | Out-Null
$proc = $null
$cacheId = $null
try {
    Set-Content (Join-Path $cfg 'shell.qml') @'
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: win
        implicitWidth: 300
        implicitHeight: 200
        anchors { left: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ii-region-test"
        color: "transparent"
        mask: Region { item: box }
        Rectangle {
            id: box
            x: 10; y: 10
            width: 100; height: 100
            color: "#aa3366"
            // the same construction as the sidebars' slide-in: the item starts outside the window
            transform: Translate { id: slide; x: -400 }
            SequentialAnimation {
                running: true
                PauseAnimation { duration: 600 }
                NumberAnimation { target: slide; property: "x"; to: 0; duration: 500 }
            }
        }
    }
}
'@
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "-p `"$cfg`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
    $log = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $handler = { if ($EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } }
    $e1 = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $log
    $e2 = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $handler -MessageData $log
    [void]$proc.Start(); $proc.BeginOutputReadLine(); $proc.BeginErrorReadLine()

    $panel = [IntPtr]::Zero; $rect = New-Object RegionProbe+RECT
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 40 -and $panel -eq [IntPtr]::Zero) {
        $panel = [RegionProbe]::FindPanel([uint32]$proc.Id, [ref]$rect)
        Start-Sleep -Milliseconds 200
    }
    Assert-True ($panel -ne [IntPtr]::Zero) 'the test panel appeared'
    Start-Sleep -Milliseconds 1500   # the slide has ended
    $dpr = ($rect.R - $rect.L) / 300.0
    $inside = @([int]($rect.L + 60 * $dpr), [int]($rect.T + 60 * $dpr))      # inside the moved item (10..110 in the window)
    $outside = @([int]($rect.L + 250 * $dpr), [int]($rect.T + 150 * $dpr))  # in the window, outside the item

    [RegionProbe]::MoveTo($outside[0], $outside[1]); Start-Sleep -Milliseconds 900
    Assert-True ([RegionProbe]::Transparent($panel)) 'with the pointer inside the window but outside the mask item, the panel lets clicks through'
    Assert-True ([RegionProbe]::RootAt($outside[0], $outside[1]) -ne $panel) 'and Windows hit-tests the window below there'

    [RegionProbe]::MoveTo($inside[0], $inside[1]); Start-Sleep -Milliseconds 900
    Assert-True (-not [RegionProbe]::Transparent($panel)) 'with the pointer on the item that slid in, the panel takes the clicks (its input region followed the transform)'
    Assert-True ([RegionProbe]::RootAt($inside[0], $inside[1]) -eq $panel) 'and Windows hit-tests the panel itself there'
}
finally {
    [RegionProbe]::MoveTo(960, 540)
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch {} }
    Unregister-Event -SourceIdentifier $e1.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $e2.Name -ErrorAction SilentlyContinue
    $all = ''; $l = $null
    if ($log) { while ($log.TryDequeue([ref]$l)) { $all += $l + "`n" } }
    if ($all -match 'cache/by-shell/([0-9a-f]{32})/') { $cacheId = $Matches[1] }
    Start-Sleep -Milliseconds 500
    if ($cacheId) {
        $dir = Join-Path $env:LOCALAPPDATA "quickshell\cache\by-shell\$cacheId"
        if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
