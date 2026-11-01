import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, B3/B7): Configuración > Actualizaciones. The state comes from services/IiUpdates.qml;
// every button asks ii-host, which runs ii-shim update with its rules (never during a game...).
ContentPage {
    id: page
    forceWidth: true

    // The installation's current.txt: which version is active and which one it can go back to.
    property string previousVersion: ""
    property string activeVersion: ""
    FileView {
        id: currentFile
        path: Quickshell.shellPath("../../../current.txt")
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const text = currentFile.text();
            page.previousVersion = (/^previous=(.*)$/m.exec(text)?.[1] ?? "").trim();
            page.activeVersion = (/^active=(.*)$/m.exec(text)?.[1] ?? "").trim();
        }
    }

    ContentSection {
        icon: "system_update"
        title: Translation.tr("Updates")

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            MaterialShapeWrappedMaterialSymbol {
                implicitWidth: 64
                implicitHeight: 64
                shape: MaterialShape.Shape.Cookie9Sided
                text: IiUpdates.ready ? "restart_alt" : IiUpdates.attention ? "download" : IiUpdates.status === "error" ? "error" : "verified"
                iconSize: 30
                padding: 14
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: IiUpdates.statusText()
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: IiUpdates.status === "error" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: {
                        const parts = [];
                        if (page.activeVersion.length > 0) parts.push(Translation.tr("Installed: %1").arg(page.activeVersion));
                        if (IiUpdates.lastCheck.length > 0) parts.push(Translation.tr("Last check: %1").arg(Qt.formatDateTime(new Date(IiUpdates.lastCheck), "dd/MM HH:mm")));
                        if (IiUpdates.attention && IiUpdates.sizeMb > 0) parts.push(Translation.tr("%1 MB").arg(IiUpdates.sizeMb));
                        return parts.join(" · ");
                    }
                }
            }
        }

        StyledProgressBar {
            visible: IiUpdates.status === "downloading"
            Layout.fillWidth: true
            value: IiUpdates.progress
        }

        StyledText {
            visible: IiUpdates.critical && IiUpdates.attention
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colPrimary
            text: Translation.tr("Recommended: it fixes important errors.")
        }
        StyledText {
            visible: IiUpdates.tooOld && IiUpdates.attention
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
            text: Translation.tr("From your version this one has to be installed by hand: download the Setup from GitHub.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                visible: !IiUpdates.busy && !IiUpdates.attention
                materialIcon: "refresh"
                mainText: Translation.tr("Check now")
                onClicked: IiUpdates.check()
            }
            RippleButtonWithIcon {
                visible: !IiUpdates.busy && IiUpdates.attention && !IiUpdates.ready && !IiUpdates.tooOld
                materialIcon: "download"
                mainText: Translation.tr("Download and install")
                onClicked: IiUpdates.install()
            }
            RippleButtonWithIcon {
                visible: IiUpdates.ready
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restart ii now")
                onClicked: IiUpdates.restartNow()
            }
            RippleButtonWithIcon {
                visible: IiUpdates.attention && !IiUpdates.ready && !IiUpdates.busy
                materialIcon: "block"
                mainText: Translation.tr("Skip this version")
                onClicked: IiUpdates.skip()
            }
            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("See on GitHub")
                onClicked: Qt.openUrlExternally(IiUpdates.releaseUrl)
            }
        }
    }

    ContentSection {
        visible: IiUpdates.attention && IiUpdates.notes.length > 0
        icon: "new_releases"
        title: Translation.tr("What's new in %1").arg(IiUpdates.latestVersion)
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            text: IiUpdates.notes
            color: Appearance.colors.colOnLayer1
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    ContentSection { // B3.6: the notes of the version in use, to read again after the notice
        visible: !(IiUpdates.attention && IiUpdates.notes.length > 0) && IiUpdates.installedNotes.length > 0
        icon: "auto_awesome"
        title: Translation.tr("What's new in this version (%1)").arg(IiUpdates.installedVersion)
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            text: IiUpdates.installedNotes
            color: Appearance.colors.colOnLayer1
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Options")

        ConfigSwitch {
            buttonIcon: "update"
            text: Translation.tr("Look for updates by itself (never during a game)")
            checked: Config.options.iiUpdates.autoCheck
            onCheckedChanged: Config.options.iiUpdates.autoCheck = checked
        }
        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Download them by itself, only on Wi-Fi or cable")
            checked: Config.options.iiUpdates.autoDownload
            onCheckedChanged: Config.options.iiUpdates.autoDownload = checked
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Tell me with a notification (otherwise only the dot in the bar)")
            checked: Config.options.iiUpdates.notify
            onCheckedChanged: Config.options.iiUpdates.notify = checked
        }
        ContentSubsection {
            title: Translation.tr("Channel")
            tooltip: Translation.tr("Beta gets test versions first, for the people who try them")
            ConfigSelectionArray {
                currentValue: Config.options.iiUpdates.channel
                onSelected: newValue => Config.options.iiUpdates.channel = newValue
                options: [
                    { displayName: Translation.tr("Stable"), icon: "verified", value: "stable" },
                    { displayName: Translation.tr("Beta"), icon: "science", value: "beta" }
                ]
            }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("Only versions signed by ii-windows are installed, next to the one you have: if the new one does not start, ii goes back by itself. The only thing sent is a question to GitHub.")
        }
    }

    ContentSection {
        visible: page.previousVersion.length > 0 && page.previousVersion !== "none"
        icon: "history"
        title: Translation.tr("Previous version")
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer1
            text: Translation.tr("%1 is still on this PC. Going back restarts ii with it.").arg(page.previousVersion)
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "undo"
                mainText: Translation.tr("Go back to %1").arg(page.previousVersion)
                onClicked: IiUpdates.rollback()
            }
        }
    }
}
