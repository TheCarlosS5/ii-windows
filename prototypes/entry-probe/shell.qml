// Prints how a few app ids resolve in the app index (ids, names, icons), then exits.
import QtQuick
import Quickshell

ShellRoot {
    Component.onCompleted: console.log("probe start", DesktopEntries.applications.values.length)
    Timer {
        interval: 25000
        running: true
        onTriggered: {
            for (const id of ["MSEdge", "msedge", "Microsoft.Windows.Explorer", "microsoft.windows.explorer",
                              "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", "explorer"]) {
                const e = DesktopEntries.byId(id);
                const h = DesktopEntries.heuristicLookup(id);
                console.log("probe", id, "byId:", e ? e.id + " icon=" + e.icon : "none", "| heuristic:", h ? h.id : "none");
            }
            const all = DesktopEntries.applications.values;
            console.log("probe count", all.length);
            for (const e of all) if (/edge|terminal|explorer/i.test(e.name + e.id)) console.log("probe entry", e.id, "|", e.name);
            Qt.quit();
        }
    }
}
