# Moves the mouse along a list of points (like a hand would) and optionally screenshots at the end.
#   mouse.ps1 -Points 960,1075 960,1040 -StepMs 30 -Shot out.png [-ShotDelayMs 500]
# Each point is "x,y". Between points the cursor is moved in 8 small steps so hover handlers see motion.
param([string[]]$Points, [int]$StepMs = 25, [string]$Shot = '', [int]$ShotDelayMs = 500, [int]$HoldMs = 400)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Native -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction SilentlyContinue
[Native.Dpi]::SetProcessDPIAware() | Out-Null
$cur = [System.Windows.Forms.Cursor]::Position
foreach ($p in $Points) {
    $xy = $p.Split(',') | ForEach-Object { [int]$_ }
    $x = $xy[0]; $y = $xy[1]
    for ($i = 1; $i -le 8; $i++) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]($cur.X + ($x - $cur.X) * $i / 8)), ([int]($cur.Y + ($y - $cur.Y) * $i / 8))
        Start-Sleep -Milliseconds $StepMs
    }
    $cur = New-Object System.Drawing.Point $x, $y
    Start-Sleep -Milliseconds $HoldMs
}
if ($Shot) { Start-Sleep -Milliseconds $ShotDelayMs; & "$PSScriptRoot\screenshot.ps1" -Out $Shot | Out-Null }
