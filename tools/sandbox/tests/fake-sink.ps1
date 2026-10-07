# Stand-in for the ii shell's shortcut receiver: a window of class IiShellShortcutSink that
# appends every WM_COPYDATA shortcut it gets to C:\xchg\outbox\sink.log.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class FakeSink {
    delegate IntPtr WndProc(IntPtr h, uint m, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WNDCLASS { public uint style; public WndProc proc; public int cls, wnd; public IntPtr inst, icon, cursor, bg; public string menu, name; }
    [StructLayout(LayoutKind.Sequential)] struct COPYDATA { public IntPtr dwData; public int cb; public IntPtr data; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint m; public IntPtr w, l; public uint t; public int x, y; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern ushort RegisterClassW(ref WNDCLASS c);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string cls, string title, uint style, int x, int y, int w, int h, IntPtr p, IntPtr m, IntPtr i, IntPtr a);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern int GetMessageW(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool DispatchMessageW(ref MSG m);
    [DllImport("user32.dll")] static extern bool ChangeWindowMessageFilterEx(IntPtr h, uint m, uint a, IntPtr p);
    static WndProc keep;
    public static void Run(string log) {
        keep = (h, m, w, l) => {
            if (m == 0x004A) {
                var cd = (COPYDATA)Marshal.PtrToStructure(l, typeof(COPYDATA));
                var name = Marshal.PtrToStringUni(cd.data);
                var kind = cd.dwData.ToInt64() == 0x49490001 ? "pressed" : "released";
                File.AppendAllText(log, DateTime.Now.ToString("HH:mm:ss.fff") + " " + kind + " " + name + "\r\n");
                return (IntPtr)1;
            }
            return DefWindowProcW(h, m, w, l);
        };
        var wc = new WNDCLASS { proc = keep, name = "IiShellShortcutSink" };
        RegisterClassW(ref wc);
        var hwnd = CreateWindowExW(0x80, "IiShellShortcutSink", "sink", 0x80000000, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        ChangeWindowMessageFilterEx(hwnd, 0x004A, 1, IntPtr.Zero);
        MSG msg;
        while (GetMessageW(out msg, IntPtr.Zero, 0, 0) > 0) DispatchMessageW(ref msg);
    }
}
'@
[FakeSink]::Run('C:\xchg\outbox\sink.log')
