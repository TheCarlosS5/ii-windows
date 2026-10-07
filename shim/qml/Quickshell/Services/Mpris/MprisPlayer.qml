// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

QtObject {
    property bool canControl: false
    property bool canPlay: false
    property bool canPause: false
    property bool canTogglePlaying: false
    property bool canSeek: false
    property bool canGoNext: false
    property bool canGoPrevious: false
    property bool canQuit: false
    property bool canRaise: false
    property string identity: ""
    property string desktopEntry: ""
    property string dbusName: ""
    property real position: 0
    property bool positionSupported: false
    property real length: 0
    property bool lengthSupported: false
    property real volume: 1
    property bool volumeSupported: false
    property var metadata: ({})
    property int uniqueId: 0
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackArtists: ""
    property string trackAlbum: ""
    property string trackAlbumArtist: ""
    property string trackArtUrl: ""
    property int playbackState: 0
    property bool isPlaying: false
    property int loopState: 0
    property bool loopSupported: false
    property real rate: 1
    property bool shuffle: false
    property bool shuffleSupported: false
    signal postTrackChanged()
    function raise() {}
    function quit() {}
    function next() {}
    function previous() {}
    function seek(offset) {}
    function play() {}
    function pause() {}
    function stop() {}
    function togglePlaying() {}
}
