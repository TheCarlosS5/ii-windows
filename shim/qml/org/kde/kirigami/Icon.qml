// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick
import QtQuick.Effects
import Quickshell

// Kirigami.Icon subset: theme icon names resolve through Quickshell's icon provider.
Item {
    id: root
    property var source: ""
    property var fallback: "application-x-executable"
    property bool isMask: false
    property color color: "transparent"
    property bool roundToIconSize: true
    property bool animated: false
    property bool active: false
    property bool selected: false
    property string placeholder: ""
    readonly property bool valid: image.status === Image.Ready
    readonly property int status: image.status
    implicitWidth: 32
    implicitHeight: 32

    function resolve(src) {
        const s = String(src ?? "");
        if (s.length === 0) return "";
        if (s.indexOf("/") >= 0 || s.indexOf(":") >= 0) return s;
        return Quickshell.iconPath(s, String(root.fallback));
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.resolve(root.source)
        sourceSize: Qt.size(root.width * 2, root.height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        visible: !root.isMask
        asynchronous: true
    }
    MultiEffect {
        anchors.fill: image
        source: image
        visible: root.isMask
        colorization: 1
        colorizationColor: root.color
    }
}
