# Moves the mouse to (X, Y) and clicks. -Button Left|Right|Middle.
param([int]$X, [int]$Y, [string]$Button = 'Left')
Add-Type -Namespace IiClick -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, System.UIntPtr e);' -ErrorAction SilentlyContinue
$flags = @{ Left = 0x2, 0x4; Right = 0x8, 0x10; Middle = 0x20, 0x40 }[$Button]
[IiClick.M]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 150
[IiClick.M]::mouse_event($flags[0], 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[IiClick.M]::mouse_event($flags[1], 0, 0, 0, [UIntPtr]::Zero)
