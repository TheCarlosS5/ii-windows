pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: the user's desktop (their Desktop folder plus the shared Public one), drawn by
// the shell in place of Explorer's icons. It reads the real folders and follows changes.
// Double click opens, right click offers open / show in folder / copy path.
Item {
    id: root

    property real topInset: Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight
    property real bottomInset: Config.options.bar.bottom ? Appearance.sizes.barHeight : 0
    property int iconSize: Config.options.background.widgets.desktopIcons.iconSize
    property int cellWidth: iconSize + 44
    property int cellHeight: iconSize + 52
    property string selectedPath: ""
    readonly property bool menuOpen: contextMenu.visible

    readonly property string userDesktop: decodeURIComponent(FileUtils.trimFileProtocol(StandardPaths.writableLocation(StandardPaths.DesktopLocation))).replace(/^\/(?=[A-Za-z]:\/)/, "")
    readonly property string publicDesktop: (Quickshell.env("PUBLIC") || "C:/Users/Public").replace(/\\/g, "/") + "/Desktop"

    function displayName(fileName) {
        // Windows hides the extension of shortcuts.
        return fileName.replace(/\.(lnk|url)$/i, "");
    }

    function iconFor(path) {
        // base64 of the UTF-8 path: safe inside an image:// URL whatever the file is called
        return Quickshell.iconPath("winfile:" + Qt.btoa(unescape(encodeURIComponent(path))), "text-x-generic");
    }

    function nativePath(path) {
        return path.replace(/\//g, "\\");
    }

    function open(path) {
        // ShellExecute receives a literal path: '#' and '%' are file-name characters,
        // not a URL fragment or escape sequence. No shell command string is involved.
        Quickshell.execDetached(["xdg-open", root.nativePath(path)]);
    }

    MouseArea {
        // Clicking empty desktop clears the selection and closes the menu.
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: {
            root.selectedPath = "";
            contextMenu.visible = false;
        }
    }

    Flow {
        id: grid
        flow: Flow.TopToBottom
        spacing: 4
        x: 12
        y: root.topInset + 12
        height: root.height - root.topInset - root.bottomInset - 24 - (Config.options.dock.enable ? Config.options.dock.height : 0)
        width: root.width / 2

        Repeater {
            model: FolderListModel {
                folder: StandardPaths.writableLocation(StandardPaths.DesktopLocation)
                showDirsFirst: true
                showDotAndDotDot: false
                showHidden: false
                sortField: FolderListModel.Name
            }
            delegate: desktopItem
        }
        Repeater {
            model: FolderListModel {
                folder: "file:///" + root.publicDesktop
                showDirsFirst: true
                showDotAndDotDot: false
                showHidden: false
                sortField: FolderListModel.Name
            }
            delegate: desktopItem
        }
    }

    Component {
        id: desktopItem

        Item {
            id: item
            required property string fileName
            required property string filePath
            readonly property bool selected: root.selectedPath === filePath
            width: root.cellWidth
            height: root.cellHeight

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: item.selected ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.15)
                     : mouse.containsMouse ? ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                     : "transparent"
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            Image {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
                width: root.iconSize
                height: root.iconSize
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                source: root.iconFor(item.filePath)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            StyledText {
                id: label
                anchors {
                    top: icon.bottom
                    topMargin: 4
                    left: parent.left
                    right: parent.right
                    leftMargin: 4
                    rightMargin: 4
                }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: item.selected ? 4 : 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: item.selected ? Appearance.colors.colOnPrimaryContainer : "white"
                text: root.displayName(item.fileName)
                style: item.selected ? Text.Normal : Text.Outline
                styleColor: ColorUtils.transparentize("black", 0.55)
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: event => {
                    root.selectedPath = item.filePath;
                    if (event.button === Qt.RightButton) {
                        const p = mapToItem(root, event.x, event.y);
                        contextMenu.target = item.filePath;
                        contextMenu.x = Math.min(p.x, root.width - contextMenu.width - 8);
                        contextMenu.y = Math.min(p.y, root.height - contextMenu.height - 8);
                        contextMenu.visible = true;
                    } else {
                        contextMenu.visible = false;
                    }
                }
                onDoubleClicked: event => {
                    if (event.button === Qt.LeftButton) root.open(item.filePath);
                }
            }
        }
    }

    Rectangle {
        id: contextMenu
        property string target: ""
        visible: false
        z: 10
        width: 220
        height: menuColumn.implicitHeight + 12
        radius: Appearance.rounding.normal
        // Layer1 is a translucent overlay intended to sit on Layer0, not wallpaper.
        color: Appearance.colors.colLayer0

        StyledDropShadow {
            target: contextMenu
        }

        Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Repeater {
                model: [
                    { icon: "open_in_new", text: Translation.tr("Open"), action: () => root.open(contextMenu.target) },
                    { icon: "folder_open", text: Translation.tr("Show in folder"),
                      action: () => Quickshell.execDetached(["ii-shim", "reveal", root.nativePath(contextMenu.target)]) },
                    { icon: "content_copy", text: Translation.tr("Copy path"),
                      action: () => Quickshell.clipboardText = root.nativePath(contextMenu.target) },
                ]
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    width: menuColumn.width
                    height: 40
                    radius: Appearance.rounding.small
                    color: entryMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                    MaterialSymbol {
                        id: entryIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        anchors.left: entryIcon.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text
                        color: Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            contextMenu.visible = false;
                            entry.modelData.action();
                        }
                    }
                }
            }
        }
    }
}
