import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, B3/B7): Configuración > Actualizaciones. The state comes from services/Updates.qml;
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
                text: Updates.ready ? "restart_alt" : Updates.attention ? "download" : Updates.status === "error" ? "error" : "verified"
                iconSize: 30
                padding: 14
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Updates.statusText()
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Updates.status === "error" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: {
                        const parts = [];
                        if (page.activeVersion.length > 0) parts.push(Translation.tr("Installed: %1").arg(page.activeVersion));
                        if (Updates.lastCheck.length > 0) parts.push(Translation.tr("Last check: %1").arg(Qt.formatDateTime(new Date(Updates.lastCheck), "dd/MM HH:mm")));
                        if (Updates.attention && Updates.sizeMb > 0) parts.push(Translation.tr("%1 MB").arg(Updates.sizeMb));
                        return parts.join(" · ");
                    }
                }
            }
        }

        StyledProgressBar {
            visible: Updates.status === "downloading"
            Layout.fillWidth: true
            value: Updates.progress
        }

        StyledText {
            visible: Updates.critical && Updates.attention
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colPrimary
            text: Translation.tr("Recommended: it fixes important errors.")
        }
        StyledText {
            visible: Updates.tooOld && Updates.attention
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
            text: Translation.tr("From your version this one has to be installed by hand: download the Setup from GitHub.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                visible: !Updates.busy && !Updates.attention
                materialIcon: "refresh"
                mainText: Translation.tr("Check now")
                onClicked: Updates.check()
            }
            RippleButtonWithIcon {
                visible: !Updates.busy && Updates.attention && !Updates.ready && !Updates.tooOld
                materialIcon: "download"
                mainText: Translation.tr("Download and install")
                onClicked: Updates.install()
            }
            RippleButtonWithIcon {
                visible: Updates.ready
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restart ii now")
                onClicked: Updates.restartNow()
            }
            RippleButtonWithIcon {
                visible: Updates.attention && !Updates.ready && !Updates.busy
                materialIcon: "block"
                mainText: Translation.tr("Skip this version")
                onClicked: Updates.skip()
            }
            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("See on GitHub")
                onClicked: Qt.openUrlExternally(Updates.releaseUrl)
            }
        }
    }

    ContentSection {
        visible: Updates.attention && Updates.notes.length > 0
        icon: "new_releases"
        title: Translation.tr("What's new in %1").arg(Updates.latestVersion)
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            text: Updates.notes
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
            checked: Config.options.updates.autoCheck
            onCheckedChanged: Config.options.updates.autoCheck = checked
        }
        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Download them by itself, only on Wi-Fi or cable")
            checked: Config.options.updates.autoDownload
            onCheckedChanged: Config.options.updates.autoDownload = checked
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Tell me with a notification (otherwise only the dot in the bar)")
            checked: Config.options.updates.notify
            onCheckedChanged: Config.options.updates.notify = checked
        }
        ContentSubsection {
            title: Translation.tr("Channel")
            tooltip: Translation.tr("Beta gets test versions first, for the people who try them")
            ConfigSelectionArray {
                currentValue: Config.options.updates.channel
                onSelected: newValue => Config.options.updates.channel = newValue
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
                onClicked: Updates.rollback()
            }
        }
    }
}
