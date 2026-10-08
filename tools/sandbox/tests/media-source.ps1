# INSIDE the sandbox: a GSMTC media session ("ii-windows test track") playing a silent file.
# The metadata goes on the MediaPlaybackItem: with the CommandManager on, MediaPlayer fills the
# SMTC display from the current item and would overwrite a manual DisplayUpdater.
[void][Windows.Media.Playback.MediaPlayer, Windows.Media.Playback, ContentType = WindowsRuntime]
[void][Windows.Media.Playback.MediaPlaybackItem, Windows.Media.Playback, ContentType = WindowsRuntime]
[void][Windows.Media.Core.MediaSource, Windows.Media.Core, ContentType = WindowsRuntime]
[void][Windows.Foundation.Uri, Windows.Foundation, ContentType = WindowsRuntime]
$source = [Windows.Media.Core.MediaSource]::CreateFromUri([Uri]'file:///C:/xchg/silence.wav')
$item = New-Object Windows.Media.Playback.MediaPlaybackItem $source
$props = $item.GetDisplayProperties()
$props.Type = [Windows.Media.MediaPlaybackType]::Music
$props.MusicProperties.Title = 'Lucid Dreams (test track)'
$props.MusicProperties.Artist = 'ii-windows'
$props.MusicProperties.AlbumTitle = 'Sandbox Sessions'
# Cover art, so players show a thumbnail (ii's default wallpaper stands in for an album cover).
[void][Windows.Storage.Streams.RandomAccessStreamReference, Windows.Storage.Streams, ContentType = WindowsRuntime]
$props.Thumbnail = [Windows.Storage.Streams.RandomAccessStreamReference]::CreateFromUri([Uri]'file:///C:/ii/build/ii/assets/images/default_wallpaper.png')
$item.ApplyDisplayProperties($props)
$player = New-Object Windows.Media.Playback.MediaPlayer
$player.Volume = 0
$player.Source = $item
$player.Play()
"source: title=$($player.SystemMediaTransportControls.DisplayUpdater.MusicProperties.Title)" | Out-File C:\xchg\outbox\media-source.txt
Start-Sleep 100
