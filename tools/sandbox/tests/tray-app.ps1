# INSIDE the sandbox: a tray icon app (WinForms NotifyIcon) that logs clicks and has a context menu.
param([int]$Seconds = 60, [string]$Name = 'ii tray test')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$log = 'C:\xchg\outbox\tray-clicks.txt'
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.Text = "$Name`nsecond line"
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Abrir ventana')
[void]$menu.Items.Add('Salir')
$icon.ContextMenuStrip = $menu
$icon.add_MouseClick({ param($s, $e) "click $($e.Button)" | Out-File -Append $log })
$icon.add_MouseDoubleClick({ param($s, $e) "double $($e.Button)" | Out-File -Append $log })
$menu.add_Opened({ 'menu opened' | Out-File -Append $log })
$icon.Visible = $true
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $Seconds * 1000
$timer.add_Tick({ $icon.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$timer.Start()
[System.Windows.Forms.Application]::Run()
