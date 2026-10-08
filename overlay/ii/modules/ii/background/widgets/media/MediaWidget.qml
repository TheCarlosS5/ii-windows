pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import qs.modules.ii.mediaControls

// ii-windows: ii's player card (the one in the bar's media popup) on the desktop, for whatever
// is playing: cover, title, artist, progress and controls. While nothing plays it shows a music
// note in one of ii's Material shapes, which slowly turns and morphs from shape to shape.
// Drag it by its edges like the clock.
AbstractBackgroundWidget {
    id: root

    configEntryName: "media"
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: root.player !== null
    implicitWidth: playing ? Appearance.sizes.mediaControlsWidth : idle.implicitWidth
    implicitHeight: playing ? Appearance.sizes.mediaControlsHeight : idle.implicitHeight
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1

    // The spectrum behind the card, as ii's media popup draws it: cava (ii-shim's, WASAPI
    // loopback on Windows) only while music plays and the desktop is on screen.
    property list<real> visualizerPoints: []
    Process {
        id: cava
        running: root.playing && (root.player?.isPlaying ?? false) && (root.configEntry.spectrum ?? true)
            && root.visible && !GlobalStates.screenLocked && ((QsWindow.window as QsWindow)?.visible ?? false)
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: if (!running) root.visualizerPoints = []
        stdout: SplitParser {
            onRead: data => {
                root.visualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.playing
        opacity: root.playing ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        sourceComponent: PlayerControl {
            player: root.player
            visualizerPoints: root.visualizerPoints
            radius: Appearance.rounding.windowRounding
        }
    }

    Item {
        id: idle
        implicitWidth: 112
        implicitHeight: 112
        visible: opacity > 0
        opacity: root.playing ? 0 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Same shapes and pace as ii's Material loading indicator, just calmer.
        property list<var> shapes: [
            MaterialShape.Shape.Cookie9Sided,
            MaterialShape.Shape.SoftBurst,
            MaterialShape.Shape.Cookie12Sided,
            MaterialShape.Shape.Clover8Leaf,
            MaterialShape.Shape.Sunny,
            MaterialShape.Shape.Cookie7Sided,
            MaterialShape.Shape.Flower,
        ]
        property int shapeIndex: 0

        Timer {
            interval: 4000
            running: idle.visible && !GlobalStates.screenLocked
            repeat: true
            onTriggered: idle.shapeIndex = (idle.shapeIndex + 1) % idle.shapes.length
        }

        MaterialShape {
            id: ring
            anchors.centerIn: parent
            implicitSize: idle.implicitWidth
            shape: idle.shapes[idle.shapeIndex]
            color: Appearance.colors.colSecondaryContainer
            RotationAnimation on rotation {
                running: idle.visible && !GlobalStates.screenLocked
                from: 0
                to: 360
                duration: 30000
                loops: Animation.Infinite
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "music_note"
            iconSize: 48
            fill: 1
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
