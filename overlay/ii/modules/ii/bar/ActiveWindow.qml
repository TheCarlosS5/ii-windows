import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ii-windows: minimized windows are not "the window on this desktop" (the bar said the name of a
// minimized Terminal over an empty desktop), and the app line shows a friendly name, never a raw
// AppUserModelID like "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App".
Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    readonly property int workspaceId: HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id ?? -1
    property var biggestWindow: {
        const visible = HyprlandData.windowList.filter(w => w.workspace.id == root.workspaceId && !w.hidden);
        return visible.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }
    readonly property bool showingActive: root.focusingThisMonitor && (root.activeWindow?.activated ?? false) && root.biggestWindow

    function friendlyName(id) {
        if (!id || id.length === 0) return "";
        const entry = DesktopEntries.heuristicLookup(id);
        if (entry?.name) return entry.name;
        // AUMID / exe fallback: "Publisher.App_hash!Entry" -> "App", "C:\...\foo.exe" -> "foo"
        let s = id.replace(/!.*$/, "").replace(/_[a-z0-9]{13}$/i, "");
        s = s.split(/[\\/]/).pop().replace(/\.exe$/i, "");
        const parts = s.split(".");
        s = parts[parts.length - 1] || s;
        return s.replace(/([a-z])([A-Z])/g, "$1 $2");
    }

    implicitWidth: colLayout.implicitWidth

    ColumnLayout {
        id: colLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: -4

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.showingActive ? root.friendlyName(root.activeWindow?.appId) :
                root.biggestWindow ? root.friendlyName(root.biggestWindow.class) : Translation.tr("Desktop")
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            text: root.showingActive ? root.activeWindow?.title :
                (root.biggestWindow?.title) ?? ((monitor?.activeWorkspace?.name ?? "1") === `${monitor?.activeWorkspace?.id ?? 1}` ? Translation.tr("Desktop %1").arg(monitor?.activeWorkspace?.id ?? 1) : monitor.activeWorkspace.name)
        }

    }

}
