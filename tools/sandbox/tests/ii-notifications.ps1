# INSIDE the sandbox: a notify-send notification and a real Windows toast, as ii shows them.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14

# 1. From the shell side (ii-shim as notify-send).
& "$dist\bin\notify-send.exe" 'Hola desde notify-send' 'Cuerpo con <b>negrita</b> y acentos: canción' -a Shell
Start-Sleep 1

# 2. A real toast, from PowerShell's AUMID.
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
$aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>Mensaje nuevo</text><text>Esto es un toast real de Windows &lt;3</text></binding></visual></toast>')
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\notif-popups.png" | Out-Null

# 3. The notification list in the right sidebar.
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\notif-sidebar.png" | Out-Null

Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'notif|Notif' } | Select-Object -Last 15
