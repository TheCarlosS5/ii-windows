# Left-button drag from (X1, Y1) to (X2, Y2) in small steps (selection rectangles and the like).
param([int]$X1, [int]$Y1, [int]$X2, [int]$Y2, [int]$Steps = 15)
Add-Type -Namespace IiDrag -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, System.UIntPtr e);' -ErrorAction SilentlyContinue
[IiDrag.M]::SetCursorPos($X1, $Y1) | Out-Null
Start-Sleep -Milliseconds 200
[IiDrag.M]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero)
for ($i = 1; $i -le $Steps; $i++) {
    [IiDrag.M]::SetCursorPos([int]($X1 + ($X2 - $X1) * $i / $Steps), [int]($Y1 + ($Y2 - $Y1) * $i / $Steps)) | Out-Null
    Start-Sleep -Milliseconds 25
}
Start-Sleep -Milliseconds 100
[IiDrag.M]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero)
