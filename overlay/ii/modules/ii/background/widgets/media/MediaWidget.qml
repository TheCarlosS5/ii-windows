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
// note in one of ii's Material shapes. That placeholder is STILL by default (P04): a desktop with
// nothing playing produces no frames because of it, only a short settle when it appears. With
// "Keep the music icon moving" (media.idleMotion, off by default) the shape turns and morphs from
// shape to shape; even then it stops under "Reduce motion" (appearance.reduceMotion), when the
// session is locked and while the desktop is covered (every frame repaints the whole wallpaper
// window). Playback never depends on any of this: the cover, controls and spectrum are untouched.
// Drag it by its edges like the clock.
// With "Show the lyrics" (media.lyrics, off by default: the card stays as it was) the song's synced lyrics
// (services/Lyrics.qml, LRCLIB) scroll under the card, the line being sung large in the middle; long
// lines wrap inside the card instead of running off it.
AbstractBackgroundWidget {
    id: root

    configEntryName: "media"
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: root.player !== null
    readonly property bool showLyrics: root.playing && (root.configEntry.lyrics ?? false)
    readonly property real lyricsGap: 10
    readonly property real lyricsHeight: 184
    implicitWidth: playing ? Appearance.sizes.mediaControlsWidth : idle.implicitWidth
    implicitHeight: playing ? Appearance.sizes.mediaControlsHeight + (showLyrics ? lyricsGap + lyricsHeight : 0) : idle.implicitHeight

    // Shown at the top of the desktop menu when it is opened over this widget.
    readonly property var menuEntries: [
        { icon: "lyrics", text: (root.configEntry.lyrics ?? false) ? Translation.tr("Hide the lyrics") : Translation.tr("Show the lyrics"),
          action: () => root.configEntry.lyrics = !(root.configEntry.lyrics ?? false) },
    ]

    // The lyrics of what plays, looked up once per song while they are shown.
    readonly property string lyricsKey: showLyrics ? `${root.player?.trackArtist ?? ""}\n${root.player?.trackTitle ?? ""}` : ""
    onLyricsKeyChanged: if (lyricsKey) lyricsAsk.restart()
    Timer {
        id: lyricsAsk
        interval: 500 // a skip through several songs asks only for the last one
        onTriggered: Lyrics.request(root.player?.trackArtist ?? "", StringUtils.cleanMusicTitle(root.player?.trackTitle) ?? "", root.player?.length ?? 0)
    }
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1

    // The spectrum behind the card, as ii's media popup draws it: cava (ii-shim's, WASAPI
    // loopback on Windows) only while music plays and the desktop is on screen.
    property list<real> visualizerPoints: []
    Process {
        id: cava
        running: root.playing && (root.player?.isPlaying ?? false) && (root.configEntry.spectrum ?? true)
            && root.visible && !GlobalStates.screenLocked && ((QsWindow.window as QsWindow)?.visible ?? false)
            // Not under a maximized app, and not twice: the media panel runs its own cava.
            && !root.desktopCovered && !GlobalStates.mediaControlsOpen
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: if (!running) root.visualizerPoints = []
        stdout: SplitParser {
            onRead: data => {
                root.visualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    Loader {
        id: cardLoader
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Appearance.sizes.mediaControlsHeight
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

    Loader {
        id: lyricsLoader
        anchors {
            top: cardLoader.bottom
            topMargin: root.lyricsGap
            left: parent.left
            right: parent.right
        }
        height: root.lyricsHeight
        active: root.showLyrics
        opacity: root.showLyrics ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        sourceComponent: LyricsCard {
            colors: cardLoader.item?.blendedColors ?? null
        }
    }

    component LyricsCard: Rectangle {
        id: card
        property QtObject colors
        readonly property color colBack: ColorUtils.applyAlpha(colors?.colLayer0 ?? Appearance.colors.colLayer0, 1) // opaque, like the player card
        readonly property color colLine: colors?.colPrimary ?? Appearance.colors.colPrimary
        readonly property color colOther: colors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
        readonly property color colSoft: colors?.colSubtext ?? Appearance.colors.colSubtext
        radius: Appearance.rounding.windowRounding
        color: colBack
        clip: true

        // The line being sung, from the player's position (only while it plays and the desktop is in view).
        property int current: -1
        Timer {
            interval: 200
            repeat: true
            triggeredOnStart: true
            running: Lyrics.lines.length > 0 && (root.player?.isPlaying ?? false) && root.visible
                && !GlobalStates.screenLocked && !root.desktopCovered
            onTriggered: card.current = Lyrics.indexAt(root.player?.position ?? 0)
        }
        Connections {
            target: Lyrics
            function onLinesChanged() {
                card.current = Lyrics.indexAt(root.player?.position ?? 0);
            }
        }

        ListView {
            id: lines
            anchors.fill: parent
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            visible: Lyrics.lines.length > 0
            model: Lyrics.lines
            interactive: false
            spacing: 10
            currentIndex: Math.max(0, card.current)
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: height / 2 - 22
            preferredHighlightEnd: height / 2 + 22
            highlightMoveDuration: 520 * Appearance.motionFactor
            highlightMoveVelocity: -1
            highlightFollowsCurrentItem: true
            delegate: Item {
                id: lineItem
                required property var modelData
                required property int index
                readonly property int distance: Math.abs(index - Math.max(0, card.current))
                readonly property bool sung: index === card.current
                width: ListView.view.width
                implicitHeight: lineText.implicitHeight
                height: implicitHeight
                StyledText {
                    id: lineText
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: 22
                        rightMargin: 22
                    }
                    horizontalAlignment: Text.AlignHCenter
                    text: lineItem.modelData.text
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: lineItem.sung ? Font.Bold : Font.Medium
                    color: lineItem.sung ? card.colLine : (lineItem.index < card.current ? card.colSoft : card.colOther)
                    transformOrigin: Item.Center
                    scale: lineItem.sung ? 1 : 0.86
                    opacity: lineItem.sung ? 1 : Math.max(0.18, 0.62 - 0.2 * (lineItem.distance - 1))
                    Behavior on scale {
                        NumberAnimation { duration: 360 * Appearance.motionFactor; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 300 * Appearance.motionFactor }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 300 * Appearance.motionFactor }
                    }
                }
            }
        }

        // The edges fade into the card, so lines come and go softly.
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 34
            gradient: Gradient {
                GradientStop { position: 0; color: card.colBack }
                GradientStop { position: 1; color: Qt.alpha(card.colBack, 0) }
            }
        }
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 34
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(card.colBack, 0) }
                GradientStop { position: 1; color: card.colBack }
            }
        }

        // Looking it up, or nothing to show.
        Column {
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 10
            visible: Lyrics.lines.length === 0
            MaterialLoadingIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Lyrics.status === "loading"
                loading: visible
                implicitSize: 40
            }
            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Lyrics.status !== "loading"
                text: "lyrics"
                iconSize: 34
                color: card.colSoft
            }
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: card.colSoft
                text: Lyrics.status === "loading" ? Translation.tr("Looking for the lyrics…")
                    : Translation.tr("This song has no synced lyrics")
            }
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
        // Continuous decoration: opt-in, and off whenever it would only cost frames.
        readonly property bool decorativeMotion: (root.configEntry.idleMotion ?? false)
            && !(Config.options.appearance.reduceMotion ?? false)
            && idle.visible && !GlobalStates.screenLocked && !root.desktopCovered

        Timer {
            interval: 4000
            running: idle.decorativeMotion
            repeat: true
            onTriggered: idle.shapeIndex = (idle.shapeIndex + 1) % idle.shapes.length
        }

        MaterialShape {
            id: ring
            anchors.centerIn: parent
            implicitSize: idle.implicitWidth
            shape: idle.shapes[idle.shapeIndex]
            color: Appearance.colors.colSecondaryContainer
            // A short settle when the placeholder appears (or the state changes), then nothing.
            scale: root.playing ? 0.85 : 1
            Behavior on scale {
                enabled: !(Config.options.appearance.reduceMotion ?? false)
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            RotationAnimation on rotation {
                running: idle.decorativeMotion
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
