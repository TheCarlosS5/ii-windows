# INSIDE the sandbox: can an unpackaged process read toasts through UserNotificationListener?
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await($op, [Type]$type) {
    $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
}
[void][Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

# A toast from PowerShell's registered AUMID.
$aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>Probe title</text><text>Probe body from a toast</text></binding></visual></toast>')
try {
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    'toast shown'
} catch { "toast failed: $($_.Exception.Message)" }
Start-Sleep 2

try {
    $l = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    "access before: $($l.GetAccessStatus())"
    $st = Await ($l.RequestAccessAsync()) ([Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus])
    "request: $st"
    $list = Await ($l.GetNotificationsAsync([Windows.UI.Notifications.NotificationKinds]::Toast)) ([System.Collections.Generic.IReadOnlyList[Windows.UI.Notifications.UserNotification]])
    "count: $($list.Count)"
    foreach ($n in $list) {
        $b = $n.Notification.Visual.GetBinding([Windows.UI.Notifications.KnownNotificationBindings]::ToastGeneric)
        $texts = ($b.GetTextElements() | ForEach-Object { $_.Text }) -join ' | '
        "  #$($n.Id) app=$($n.AppInfo.DisplayInfo.DisplayName) aumid=$($n.AppInfo.AppUserModelId) texts=$texts"
    }
} catch { "listener failed: $($_.Exception.GetType().FullName): $($_.Exception.Message)" }
