# INSIDE the sandbox: does HKCU ...\Notifications\Settings\<AUMID>\ShowBanner=0 hide the banner while
# the toast still reaches the notification center (and so UserNotificationListener)?
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await($op, [Type]$type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
[void][Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

$aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$aumid"
function Toast($title) {
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$title</text><text>body</text></binding></visual></toast>")
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
}
function Count() {
    $l = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    (Await ($l.GetNotificationsAsync([Windows.UI.Notifications.NotificationKinds]::Toast)) ([System.Collections.Generic.IReadOnlyList[Windows.UI.Notifications.UserNotification]])).Count
}

"existing values:"; if (Test-Path $key) { Get-ItemProperty $key | Out-String } else { '(none)' }
Toast 'Banner A (default)'; Start-Sleep 2
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\banner-a.png | Out-Null
"count after A: $(Count)"
Start-Sleep 6

New-Item $key -Force | Out-Null
Set-ItemProperty $key -Name ShowBanner -Value 0 -Type DWord
Toast 'Banner B (ShowBanner=0)'; Start-Sleep 2
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\banner-b.png | Out-Null
"count after B: $(Count)"
"values now:"; Get-ItemProperty $key | Out-String
