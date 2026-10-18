pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: what can be done with one app of the store right now (install / open / update / try again, with the
// progress of a running job) and, when winget can remove it, the uninstall button. Until `winget list` has
// answered nobody knows what is installed: a quiet placeholder is shown instead of a wrong "Install".
RowLayout {
    id: root
    property string appId: ""
    property string name: ""
    property var aka: []
    property bool compact: false // tiles: one button, no uninstall
    spacing: 4

    readonly property var opState: Winget.stateOf(appId)
    readonly property var installedRow: Winget.installedRow(appId, name, aka)
    readonly property bool isInstalled: installedRow !== null
    readonly property var upgradeInfo: Winget.upgradeFor(appId)
    readonly property bool running: opState !== null && (opState.state === "queued" || opState.state === "running")
    readonly property bool failed: opState !== null && opState.state === "error"
    readonly property bool known: Winget.listedOnce || running || failed
    readonly property bool primary: !isInstalled || upgradeInfo !== null || failed

    RippleButton {
        id: action
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: root.compact ? 34 : 40
        implicitWidth: Math.max(root.compact ? 92 : 112, label.implicitWidth + 32)
        buttonRadius: Appearance.rounding.full
        enabled: root.known && !(root.running && root.opState.state === "queued")
        colBackground: !root.known ? Appearance.colors.colLayer2 : root.failed ? Appearance.m3colors.m3errorContainer : root.primary ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: root.failed ? Appearance.m3colors.m3errorContainer : root.primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        onClicked: {
            if (root.running) return;
            if (root.failed) {
                const op = root.opState.op;
                Winget.dismiss(root.appId);
                Winget.enqueue(op, root.appId, root.name);
            } else if (root.upgradeInfo) Winget.upgrade(root.appId, root.name);
            else if (!root.isInstalled) Winget.install(root.appId, root.name);
            else root.openApp();
        }
        // The progress of a running job fills the button from the left.
        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            visible: root.running && root.opState.percent >= 0
            width: parent.width * Math.max(0, root.opState?.percent ?? 0) / 100
            radius: height / 2
            color: Qt.alpha(Appearance.colors.colOnPrimary, 0.22)
            Behavior on width {
                NumberAnimation { duration: 250 * Appearance.motionFactor; easing.type: Easing.OutCubic }
            }
        }
        contentItem: Item {
            implicitWidth: actionRow.implicitWidth
            implicitHeight: actionRow.implicitHeight
            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 6
                MaterialLoadingIndicator {
                    visible: root.running && root.opState.percent < 0 || !root.known
                    loading: visible
                    implicitSize: 20
                    color: "transparent"
                }
                StyledText {
                    id: label
                    font.weight: Font.Medium
                    color: !root.known ? Appearance.colors.colSubtext : root.failed ? Appearance.m3colors.m3onErrorContainer : root.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    text: {
                        if (!root.known) return "";
                        if (root.running) {
                            const op = root.opState.op;
                            const w = op === "install" ? Translation.tr("Installing") : op === "upgrade" ? Translation.tr("Updating") : Translation.tr("Uninstalling");
                            return root.opState.state === "queued" ? Translation.tr("Queued") : (root.opState.percent >= 0 ? `${root.opState.percent}%` : w);
                        }
                        if (root.failed) return Translation.tr("Try again");
                        if (root.upgradeInfo) return Translation.tr("Update");
                        if (root.isInstalled) return Translation.tr("Open");
                        return Translation.tr("Install");
                    }
                }
            }
        }
        StyledToolTip {
            text: root.failed ? (root.opState?.message ?? "") : ""
            extraVisibleCondition: root.failed && (root.opState?.message ?? "") !== ""
        }
    }
    RippleButton {
        // Winget can only remove what its list shows (not an app that is just in the Start menu).
        // Hidden, it keeps its room: the main buttons of a list line up.
        readonly property bool usable: root.isInstalled && !root.running && (root.installedRow?.id ?? "") !== ""
        visible: !root.compact
        opacity: usable ? 1 : 0
        enabled: usable
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        onClicked: Winget.uninstall(root.appId, root.name, root.installedRow.id)
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

    // "Open": the Start menu has the app under its name (or the name winget lists it under).
    function openApp() {
        const names = [root.name, root.installedRow?.name ?? ""].concat(root.aka ?? []).filter(n => n !== "").map(n => n.toLowerCase());
        let entry = null;
        for (const n of names) {
            entry = AppSearch.list.find(a => a.name.toLowerCase() === n);
            if (entry) break;
        }
        if (!entry) {
            const key = Winget.nameKey(root.name);
            entry = AppSearch.list.find(a => Winget.nameKey(a.name) === key)
                ?? AppSearch.list.find(a => a.name.toLowerCase().includes(root.name.toLowerCase().split(" ")[0]));
        }
        if (entry) entry.execute();
    }
}
