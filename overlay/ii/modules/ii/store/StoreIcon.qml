import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects

// ii-windows: an app's icon in the store: its site's favicon (downloaded once, kept), or a coloured letter
// when there is no site (search results) or the download fails.
Item {
    id: root
    property string site: ""
    property string label: ""
    property real size: 52

    implicitWidth: size
    implicitHeight: size

    readonly property string cacheFile: FileUtils.trimFileProtocol(`${Directories.favicons}/store-${root.site}.png`)
    property string loaded: ""

    Process {
        id: fetch
        running: false
        command: ["ii-shim", "fetch", `https://www.google.com/s2/favicons?domain=${root.site}&sz=128`, "--out", root.cacheFile, "--keep"]
        onExited: (code, status) => {
            if (code === 0) root.loaded = root.cacheFile;
        }
    }
    onSiteChanged: {
        loaded = "";
        if (site !== "") fetch.running = true;
    }
    Component.onCompleted: {
        if (site !== "") fetch.running = true;
    }

    // The letter, when there is no picture.
    Rectangle {
        anchors.fill: parent
        visible: image.status !== Image.Ready
        radius: root.size * 0.28
        color: {
            let h = 0;
            for (let i = 0; i < root.label.length; i++) h = (h * 31 + root.label.charCodeAt(i)) % 360;
            return Qt.hsla(h / 360, 0.38, Appearance.m3colors.darkmode ? 0.30 : 0.82, 1);
        }
        StyledText {
            anchors.centerIn: parent
            text: root.label.length > 0 ? root.label[0].toUpperCase() : "?"
            font.pixelSize: root.size * 0.46
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
    }
    Image {
        id: image
        anchors.fill: parent
        anchors.margins: root.size * 0.1
        source: root.loaded !== "" ? Qt.resolvedUrl(root.loaded) : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        visible: status === Image.Ready
    }
}
