# INSIDE the sandbox: a borderless fullscreen window standing in for a game.
param([int]$Seconds = 40)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.StartPosition = 'Manual'
$f.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$f.BackColor = [System.Drawing.Color]::FromArgb(30, 120, 60)
$f.Text = 'Fake game'
$label = New-Object System.Windows.Forms.Label
$label.Text = 'FAKE GAME (fullscreen)'; $label.ForeColor = 'White'; $label.AutoSize = $true
$label.Font = New-Object System.Drawing.Font('Segoe UI', 28); $label.Location = New-Object System.Drawing.Point(500, 380)
$f.Controls.Add($label)
$t = New-Object System.Windows.Forms.Timer; $t.Interval = $Seconds * 1000; $t.add_Tick({ $f.Close() }); $t.Start()
$f.add_Shown({ $f.Activate() })
[System.Windows.Forms.Application]::Run($f)
