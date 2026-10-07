# INSIDE the sandbox: does UserNotificationListener.NotificationChanged fire for an unpackaged process?
[void][Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
try {
    $l = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    $tok = $l.add_NotificationChanged({ param($s, $e) "event: $($e.ChangeKind) $($e.UserNotificationId)" | Out-File -Append C:\xchg\outbox\notif-event.txt })
    'subscribed'
} catch { "subscribe failed: $($_.Exception.GetType().FullName): $($_.Exception.Message)" }
