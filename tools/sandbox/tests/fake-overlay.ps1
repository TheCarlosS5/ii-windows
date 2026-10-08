# A click-through, screen-sized overlay of another app (like the cursor overlay of an automation
# tool found on the real PC). It must never make ii think a fullscreen app is running.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace FakeOverlay -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);'
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.Bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$form.BackColor = [Drawing.Color]::Magenta
$form.TransparencyKey = [Drawing.Color]::Magenta
$form.Add_Shown({
    # WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW, as cua-driver's overlay.
    $ex = [FakeOverlay.W]::GetWindowLong($form.Handle, -20)
    [void][FakeOverlay.W]::SetWindowLong($form.Handle, -20, $ex -bor 0x80000 -bor 0x20 -bor 0x80)
})
[Windows.Forms.Application]::Run($form)
