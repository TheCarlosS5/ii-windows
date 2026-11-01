// Test config (plan 2026-10-31, A8): reads every MPRIS player property the way ii's media panels do, and logs a line
// per second. Used by tools/sandbox/tests/test-mpris-stress.ps1 with ii-media-churn.exe.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

ShellRoot {
    id: root
    property int maxPlayers: 0
    property int seenTitles: 0

    Repeater {
        model: Mpris.players
        Item {
            required property var modelData
            property string title: modelData?.trackTitle ?? ""
            property string art: modelData?.trackArtUrl ?? ""
            property bool playing: modelData?.isPlaying ?? false
            property real length: modelData?.length ?? 0
            property real position: modelData?.position ?? 0
            property bool seek: modelData?.canSeek ?? false
            onTitleChanged: root.seenTitles++
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const n = Mpris.players.values.length;
            root.maxPlayers = Math.max(root.maxPlayers, n);
            console.info(`mpris-watch players=${n} max=${root.maxPlayers} titles=${root.seenTitles}`);
        }
    }
}
