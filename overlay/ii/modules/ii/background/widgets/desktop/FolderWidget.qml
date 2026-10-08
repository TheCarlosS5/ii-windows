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
import qs.modules.ii.background.widgets

// ii-windows: a card on the desktop with the newest files of a real folder (Downloads unless
// background.widgets.folder.path says otherwise). Click opens, right click shows the file in
// Explorer, the header button opens the folder. Drag the card to move it, like the clock.
AbstractBackgroundWidget {
    id: root

    configEntryName: "folder"
    implicitWidth: 320
    implicitHeight: card.implicitHeight

    readonly property url folderUrl: configEntry.path?.length > 0
        ? "file:///" + configEntry.path.replace(/\\/g, "/")
        : StandardPaths.writableLocation(StandardPaths.DownloadLocation)
    readonly property string folderPath: decodeURIComponent(FileUtils.trimFileProtocol(folderUrl.toString())).replace(/^\/(?=[A-Za-z]:\/)/, "")
    readonly property string folderName: folderPath.split("/").filter(s => s.length > 0).pop() ?? folderPath
    readonly property int maxItems: configEntry.maxItems ?? 7

    function nativePath(path) {
        return path.replace(/\//g, "\\");
    }
    function iconFor(path) {
        return Quickshell.iconPath("winfile:" + Qt.btoa(unescape(encodeURIComponent(path))), "text-x-generic");
    }
    function relativeTime(date) {
        const minutes = Math.floor((Date.now() - date.getTime()) / 60000);
        if (minutes < 1) return Translation.tr("Just now");
        if (minutes < 60) return Translation.tr("%1 min ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return Translation.tr("%1 h ago").arg(hours);
        const days = Math.floor(hours / 24);
        if (days < 7) return Translation.tr("%1 d ago").arg(days);
        return Qt.formatDate(date, Qt.DefaultLocaleShortDate);
    }

    FolderListModel {
        id: folderModel
        folder: root.folderUrl
        showDirs: true
        showDirsFirst: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Time
    }

    StyledDropShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: column.implicitHeight + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0

        Column {
            id: column
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 4

            Item { // Header: folder name + open button
                width: parent.width
                height: 40

                MaterialShapeWrappedMaterialSymbol {
                    id: headerIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "folder_open"
                    iconSize: Appearance.font.pixelSize.larger
                }
                StyledText {
                    anchors {
                        left: headerIcon.right
                        leftMargin: 10
                        right: openButton.left
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer0
                    text: root.folderName
                }
                RippleButton {
                    id: openButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    onClicked: Quickshell.execDetached(["xdg-open", root.nativePath(root.folderPath)])
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            StyledText {
                visible: rows.count === 0
                width: parent.width
                height: 48
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Appearance.colors.colSubtext
                text: Translation.tr("Nothing here yet")
            }

            Repeater {
                id: rows
                model: folderModel
                delegate: Rectangle {
                    id: row
                    required property int index
                    required property string fileName
                    required property string filePath
                    required property date fileModified
                    visible: index < root.maxItems
                    width: column.width
                    height: visible ? 44 : 0
                    radius: Appearance.rounding.small
                    color: rowMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                    Image {
                        id: rowIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        sourceSize: Qt.size(56, 56)
                        source: row.visible ? root.iconFor(row.filePath) : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Column {
                        anchors {
                            left: rowIcon.right
                            leftMargin: 10
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            width: parent.width
                            elide: Text.ElideMiddle
                            color: Appearance.colors.colOnLayer0
                            text: row.fileName
                        }
                        StyledText {
                            width: parent.width
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root.relativeTime(row.fileModified)
                        }
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: event => {
                            if (event.button === Qt.RightButton)
                                Quickshell.execDetached(["ii-shim", "reveal", root.nativePath(row.filePath)]);
                            else
                                Quickshell.execDetached(["xdg-open", root.nativePath(row.filePath)]);
                        }
                    }
                }
            }
        }
    }
}
