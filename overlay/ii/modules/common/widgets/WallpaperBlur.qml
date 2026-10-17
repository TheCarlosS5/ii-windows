import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.modules.common

// ii-windows: the frosted glass Hyprland draws behind ii's panels. Windows blurs nothing behind a
// translucent window, so with transparency on the wallpaper's details (and the desktop widgets) showed
// through the panels and made them hard to read. This draws the wallpaper, blurred, exactly where the
// panel sits on the screen (like Windows 11's Mica: the wallpaper, not the windows behind), with the
// panel's own translucent colour over it.
//
// Put it as the first child of a panel's background Rectangle:
//     WallpaperBlur { anchors.fill: parent; radius: parent.radius; tint: parent.color; inset: parent.border.width }
// The position is the panel's place at rest (transforms are left out), so a panel that slides in carries
// its glass with it and lands aligned.
Item {
    id: root

    property real radius: 0
    property color tint: Appearance.colors.colLayer0
    property real inset: 0 // the parent's border width: the glass stays inside the border
    property real minTintAlpha: 0.5

    readonly property bool active: (Config.options.appearance.transparency.enable ?? false)
        && (Config.options.appearance.transparency.blurBehind ?? true)
        && Appearance.backgroundTransparency > 0.02
        && wallpaperSource.length > 0
    readonly property string wallpaperSource: {
        const p = Config.options.background.wallpaperPath ?? "";
        const video = /\.(mp4|webm|mkv|avi|mov|gif)$/i.test(p);
        const s = video ? (Config.options.background.thumbnailPath ?? "") : p;
        return s.length > 0 ? Qt.resolvedUrl(s) : "";
    }

    readonly property var screenInfo: root.QsWindow.window?.screen ?? null
    readonly property real screenWidth: screenInfo?.width ?? 1920
    readonly property real screenHeight: screenInfo?.height ?? 1080
    // Where this item's top-left corner is on its screen, at rest.
    property real screenX: 0
    property real screenY: 0

    // The blur works on a small copy (1/4) scaled back up: cheap, and the blur is wide anyway.
    readonly property real down: 4
    readonly property real pad: 48 // the copy runs past the screen edges, so the blur does not fade there

    function place() {
        let x = root.inset, y = root.inset, item = root, top = root;
        while (item) {
            x += item.x;
            y += item.y;
            top = item;
            item = item.parent;
        }
        // `top` is the window's content item; it never moves inside the window.
        const g = top.mapToGlobal(0, 0);
        root.screenX = x + g.x - top.x - (root.screenInfo?.x ?? 0);
        root.screenY = y + g.y - top.y - (root.screenInfo?.y ?? 0);
    }

    visible: active
    onVisibleChanged: if (visible) Qt.callLater(root.place)
    onWidthChanged: Qt.callLater(root.place)
    onHeightChanged: Qt.callLater(root.place)
    Component.onCompleted: Qt.callLater(root.place)
    Timer {
        // Layouts settle after the first frame (and a panel can be moved by its settings).
        running: root.visible
        interval: 700
        onTriggered: root.place()
    }

    Item {
        id: glass
        anchors.fill: parent
        anchors.margins: root.inset
        clip: true
        layer.enabled: root.active && root.radius > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: glass.width
                height: glass.height
                radius: Math.max(0, root.radius - root.inset)
            }
        }

        Item {
            id: small
            visible: root.active
            x: -root.screenX - root.pad
            y: -root.screenY - root.pad
            width: (root.screenWidth + root.pad * 2) / root.down
            height: (root.screenHeight + root.pad * 2) / root.down
            scale: root.down
            transformOrigin: Item.TopLeft

            Image {
                id: wall
                anchors.fill: parent
                visible: false
                source: root.active ? root.wallpaperSource : ""
                sourceSize: Qt.size(Math.round(parent.width), Math.round(parent.height))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: 1
                saturation: 0.1
            }
        }

        Rectangle {
            // Over a blur the panel may be a little less see-through than over Hyprland's: a bright
            // wallpaper still washes out white text at the user's most transparent setting.
            anchors.fill: parent
            color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, Math.max(root.tint.a, root.minTintAlpha))
        }
    }
}
