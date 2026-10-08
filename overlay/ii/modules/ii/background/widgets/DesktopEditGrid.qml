import QtQuick
import qs
import qs.modules.common

// ii-windows: while editing the desktop, a dotted grid the widgets snap to (gridSize px).
Item {
    id: root

    readonly property int gridSize: 32
    visible: opacity > 0
    opacity: GlobalStates.desktopEditMode ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle { // dim the wallpaper a bit, as ii's overlay does
        anchors.fill: parent
        color: Qt.alpha(Appearance.colors.colScrim ?? "black", 0.25)
    }

    Canvas {
        anchors.fill: parent
        visible: root.visible
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Qt.alpha(Appearance.colors.colOnLayer0, 0.35);
            for (let x = root.gridSize; x < width; x += root.gridSize) {
                for (let y = root.gridSize; y < height; y += root.gridSize) {
                    ctx.beginPath();
                    ctx.arc(x, y, 1.6, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }
        }
    }
}
