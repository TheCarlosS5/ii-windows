//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// Plan 2026-10-31, E1: what the launcher shows for the queries in E1_QUERIES ("a|b|c"), one line each:
//   E1PROBE <query> => [type] name | [type] name ...   (the first 5 rows)
// tools/sandbox/tests/test-search-plus.ps1 copies it into the staged build/ii (it uses ii's services) and reads them.
ShellRoot {
    id: root
    property var queries: (Quickshell.env("E1_QUERIES") || "bloquear|5 km a millas|hora en tokio").split("|")
    property int i: 0
    Timer {
        interval: 1200
        running: Config.ready
        repeat: true
        onTriggered: {
            if (root.i > 0) {
                const q = root.queries[root.i - 1];
                const r = LauncherSearch.results.slice(0, 5).map(x => `[${x.type}] ${x.name}`);
                console.log("E1PROBE " + q + " => " + r.join(" | "));
            }
            if (root.i >= root.queries.length) {
                Qt.quit();
                return;
            }
            LauncherSearch.query = root.queries[root.i];
            root.i += 1;
        }
    }
}
