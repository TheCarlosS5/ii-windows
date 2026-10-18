import QtQuick

// ii-windows: smooth mouse-wheel scrolling for a Flickable, ListView or GridView. Put it over the view
// (anchors.fill: view). Qt's own wheel handling on Windows turns quick wheel turns into flicks that
// fight each other (the list stalls, then jumps); here every notch moves the goal a fixed step and
// the view glides there, so a fast spin simply goes further. A touchpad scrolls 1:1. Clicks and
// hover go through to the view (no buttons accepted).
MouseArea {
    id: root
    required property Flickable flickable
    property real step: 132 // pixels per wheel notch
    property int duration: 280
    acceptedButtons: Qt.NoButton
    hoverEnabled: false

    property real goal: 0

    function clampY(y) {
        const f = root.flickable;
        const min = f.originY - f.topMargin;
        const max = Math.max(min, f.originY + f.contentHeight + f.bottomMargin - f.height);
        return Math.max(min, Math.min(max, y));
    }

    onWheel: wheel => {
        const f = root.flickable;
        if (!f) {
            wheel.accepted = false;
            return;
        }
        const touchpad = wheel.pixelDelta.y !== 0 && Math.abs(wheel.angleDelta.y) < 120;
        if (touchpad) {
            glide.stop();
            f.contentY = root.clampY(f.contentY - wheel.pixelDelta.y);
            root.goal = f.contentY;
        } else {
            const base = glide.running ? root.goal : f.contentY;
            root.goal = root.clampY(base - wheel.angleDelta.y / 120 * root.step);
            glide.stop();
            glide.from = f.contentY;
            glide.to = root.goal;
            glide.start();
        }
        wheel.accepted = true;
    }

    NumberAnimation {
        id: glide
        target: root.flickable
        property: "contentY"
        duration: root.duration
        easing.type: Easing.OutCubic
    }
}
