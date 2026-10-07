# Capture the screen (or a region of it) to a PNG, DPI-aware.
# usage: screenshot.ps1 -Out shot.png [-X 0 -Y 0 -W 1920 -H 200] [-Delay 0]
param([Parameter(Mandatory)][string]$Out, [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0, [double]$Delay = 0)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -Namespace Native -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[Native.Dpi]::SetProcessDPIAware() | Out-Null
if ($Delay -gt 0) { Start-Sleep -Milliseconds ([int]($Delay * 1000)) }
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($W -le 0) { $W = $b.Width }
if ($H -le 0) { $H = $b.Height }
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output $Out
