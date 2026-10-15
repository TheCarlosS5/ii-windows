pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: Settings > About. What this is, which version, who made it and what it stands on.
ContentPage {
    id: page
    forceWidth: true

    property string version: ""
    property string built: ""
    property string windowsName: ""
    property string commit: ""

    FileView {
        path: Quickshell.shellPath("../build-info.json")
        onLoaded: {
            try {
                const info = JSON.parse(text().replace(/^﻿/, ""));
                page.version = info.version ?? page.version;
                page.built = (info.built ?? "").slice(0, 10);
                page.commit = (info.commits?.ii?.head ?? "").slice(0, 7);
            } catch (e) {}
        }
    }
    Process {
        running: true
        command: ["ii-shim", "system-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(text);
                    page.windowsName = `${info.name} (${info.build})`;
                } catch (e) {}
            }
        }
    }

    // A person or project: avatar, name, what they did, link.
    component Credit: Rectangle {
        id: credit
        property string name
        property string role
        property string link: ""
        property string linkLabel: ""
        property string photo: ""
        property string symbol: "person"
        property var shape: MaterialShape.Shape.Cookie9Sided
        Layout.fillWidth: true
        implicitHeight: row.implicitHeight + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        RowLayout {
            id: row
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 14
            }
            spacing: 14
            Item {
                implicitWidth: 64
                implicitHeight: 64
                Image {
                    id: photoImage
                    anchors.fill: parent
                    visible: false
                    source: credit.photo
                    sourceSize: Qt.size(160, 160)
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }
                Rectangle {
                    id: photoMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    visible: credit.photo !== "" && photoImage.status === Image.Ready
                    source: photoImage
                    maskSource: photoMask
                }
                MaterialShapeWrappedMaterialSymbol {
                    anchors.fill: parent
                    visible: credit.photo === "" || photoImage.status !== Image.Ready
                    shape: credit.shape
                    text: credit.symbol
                    iconSize: 30
                    padding: 14
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: credit.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: credit.role
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButtonWithIcon {
                visible: credit.link !== ""
                materialIcon: "open_in_new"
                mainText: credit.linkLabel
                onClicked: Qt.openUrlExternally(credit.link)
            }
        }
    }

    ContentSection {
        icon: "info"
        title: Translation.tr("ii-windows")

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 18
            Rectangle {
                implicitWidth: 84
                implicitHeight: 84
                radius: 28
                color: Appearance.colors.colPrimaryContainer
                StyledText {
                    anchors.centerIn: parent
                    text: "ii"
                    font.pixelSize: 44
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("ii-windows")
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("A desktop environment for programmers on Windows 11: the Illogical Impulse shell (Material 3 Expressive) with ideas from macOS, GNOME and Hyprland.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 6
                    Repeater {
                        model: [
                            { icon: "sell", text: page.version ? Translation.tr("Version %1").arg(page.version) : Translation.tr("Development build") },
                            { icon: "calendar_month", text: page.built ? Translation.tr("Built %1").arg(page.built) : "" },
                            { icon: "commit", text: page.commit },
                            { icon: "desktop_windows", text: page.windowsName }
                        ].filter(c => c.text !== "")
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            height: 28
                            width: chipRow.implicitWidth + 20
                            radius: 14
                            color: Appearance.colors.colSecondaryContainer
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData.text
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "tour"
                mainText: Translation.tr("Show the tour")
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "tour", "open"])
            }
            RippleButtonWithIcon {
                materialIcon: "keyboard"
                mainText: Translation.tr("Shortcuts")
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "cheatsheet", "toggle"])
            }
            RippleButtonWithIcon {
                materialIcon: "system_update_alt"
                mainText: Translation.tr("Check for updates")
                onClicked: Qt.openUrlExternally("https://github.com/TheCarlosS5/ii-windows/releases/latest")
            }
            RippleButtonWithIcon {
                materialIcon: "bug_report"
                mainText: Translation.tr("Report a problem")
                onClicked: Qt.openUrlExternally("https://github.com/TheCarlosS5/ii-windows/issues/new/choose")
            }
            RippleButtonWithIcon {
                materialIcon: "folder_open"
                mainText: Translation.tr("Open the logs folder")
                onClicked: Quickshell.execDetached(["explorer.exe", Quickshell.env("LOCALAPPDATA") + "\\ii-windows"])
            }
        }
    }

    ContentSection {
        icon: "groups"
        title: Translation.tr("Credits")

        Credit {
            name: "Carlos (TheCarlosS5)"
            role: Translation.tr("Idea, direction, testing and everyday use. ii-windows exists because of the question \"can this be on Windows?\".")
            photo: Qt.resolvedUrl("../../assets/images/about/carlos.jpg")
            link: "https://github.com/TheCarlosS5"
            linkLabel: "GitHub"
        }
        Credit {
            name: "Claude (Anthropic)"
            role: Translation.tr("AI that wrote the Windows port: the Quickshell backend, the host, the dock, the installer and the fixes, working together with Carlos.")
            symbol: "auto_awesome"
            shape: MaterialShape.Shape.SoftBurst
            link: "https://claude.com"
            linkLabel: "claude.com"
        }
        Credit {
            name: "end-4"
            role: Translation.tr("Creator of Illogical Impulse (dots-hyprland), the shell this is built on, and its contributors.")
            symbol: "palette"
            shape: MaterialShape.Shape.Clover4Leaf
            link: "https://github.com/end-4/dots-hyprland"
            linkLabel: "dots-hyprland"
        }
        Credit {
            name: "Quickshell"
            role: Translation.tr("The toolkit ii is written with, by outfoxxed. The Windows backend lives in a fork of it.")
            symbol: "widgets"
            shape: MaterialShape.Shape.Pill
            link: "https://quickshell.org"
            linkLabel: "quickshell.org"
        }
    }

    ContentSection {
        icon: "favorite"
        title: Translation.tr("Built with")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("Qt 6 and QML · Material Color Utilities (Google) for the colours · Bibata cursors · fastfetch · JetBrains Mono Nerd Font · Google Sans Flex, Space Grotesk and Readex Pro · Breeze icons. ii-windows is free software under the GNU GPL 3; the Quickshell fork is LGPL. Thank you to everyone who published what this stands on.")
        }
    }
}
