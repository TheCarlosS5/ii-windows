import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, C4.1): a ContentSection whose controls are created only when the section comes near
// the visible part of the page (1.5 screens), and stay once created. Until then it keeps an estimated height, so the
// scroll bar does not jump much. tools/port/gen_lazy_sections.py turns the long pages' sections into these.
// The settings search loads them all first (isLazySection / load).
ContentSection {
    id: root

    property Component content
    property real estimatedHeight: 200
    property bool load: false
    readonly property bool isLazySection: true

    property Item flickable: null
    function findFlickable() {
        for (let p = root.parent; p; p = p.parent)
            if (p.flickableDirection !== undefined) return p;
        return null;
    }
    function check() {
        if (root.load) return;
        if (!root.flickable) {
            root.load = true;
            return;
        }
        const y = root.mapToItem(root.flickable.contentItem, 0, 0).y;
        const top = root.flickable.contentY - 1.5 * root.flickable.height;
        const bottom = root.flickable.contentY + 2.5 * root.flickable.height;
        if (y < bottom && y + root.height > top) root.load = true;
    }
    Component.onCompleted: {
        root.flickable = root.findFlickable();
        Qt.callLater(root.check); // once the page has its layout
    }
    Connections {
        target: root.flickable
        enabled: !root.load
        function onContentYChanged() { root.check(); }
        function onHeightChanged() { root.check(); }
    }

    Loader {
        Layout.fillWidth: true
        active: root.load
        sourceComponent: root.content
    }
    Item {
        visible: !root.load
        Layout.fillWidth: true
        implicitHeight: root.estimatedHeight
    }
}
