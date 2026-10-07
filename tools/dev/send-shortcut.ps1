# Sends a GlobalShortcut press+release to the running shell, the same way ii-host does.
#   send-shortcut.ps1 -Name overviewWorkspacesToggle
param([Parameter(Mandatory)][string]$Name, [switch]$PressOnly, [switch]$ReleaseOnly)
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Sc {
  [StructLayout(LayoutKind.Sequential)] struct CDS { public IntPtr dwData; public int cb; public IntPtr data; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, ref CDS l);
  public static bool Send(string name, bool pressed) {
    var sink = FindWindow("IiShellShortcutSink", null);
    if (sink == IntPtr.Zero) return false;
    var p = Marshal.StringToHGlobalUni(name);
    var cds = new CDS { dwData = (IntPtr)(pressed ? 0x49490001 : 0x49490002), cb = (name.Length + 1) * 2, data = p };
    SendMessage(sink, 0x004A, IntPtr.Zero, ref cds);
    Marshal.FreeHGlobal(p);
    return true;
  }
}
'@
$ok = $true
if (-not $ReleaseOnly) { $ok = [Sc]::Send($Name, $true) }
if (-not $PressOnly) { $ok = $ok -and [Sc]::Send($Name, $false) }
if ($ok) { "sent $Name" } else { "shell shortcut sink not found" }
