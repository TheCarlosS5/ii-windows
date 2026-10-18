pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: the store's front page carousel, Material 3 Expressive "hero" style: one big card and a few narrow
// ones next to it. Every few seconds (not under the pointer) the next app takes the big place: the cards change
// size and slide instead of being swapped. A click on a narrow card brings it forward.
Item {
    id: root
    property var apps: [] // [{ id, name, site, desc, tagline, aka }]
    property int current: 0
    readonly property int count: apps.length
    readonly property int shown: Math.min(count, width > 980 ? 4 : 3)
    readonly property real gap: 10
    readonly property real narrow: 132
    readonly property real wide: Math.max(narrow, width - (shown - 1) * (narrow + gap))
    implicitHeight: 236
    clip: true

    HoverHandler {
        id: hover
    }
    Timer {
        interval: 6500
        repeat: true
        running: root.count > 1 && !hover.hovered && root.Window.active
        onTriggered: root.current = (root.current + 1) % root.count
    }

    function slotX(rank) {
        return rank === 0 ? 0 : wide + gap + (rank - 1) * (narrow + gap);
    }

    Repeater {
        model: root.count
        delegate: Rectangle {
            id: card
            required property int index
            readonly property var app: root.apps[index]
            readonly property int rank: (index - root.current + root.count) % root.count
            readonly property bool big: rank === 0
            readonly property bool onScreen: rank < root.shown
            readonly property real hue: {
                let h = 0;
                const s = app?.name ?? "";
                for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
                return h / 360;
            }
            x: onScreen ? root.slotX(rank) : rank === root.count - 1 ? -root.narrow - root.gap : root.width + root.gap
            y: 0
            width: big ? root.wide : root.narrow
            height: root.height
            opacity: onScreen ? 1 : 0
            radius: Appearance.rounding.verylarge ?? 28
            color: Qt.hsla(hue, 0.42, Appearance.m3colors.darkmode ? 0.24 : 0.86, 1)
            Behavior on x {
                NumberAnimation { duration: 520 * Appearance.motionFactor; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                NumberAnimation { duration: 520 * Appearance.motionFactor; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
            }
            Behavior on opacity {
                NumberAnimation { duration: 300 * Appearance.motionFactor }
            }

            TapHandler {
                enabled: !card.big
                onTapped: root.current = card.index
            }

            // A big soft shape behind the icon, turned a little differently for each app.
            MaterialShape {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    rightMargin: card.big ? 28 : (card.width - implicitSize) / 2
                }
                implicitSize: card.big ? 188 : 96
                shape: [MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie12Sided, MaterialShape.Shape.Clover8Leaf][card.index % 4]
                rotation: card.hue * 90
                color: Qt.hsla(card.hue, 0.5, Appearance.m3colors.darkmode ? 0.34 : 0.76, 1)
                Behavior on implicitSize {
                    NumberAnimation { duration: 520 * Appearance.motionFactor; easing.type: Easing.OutCubic }
                }
                StoreIcon {
                    anchors.centerIn: parent
                    site: card.app?.site ?? ""
                    label: card.app?.name ?? ""
                    size: card.big ? 92 : 56
                }
            }

            // Big card: what it is and the button.
            ColumnLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 28
                    rightMargin: 240
                }
                spacing: 6
                visible: opacity > 0
                opacity: card.big && card.width > root.narrow + 200 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 220 * Appearance.motionFactor }
                }
                StyledText {
                    text: Translation.tr("Recommended")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.app?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(card.app?.tagline ?? card.app?.desc ?? "")
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                }
                StoreAction {
                    Layout.topMargin: 8
                    compact: true
                    appId: card.app?.id ?? ""
                    name: card.app?.name ?? ""
                    aka: card.app?.aka ?? []
                }
            }
        }
    }

    // Where the carousel is: one dot per app, the current one long.
    Row {
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 28
            bottomMargin: 14
        }
        spacing: 5
        Repeater {
            model: root.count
            delegate: Rectangle {
                required property int index
                width: index === root.current ? 18 : 6
                height: 6
                radius: 3
                color: index === root.current ? Appearance.colors.colOnLayer0 : Qt.alpha(Appearance.colors.colOnLayer0, 0.3)
                Behavior on width {
                    NumberAnimation { duration: 240 * Appearance.motionFactor }
                }
            }
        }
    }
}
