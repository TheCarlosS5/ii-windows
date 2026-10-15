# ii-windows: the uninstall window ("Desinstalar ii-windows" in the Start menu and in Settings > Apps).
# One question, one button; the real work is uninstall.ps1 -Yes (it puts Windows back exactly as it was).
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$uninstall = Join-Path $here 'uninstall.ps1'
if (-not (Test-Path -LiteralPath $uninstall)) {
    [System.Windows.Forms.MessageBox]::Show("Falta uninstall.ps1 junto a este desinstalador:`n$here", 'ii-windows', 'OK', 'Error') | Out-Null
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Desinstalar ii-windows'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(520, 300)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::White

$bar = New-Object System.Windows.Forms.Panel
$bar.Dock = 'Left'
$bar.Width = 8
$bar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#7F5AF0')
$form.Controls.Add($bar)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Quitar ii-windows'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.Location = New-Object System.Drawing.Point(28, 18)
$title.AutoSize = $true
$form.Controls.Add($title)

$text = New-Object System.Windows.Forms.Label
$text.Text = "Se cierra ii y se devuelven la barra de tareas, los iconos, los colores, el cursor y el fondo de pantalla que tenía Windows. Se borran los accesos y las carpetas que creó ii. No se tocan tus archivos ni tus programas."
$text.Location = New-Object System.Drawing.Point(30, 62)
$text.Size = New-Object System.Drawing.Size(465, 90)
$form.Controls.Add($text)

$keep = New-Object System.Windows.Forms.CheckBox
$keep.Text = 'Conservar mis ajustes de ii y mis claves guardadas (por si lo vuelvo a instalar)'
$keep.Checked = $true
$keep.Location = New-Object System.Drawing.Point(30, 162)
$keep.Size = New-Object System.Drawing.Size(465, 48)
$form.Controls.Add($keep)

$go = New-Object System.Windows.Forms.Button
$go.Text = 'Desinstalar'
$go.Size = New-Object System.Drawing.Size(130, 38)
$go.Location = New-Object System.Drawing.Point(235, 238)
$go.FlatStyle = 'Flat'
$go.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#7F5AF0')
$go.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($go)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancelar'
$cancel.Size = New-Object System.Drawing.Size(110, 38)
$cancel.Location = New-Object System.Drawing.Point(380, 238)
$cancel.DialogResult = 'Cancel'
$form.CancelButton = $cancel
$form.Controls.Add($cancel)

$go.Add_Click({
    $go.Enabled = $false; $cancel.Enabled = $false; $keep.Enabled = $false
    $title.Text = 'Desinstalando...'
    $text.Text = 'Un momento: se está devolviendo todo a como estaba. Esta ventana se cierra sola al terminar.'
    $form.Refresh()
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$uninstall`"", '-Yes')
    if ($keep.Checked) { $args2 += '-KeepConfig' }
    $p = Start-Process powershell.exe -ArgumentList $args2 -WindowStyle Hidden -PassThru
    while (-not $p.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    $form.Close()
    if ($p.ExitCode -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('ii-windows se desinstaló y Windows quedó como estaba. Gracias por probarlo.', 'ii-windows', 'OK', 'Information') | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show("La desinstalación no terminó bien (código $($p.ExitCode)). Abre una consola y ejecuta uninstall.cmd -Yes para ver el detalle, o usa 'Rescate de ii'.", 'ii-windows', 'OK', 'Warning') | Out-Null
    }
})
[void]$form.ShowDialog()
