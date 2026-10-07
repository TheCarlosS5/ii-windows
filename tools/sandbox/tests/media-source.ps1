# INSIDE the sandbox: a GSMTC media session ("ii-windows test track") playing a silent file.
[void][Windows.Media.Playback.MediaPlayer, Windows.Media.Playback, ContentType = WindowsRuntime]
[void][Windows.Media.Core.MediaSource, Windows.Media.Core, ContentType = WindowsRuntime]
[void][Windows.Foundation.Uri, Windows.Foundation, ContentType = WindowsRuntime]
$player = New-Object Windows.Media.Playback.MediaPlayer
$player.Source = [Windows.Media.Core.MediaSource]::CreateFromUri([Uri]'file:///C:/xchg/silence.wav')
$player.CommandManager.IsEnabled = $true
$smtc = $player.SystemMediaTransportControls
$smtc.IsEnabled = $true
$smtc.IsPlayEnabled = $true
$smtc.IsPauseEnabled = $true
$smtc.IsNextEnabled = $true
$updater = $smtc.DisplayUpdater
$updater.Type = [Windows.Media.MediaPlaybackType]::Music
$updater.MusicProperties.Title = 'Lucid Dreams (test track)'
$updater.MusicProperties.Artist = 'ii-windows'
$updater.MusicProperties.AlbumTitle = 'Sandbox Sessions'
$updater.Update()
$player.Play()
Start-Sleep 100
