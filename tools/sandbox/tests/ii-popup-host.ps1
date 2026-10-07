# INSIDE the sandbox: a toast while ii runs under ii-host; screenshots + z-order over time.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$cfg = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $cfg /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$before = @(Get-Process explorer | ForEach-Object { $_.MainWindowTitle })
Start-Process C:\ii\host\build\ii-host.exe -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$cfg`"", '--no-hook'
Start-Sleep 14
"explorer windows before: $($before -join ' | ')"
"explorer windows after:  $(@(Get-Process explorer | ForEach-Object { $_.MainWindowTitle }) -join ' | ')"

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>Popup test</text><text>under ii-host</text></binding></visual></toast>')
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new($xml))
foreach ($t in 1, 2, 4) {
    Start-Sleep 1
    & "$dev\screenshot.ps1" -Out "$out\popup-host-$t.png" -H 300 | Out-Null
}
"--- z-order"
& "$dev\zorder.ps1" | Select-Object -First 14
Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1 | Out-Null
