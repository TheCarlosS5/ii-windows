pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: one app of the store: icon, name, a line about it and what can be done with it right now.
Rectangle {
    id: root
    property string appId: ""
    property string name: ""
    property string description: ""
    property string site: ""
    property string version: ""

    readonly property var opState: Winget.stateOf(appId)
    readonly property bool isInstalled: Winget.isInstalled(appId)
    readonly property var upgradeInfo: Winget.upgradeFor(appId)
    readonly property bool running: opState && (opState.state === "queued" || opState.state === "running")
    readonly property bool failed: opState && opState.state === "error"

    implicitHeight: 92
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1

    RowLayout {
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 14

        StoreIcon {
            Layout.alignment: Qt.AlignVCenter
            site: root.site
            label: root.name
            size: 56
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.name
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: root.description !== "" ? root.description : root.appId
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledProgressBar {
                Layout.fillWidth: true
                visible: root.opState && root.opState.state === "running" && root.opState.percent >= 0
                Layout.topMargin: 2
                valueBarHeight: 4
                value: root.opState ? Math.max(0, root.opState.percent) / 100 : 0
            }
            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: root.opState && root.opState.state === "running" && root.opState.percent < 0
                Layout.topMargin: 2
            }
        }

        // What can be done.
        RippleButton {
            id: action
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 38
            implicitWidth: label.implicitWidth + 32
            buttonRadius: Appearance.rounding.full
            readonly property bool primary: !root.isInstalled || root.upgradeInfo !== null || root.failed
            colBackground: root.failed ? Appearance.m3colors.m3errorContainer : primary ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            colBackgroundHover: root.failed ? Appearance.m3colors.m3errorContainer : primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
            onClicked: {
                if (root.running) return;
                if (root.failed) { const op = root.opState.op; Winget.dismiss(root.appId); Winget.enqueue(op, root.appId, root.name); }
                else if (root.upgradeInfo) Winget.upgrade(root.appId, root.name);
                else if (!root.isInstalled) Winget.install(root.appId, root.name);
                else root.openApp();
            }
            contentItem: StyledText {
                id: label
                anchors.centerIn: parent
                font.weight: Font.Medium
                color: root.failed ? Appearance.m3colors.m3onErrorContainer : action.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                text: {
                    if (root.running) {
                        const op = root.opState.op;
                        const w = op === "install" ? Translation.tr("Installing") : op === "upgrade" ? Translation.tr("Updating") : Translation.tr("Uninstalling");
                        return root.opState.state === "queued" ? Translation.tr("Queued") : (root.opState.percent >= 0 ? `${w} ${root.opState.percent}%` : w + "…");
                    }
                    if (root.failed) return Translation.tr("Try again");
                    if (root.upgradeInfo) return Translation.tr("Update");
                    if (root.isInstalled) return Translation.tr("Open");
                    return Translation.tr("Install");
                }
            }
        }
        RippleButton {
            visible: root.isInstalled && !root.running
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 38
            implicitHeight: 38
            buttonRadius: Appearance.rounding.full
            onClicked: Winget.uninstall(root.appId, root.name)
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "delete"
                iconSize: 20
                color: Appearance.colors.colOnLayer1
            }
            StyledToolTip {
                text: Translation.tr("Uninstall")
            }
        }
    }

    // "Open": the Start menu has the app under its name.
    function openApp() {
        const entry = AppSearch.list.find(a => a.name.toLowerCase() === root.name.toLowerCase())
            ?? AppSearch.list.find(a => a.name.toLowerCase().includes(root.name.toLowerCase().split(" ")[0]));
        if (entry) entry.execute();
    }
}
