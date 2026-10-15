pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtCore
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: the user's desktop (their Desktop folder plus the shared Public one), drawn by
// the shell in place of Explorer's icons. It reads the real folders and follows changes.
//
// Icons sit on a grid and stay where they are dragged (saved in the state folder); new files
// take the first free cell. Click, Ctrl+click, Shift+click and a selection rectangle select;
// the keyboard works as in Explorer (arrows, Enter, F2, Delete, Ctrl+A/C/X/V, typing a name).
// Files can be dragged to other apps and folders, and dropped here from them. File actions
// (Recycle Bin, rename, paste, properties, Explorer's own context menu) go through Windows'
// shell via `ii-shim files`, so they behave exactly as in Explorer.
Item {
    id: root

    // The desktop menu (DesktopMenu.qml), shared with the wallpaper's right click.
    property var menu: null

    property real topInset: Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight
    property real bottomInset: Config.options.bar.bottom ? Appearance.sizes.barHeight : 0
    // ii-windows: icons follow the screen (a 720p laptop gets smaller ones than a 1440p monitor); the
    // size in Settings is used when "Adjust to the screen" is off.
    readonly property bool autoSize: Config.options.background.widgets.desktopIcons.autoSize ?? true
    property int iconSize: autoSize ? Math.max(36, Math.min(72, Math.round(48 * Math.max(1, root.height) / 1080 / 4) * 4))
                                    : Config.options.background.widgets.desktopIcons.iconSize
    property int cellWidth: iconSize + 44
    property int cellHeight: iconSize + 52

    readonly property real gridLeft: 12
    readonly property real gridTop: topInset + 12
    readonly property real gridBottom: height - bottomInset - 12 - (Config.options.dock.enable ? Config.options.dock.height : 0)
    readonly property int rows: Math.max(1, Math.floor((gridBottom - gridTop) / cellHeight))
    readonly property int columns: Math.max(1, Math.floor((width - 2 * gridLeft) / cellWidth))

    // Above the other widgets while an icon is being renamed (the field must get the clicks).
    readonly property bool raised: renamingPath !== ""

    // Everything on the desktop, in arrangement order: { path, name, isDir, modified, suffix }.
    property var entries: []
    // path -> cell index (column * rows + row); -1 when it does not fit (see the overflow tile).
    property var cells: ({})
    property int overflowCount: 0
    readonly property int overflowCell: overflowCount > 0 ? rows * columns - 1 : -1

    property var selection: ({})
    readonly property int selectionCount: Object.keys(selection).length
    property string currentPath: ""   // keyboard cursor
    property string anchorPath: ""    // start of Shift ranges
    property bool keyboardUsed: false
    property string renamingPath: ""
    property string pendingRename: "" // a new folder, renamed as soon as it shows up (key)
    property string pendingSelect: "" // a renamed file, selected once it shows up (key)
    property bool internalDrag: false
    property var dragPaths: []
    property string dragAnchor: ""

    // Saved: path -> [column, row], and how unsaved icons are ordered.
    property var positions: ({})
    property string sortMode: "name"

    readonly property string userDesktop: decodeURIComponent(FileUtils.trimFileProtocol(StandardPaths.writableLocation(StandardPaths.DesktopLocation))).replace(/^\/(?=[A-Za-z]:\/)/, "")
    readonly property string publicDesktop: (Quickshell.env("PUBLIC") || "C:/Users/Public").replace(/\\/g, "/") + "/Desktop"
    readonly property string layoutPath: FileUtils.trimFileProtocol(`${Directories.state}/user/desktop-layout.json`)

    onRowsChanged: relayoutTimer.restart()
    onColumnsChanged: relayoutTimer.restart()

    // --- helpers -------------------------------------------------------------------------

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

    function fileUrl(path) {
        // encodeURI leaves '#' and '?' alone; in a file name they are just characters.
        return "file:///" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    function pathFromUrl(url) {
        const text = url.toString();
        if (!text.startsWith("file:")) return "";
        return decodeURIComponent(text.replace(/^file:\/*/, "")).replace(/\\/g, "/").replace(/^(?![A-Za-z]:)/, "//");
    }

    function parentOf(path) {
        return path.substring(0, path.lastIndexOf("/"));
    }

    function baseName(path) {
        return path.substring(path.lastIndexOf("/") + 1);
    }

    function samePath(a, b) {
        return a.toLowerCase() === b.toLowerCase();
    }

    // Saved positions are keyed case-insensitively, as Windows compares paths: Qt and the shell
    // spell the drive letter differently ("c:/..." vs "C:/...").
    function key(path) {
        return path.toLowerCase();
    }

    // The model's spelling of a path from elsewhere (a drop, the shell), or "".
    function modelPath(path) {
        const k = root.key(path);
        return root.entries.find(e => root.key(e.path) === k)?.path ?? "";
    }

    function entryFor(path) {
        return root.entries.find(e => e.path === path);
    }

    function files(args) {
        Quickshell.execDetached(["ii-shim", "files", ...args]);
    }

    function cellX(cell) {
        return root.gridLeft + Math.floor(cell / root.rows) * root.cellWidth;
    }

    function cellY(cell) {
        return root.gridTop + (cell % root.rows) * root.cellHeight;
    }

    // Cell under a point (clamped to the grid).
    function cellAt(x, y) {
        const c = Math.max(0, Math.min(root.columns - 1, Math.floor((x - root.gridLeft) / root.cellWidth)));
        const r = Math.max(0, Math.min(root.rows - 1, Math.floor((y - root.gridTop) / root.cellHeight)));
        return c * root.rows + r;
    }

    // Items in grid order (top to bottom, then left to right), as the keyboard walks them.
    function visualOrder() {
        return root.entries.filter(e => (root.cells[e.path] ?? -1) >= 0)
            .sort((a, b) => root.cells[a.path] - root.cells[b.path]);
    }

    function selectedPaths() {
        return root.visualOrder().filter(e => root.selection[e.path]).map(e => e.path);
    }

    // --- layout --------------------------------------------------------------------------

    function collect(model) {
        const out = [];
        for (let i = 0; i < model.count; i++) {
            out.push({
                path: model.get(i, "filePath"),
                name: model.get(i, "fileName"),
                isDir: model.get(i, "fileIsDir"),
                modified: model.get(i, "fileModified"),
                suffix: (model.get(i, "fileSuffix") ?? "").toLowerCase(),
            });
        }
        return out;
    }

    function relayout() {
        const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
        const list = root.collect(userModel).concat(root.collect(publicModel));
        list.sort((a, b) => {
            if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
            if (root.sortMode === "date") return (b.modified - a.modified) || byName(a, b);
            if (root.sortMode === "type") return a.suffix.localeCompare(b.suffix) || byName(a, b);
            return byName(a, b);
        });

        const capacity = root.rows * root.columns;
        const taken = {};
        const cells = {};
        // With more icons than cells, the last cell shows "+N" (opens the folder).
        const overflowing = list.length > capacity;
        if (overflowing) taken[capacity - 1] = true;
        for (const e of list) {
            const p = root.positions[root.key(e.path)];
            if (!p || p[0] >= root.columns || p[1] >= root.rows) continue;
            const cell = p[0] * root.rows + p[1];
            if (taken[cell]) continue;
            taken[cell] = true;
            cells[e.path] = cell;
        }
        let next = 0;
        let overflow = 0;
        for (const e of list) {
            if (cells[e.path] !== undefined) continue;
            while (next < capacity && taken[next]) next++;
            if (next < capacity) {
                taken[next] = true;
                cells[e.path] = next;
            } else {
                cells[e.path] = -1;
                overflow++;
            }
        }

        root.entries = list;
        root.cells = cells;
        root.overflowCount = overflow;

        // Forget selected files that are gone.
        const present = {};
        for (const e of list) present[e.path] = true;
        const kept = {};
        for (const path in root.selection) if (present[path]) kept[path] = true;
        if (Object.keys(kept).length !== root.selectionCount) root.selection = kept;
        if (root.currentPath && !present[root.currentPath]) root.currentPath = "";
        // Files announced by a drop, a paste or a rename that have now arrived.
        const byKey = {};
        for (const e of list) byKey[root.key(e.path)] = e.path;
        let arrived = false;
        const pending = Object.assign({}, root.pendingPaths);
        for (const k in pending) if (byKey[k]) { delete pending[k]; arrived = true; }
        if (arrived) root.pendingPaths = pending;
        if (root.pendingSelect && byKey[root.pendingSelect]) {
            root.selectOnly(byKey[root.pendingSelect]);
            root.pendingSelect = "";
        }

        if (root.pendingRename && byKey[root.pendingRename]) {
            root.selectOnly(byKey[root.pendingRename]);
            root.renamingPath = byKey[root.pendingRename];
            root.pendingRename = "";
        }
    }

    function save() {
        // Only files that still exist; the file is tiny.
        const present = {};
        for (const e of root.entries) present[root.key(e.path)] = true;
        const kept = {};
        for (const k in root.positions) if (present[k] || root.pendingPaths[k]) kept[k] = root.positions[k];
        layoutFile.setText(JSON.stringify({ sort: root.sortMode, positions: kept }, null, 1));
    }

    // Paths announced by a drop or a paste that have not appeared yet: keep their spots.
    property var pendingPaths: ({})

    // Once anything is moved by hand, every icon keeps its current cell (like Explorer with
    // auto-arrange off), so new files never shuffle the others.
    function freezeLayout() {
        const positions = Object.assign({}, root.positions);
        for (const e of root.entries) {
            const cell = root.cells[e.path];
            if (cell >= 0) positions[root.key(e.path)] = [Math.floor(cell / root.rows), cell % root.rows];
        }
        return positions;
    }

    // Nearest free cell to `cell` (Chebyshev rings), or -1.
    function nearestFree(cell, taken) {
        const c0 = Math.floor(cell / root.rows);
        const r0 = cell % root.rows;
        const limit = Math.max(root.rows, root.columns);
        for (let d = 0; d <= limit; d++) {
            for (let dc = -d; dc <= d; dc++) {
                for (let dr = -d; dr <= d; dr++) {
                    if (Math.max(Math.abs(dc), Math.abs(dr)) !== d) continue;
                    const c = c0 + dc;
                    const r = r0 + dr;
                    if (c < 0 || r < 0 || c >= root.columns || r >= root.rows) continue;
                    const k = c * root.rows + r;
                    if (!taken[k] && k !== root.overflowCell) return k;
                }
            }
        }
        return -1;
    }

    // Moves `paths` so that `anchor` lands on `targetCell`, keeping their relative placement.
    function moveTo(paths, anchor, targetCell) {
        const from = root.cells[anchor];
        if (from === undefined || from < 0) return;
        const dc = Math.floor(targetCell / root.rows) - Math.floor(from / root.rows);
        const dr = targetCell % root.rows - from % root.rows;
        if (dc === 0 && dr === 0) return;

        const positions = root.freezeLayout();
        const moving = {};
        for (const p of paths) moving[p] = true;
        const taken = {};
        for (const e of root.entries) {
            const cell = root.cells[e.path];
            if (cell >= 0 && !moving[e.path]) taken[cell] = true;
        }
        for (const p of paths) {
            const cell = root.cells[p];
            if (cell === undefined || cell < 0) continue;
            const c = Math.max(0, Math.min(root.columns - 1, Math.floor(cell / root.rows) + dc));
            const r = Math.max(0, Math.min(root.rows - 1, cell % root.rows + dr));
            const free = root.nearestFree(c * root.rows + r, taken);
            if (free < 0) continue;
            taken[free] = true;
            positions[root.key(p)] = [Math.floor(free / root.rows), free % root.rows];
        }
        root.positions = positions;
        root.relayout();
        root.save();
    }

    // Reserves free cells from `cell` on for files that are about to appear (drop, paste).
    function reserve(paths, cell) {
        const positions = root.freezeLayout();
        const taken = {};
        for (const e of root.entries) if (root.cells[e.path] >= 0) taken[root.cells[e.path]] = true;
        const pending = Object.assign({}, root.pendingPaths);
        for (const p of paths) {
            const free = root.nearestFree(cell, taken);
            if (free < 0) break;
            taken[free] = true;
            positions[root.key(p)] = [Math.floor(free / root.rows), free % root.rows];
            pending[root.key(p)] = true;
        }
        root.positions = positions;
        root.pendingPaths = pending;
        root.save();
    }

    function sortBy(mode) {
        root.sortMode = mode;
        root.positions = {};
        root.relayout();
        root.save();
    }

    // --- selection -----------------------------------------------------------------------

    function selectOnly(path) {
        const s = {};
        if (path) s[path] = true;
        root.selection = s;
        root.currentPath = path;
        root.anchorPath = path;
    }

    function toggle(path) {
        const s = Object.assign({}, root.selection);
        if (s[path]) delete s[path];
        else s[path] = true;
        root.selection = s;
        root.currentPath = path;
        root.anchorPath = path;
    }

    function selectRange(from, to, additive) {
        const order = root.visualOrder().map(e => e.path);
        let a = order.indexOf(from);
        let b = order.indexOf(to);
        if (a < 0) a = b;
        const s = additive ? Object.assign({}, root.selection) : {};
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++) s[order[i]] = true;
        root.selection = s;
        root.currentPath = to;
    }

    function selectAll() {
        const s = {};
        for (const e of root.entries) s[e.path] = true;
        root.selection = s;
    }

    // --- actions -------------------------------------------------------------------------

    function open(paths) {
        // ShellExecute receives a literal path: '#' and '%' are file-name characters,
        // not a URL fragment or escape sequence. No shell command string is involved.
        for (const path of paths.slice(0, 16)) Quickshell.execDetached(["xdg-open", root.nativePath(path)]);
    }

    function recycle(paths, permanently) {
        if (paths.length > 0) root.files([permanently ? "delete" : "recycle", ...paths.map(root.nativePath)]);
    }

    function clip(mode, paths) {
        if (paths.length > 0) root.files(["clip", mode, ...paths.map(root.nativePath)]);
    }

    function paste() {
        root.files(["paste", root.nativePath(root.userDesktop)]);
    }

    function startRename(path) {
        if (!path) return;
        root.selectOnly(path);
        root.renamingPath = path;
    }

    function commitRename(path, text) {
        root.renamingPath = "";
        const entry = root.entryFor(path);
        let name = text.trim();
        if (!entry || name === "" || name === root.displayName(entry.name)) return;
        // Shortcuts are shown without their extension: keep it.
        const hidden = entry.name.match(/\.(lnk|url)$/i);
        if (hidden && !name.toLowerCase().endsWith(hidden[0].toLowerCase())) name += hidden[0];
        renameProc.oldPath = path;
        renameProc.command = ["ii-shim", "files", "rename", root.nativePath(path), name];
        renameProc.running = true;
    }

    function newFolderAt(x, y) {
        newFolderProc.cell = root.cellAt(x, y);
        newFolderProc.command = ["ii-shim", "files", "newfolder", root.nativePath(root.userDesktop), Translation.tr("New folder")];
        newFolderProc.running = true;
    }

    function explorerMenu(paths) {
        menuProc.command = ["ii-shim", "files", "menu", ...paths.map(root.nativePath)];
        menuProc.running = true;
    }

    // Right click on icons: ii's menu, with Explorer's full menu one entry away.
    function openItemMenu(x, y) {
        const paths = root.selectedPaths();
        if (paths.length === 0 || !root.menu) return;
        const single = paths.length === 1;
        const entry = single ? root.entryFor(paths[0]) : null;
        const entries = [
            { icon: "open_in_new", text: Translation.tr("Open"), action: () => root.open(paths) },
        ];
        if (single && !entry?.isDir)
            entries.push({ icon: "apps", text: Translation.tr("Open with…"), action: () => root.files(["openwith", root.nativePath(paths[0])]) });
        if (single)
            entries.push({ icon: "folder_open", text: Translation.tr("Show in folder"), action: () => Quickshell.execDetached(["ii-shim", "reveal", root.nativePath(paths[0])]) });
        entries.push(
            { separator: true },
            { icon: "content_cut", text: Translation.tr("Cut"), action: () => root.clip("cut", paths) },
            { icon: "content_copy", text: Translation.tr("Copy"), action: () => root.clip("copy", paths) },
            { icon: "link", text: Translation.tr("Copy path"), action: () => Quickshell.clipboardText = paths.map(root.nativePath).join("\n") },
        );
        if (single)
            entries.push({ icon: "edit", text: Translation.tr("Rename"), action: () => root.startRename(paths[0]) });
        entries.push(
            { icon: "delete", text: Translation.tr("Delete"), action: () => root.recycle(paths, false) },
            { separator: true },
            { icon: "info", text: Translation.tr("Properties"), action: () => root.files(["properties", ...paths.map(root.nativePath)]) },
            { icon: "more_horiz", text: Translation.tr("More options"), action: () => root.explorerMenu(paths) },
        );
        root.menu.popupEntries(x, y, entries);
    }

    // Added to the desktop menu (right click on the wallpaper).
    readonly property var desktopEntries: [
        { key: "new", icon: "create_new_folder", text: Translation.tr("New folder"),
          action: () => root.newFolderAt(root.menu.originX, root.menu.originY) },
        { key: "paste", icon: "content_paste", text: Translation.tr("Paste"), action: () => root.paste() },
        { key: "sort", icon: "sort", text: Translation.tr("Sort by"), choices: [
            { text: Translation.tr("Name"), checked: root.sortMode === "name", action: () => root.sortBy("name") },
            { text: Translation.tr("Date"), checked: root.sortMode === "date", action: () => root.sortBy("date") },
            { text: Translation.tr("Type"), checked: root.sortMode === "type", action: () => root.sortBy("type") },
        ] },
        { key: "terminal", icon: "terminal", text: Translation.tr("Open in Terminal"),
          action: () => Quickshell.execDetached(["wt", "-d", root.nativePath(root.userDesktop)]) },
        { key: "more", icon: "more_horiz", text: Translation.tr("More options"),
          action: () => { menuProc.command = ["ii-shim", "files", "menu", "--background", root.nativePath(root.userDesktop)]; menuProc.running = true; } },
    ]

    // --- keyboard ------------------------------------------------------------------------

    property string typed: ""
    Timer {
        id: typedReset
        interval: 900
        onTriggered: root.typed = ""
    }

    function step(dc, dr) {
        const order = root.visualOrder();
        if (order.length === 0) return "";
        const current = root.cells[root.currentPath];
        if (current === undefined || current < 0) return order[0].path;
        const c0 = Math.floor(current / root.rows);
        const r0 = current % root.rows;
        let best = "";
        let bestScore = Infinity;
        for (const e of order) {
            const cell = root.cells[e.path];
            const c = Math.floor(cell / root.rows);
            const r = cell % root.rows;
            const along = dc !== 0 ? (c - c0) * dc : (r - r0) * dr;
            const across = dc !== 0 ? Math.abs(r - r0) : Math.abs(c - c0);
            if (along <= 0) continue;
            const score = along + across * 4;
            if (score < bestScore) {
                bestScore = score;
                best = e.path;
            }
        }
        return best || root.currentPath;
    }

    function moveCursor(path, event) {
        if (!path) return;
        if (event.modifiers & Qt.ShiftModifier) root.selectRange(root.anchorPath || path, path, false);
        else if (event.modifiers & Qt.ControlModifier) root.currentPath = path;
        else root.selectOnly(path);
    }

    focus: true
    Keys.onPressed: event => {
        root.keyboardUsed = true;
        const ctrl = event.modifiers & Qt.ControlModifier;
        const paths = root.selectedPaths();
        switch (event.key) {
        case Qt.Key_Left: root.moveCursor(root.step(-1, 0), event); break;
        case Qt.Key_Right: root.moveCursor(root.step(1, 0), event); break;
        case Qt.Key_Up: root.moveCursor(root.step(0, -1), event); break;
        case Qt.Key_Down: root.moveCursor(root.step(0, 1), event); break;
        case Qt.Key_Home: root.moveCursor(root.visualOrder()[0]?.path ?? "", event); break;
        case Qt.Key_End: root.moveCursor(root.visualOrder().slice(-1)[0]?.path ?? "", event); break;
        case Qt.Key_Space:
            if (ctrl && root.currentPath) root.toggle(root.currentPath);
            else if (root.currentPath && !root.selection[root.currentPath]) root.selectOnly(root.currentPath);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (event.modifiers & Qt.AltModifier) root.files(["properties", ...paths.map(root.nativePath)]);
            else root.open(paths);
            break;
        case Qt.Key_Delete: root.recycle(paths, event.modifiers & Qt.ShiftModifier); break;
        case Qt.Key_F2: root.startRename(root.currentPath || paths[0]); break;
        case Qt.Key_F5: root.relayout(); break;
        case Qt.Key_Escape:
            if (root.menu?.menuOpen) root.menu.close();
            else root.selectOnly("");
            break;
        case Qt.Key_Menu:
        case Qt.Key_F10:
            if (event.key === Qt.Key_F10 && !(event.modifiers & Qt.ShiftModifier)) return;
            if (paths.length > 0) {
                const cell = root.cells[root.currentPath || paths[0]] ?? 0;
                root.openItemMenu(root.cellX(cell) + root.cellWidth / 2, root.cellY(cell) + root.cellHeight / 2);
            }
            break;
        default:
            if (ctrl && event.key === Qt.Key_A) root.selectAll();
            else if (ctrl && event.key === Qt.Key_C) root.clip("copy", paths);
            else if (ctrl && event.key === Qt.Key_X) root.clip("cut", paths);
            else if (ctrl && event.key === Qt.Key_V) root.paste();
            else if (!ctrl && event.text.length === 1 && event.text >= " ") {
                // Type the start of a name to jump to it.
                root.typed += event.text.toLowerCase();
                typedReset.restart();
                const order = root.visualOrder();
                const start = Math.max(0, order.findIndex(e => e.path === root.currentPath));
                for (let i = 0; i < order.length; i++) {
                    const e = order[(start + (root.typed.length === 1 ? i + 1 : i)) % order.length];
                    if (root.displayName(e.name).toLowerCase().startsWith(root.typed)) {
                        root.selectOnly(e.path);
                        break;
                    }
                }
            } else return;
        }
        event.accepted = true;
    }

    // --- processes and storage -----------------------------------------------------------

    FileView {
        id: layoutFile
        path: Qt.resolvedUrl(root.layoutPath)
        onLoaded: {
            try {
                const data = JSON.parse(layoutFile.text());
                root.positions = data.positions ?? {};
                root.sortMode = data.sort ?? "name";
            } catch (e) {
                console.warn("[DesktopIcons] Unreadable layout, starting fresh:", e);
            }
            relayoutTimer.restart();
        }
    }

    Process {
        id: renameProc
        property string oldPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const renamed = text.trim().replace(/\\/g, "/");
                if (!renamed) return;
                // The icon stays where it was (and so do the others).
                const positions = root.freezeLayout();
                const oldKey = root.key(renameProc.oldPath);
                if (positions[oldKey]) {
                    positions[root.key(renamed)] = positions[oldKey];
                    delete positions[oldKey];
                    const pending = Object.assign({}, root.pendingPaths);
                    pending[root.key(renamed)] = true;
                    root.pendingPaths = pending;
                    root.positions = positions;
                    root.save();
                }
                root.pendingSelect = root.key(renamed);
                relayoutTimer.restart();
            }
        }
    }

    Process {
        id: newFolderProc
        property int cell: 0
        stdout: StdioCollector {
            onStreamFinished: {
                const created = text.trim().replace(/\\/g, "/");
                if (!created) return;
                root.reserve([created], newFolderProc.cell);
                root.pendingRename = root.key(created);
                relayoutTimer.restart();
            }
        }
    }

    Process {
        id: menuProc
        stdout: StdioCollector {
            // Explorer's "Rename" needs a view that edits names in place: that is ours.
            onStreamFinished: if (text.trim() === "rename") root.startRename(root.currentPath)
        }
    }

    // FolderListModel fills in asynchronously and in bursts: lay out once things settle.
    Timer {
        id: relayoutTimer
        interval: 60
        onTriggered: root.relayout()
    }

    FolderListModel {
        id: userModel
        folder: StandardPaths.writableLocation(StandardPaths.DesktopLocation)
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: relayoutTimer.restart()
        onStatusChanged: relayoutTimer.restart()
    }
    FolderListModel {
        id: publicModel
        folder: "file:///" + root.publicDesktop
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: relayoutTimer.restart()
        onStatusChanged: relayoutTimer.restart()
    }

    // --- empty desktop: click, selection rectangle, drops --------------------------------

    MouseArea {
        id: background
        // Clicking empty desktop clears the selection; dragging draws a selection rectangle.
        // Right clicks go on to the desktop menu underneath (Background.qml).
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        property point origin
        property var base: ({})
        onPressed: event => {
            root.forceActiveFocus();
            root.keyboardUsed = false;
            origin = Qt.point(event.x, event.y);
            base = (event.modifiers & Qt.ControlModifier) ? Object.assign({}, root.selection) : {};
            root.selection = base;
            band.visible = false;
        }
        onPositionChanged: event => {
            if (!pressed) return;
            const x1 = Math.min(origin.x, event.x), x2 = Math.max(origin.x, event.x);
            const y1 = Math.min(origin.y, event.y), y2 = Math.max(origin.y, event.y);
            if (!band.visible && x2 - x1 < 4 && y2 - y1 < 4) return;
            band.visible = true;
            band.x = x1;
            band.y = y1;
            band.width = x2 - x1;
            band.height = y2 - y1;
            const s = Object.assign({}, base);
            for (const e of root.entries) {
                const cell = root.cells[e.path];
                if (cell < 0) continue;
                // The visible part of an icon: its picture and the first lines of its name.
                const ix = root.cellX(cell) + 6, iy = root.cellY(cell) + 6;
                if (ix < x2 && ix + root.cellWidth - 12 > x1 && iy < y2 && iy + root.cellHeight - 12 > y1) s[e.path] = true;
            }
            root.selection = s;
        }
        onReleased: band.visible = false
    }

    Rectangle {
        id: band
        visible: false
        z: 5
        radius: Appearance.rounding.verysmall
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.3)
    }

    DropArea {
        // Icons moved on the desktop, and files dropped here from Explorer or other apps.
        anchors.fill: parent
        onEntered: drag => {
            if (!root.internalDrag && !drag.hasUrls) drag.accepted = false;
        }
        onPositionChanged: drag => dropHint.cell = root.cellAt(drag.x - (root.internalDrag ? dragSource.Drag.hotSpot.x - root.cellWidth / 2 : 0),
                                                                  drag.y - (root.internalDrag ? dragSource.Drag.hotSpot.y - root.cellHeight / 2 : 0))
        onExited: dropHint.cell = -1
        onDropped: drop => {
            dropHint.cell = -1;
            if (root.internalDrag) {
                const target = root.cellAt(drop.x - dragSource.Drag.hotSpot.x + root.cellWidth / 2,
                                           drop.y - dragSource.Drag.hotSpot.y + root.cellHeight / 2);
                root.moveTo(root.dragPaths, root.dragAnchor, target);
                drop.accept(Qt.CopyAction);
                return;
            }
            const paths = Array.from(drop.urls).map(root.pathFromUrl).filter(p => p !== "");
            if (paths.length === 0) return;
            const cell = root.cellAt(drop.x, drop.y);
            const onDesktop = p => root.samePath(root.parentOf(p), root.userDesktop) || root.samePath(root.parentOf(p), root.publicDesktop);
            if (paths.every(onDesktop)) {
                // From an Explorer window showing the Desktop: just place them.
                const known = paths.map(root.modelPath).filter(p => p !== "");
                if (known.length > 0) root.moveTo(known, known[0], cell);
            } else {
                // Explorer's rule: move within the same drive, copy across drives.
                const sameDrive = paths[0].substring(0, 2).toLowerCase() === root.userDesktop.substring(0, 2).toLowerCase();
                root.reserve(paths.map(p => root.userDesktop + "/" + root.baseName(p)), cell);
                root.files([sameDrive ? "move" : "copy", root.nativePath(root.userDesktop), ...paths.map(root.nativePath)]);
            }
            // Report a copy: the source must never delete anything after our own move.
            drop.accept(Qt.CopyAction);
        }
    }

    Rectangle {
        id: dropHint
        property int cell: -1
        visible: cell >= 0
        x: root.cellX(Math.max(0, cell))
        y: root.cellY(Math.max(0, cell))
        width: root.cellWidth
        height: root.cellHeight
        radius: Appearance.rounding.normal
        color: "transparent"
        border.width: 2
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
    }

    // Carries the drag: a system drag, so files can also go to Explorer, browsers, chats...
    Item {
        id: dragSource
        Drag.dragType: Drag.None
    }

    function startDrag(item, hotSpot) {
        if (!root.selection[item.filePath]) root.selectOnly(item.filePath);
        const paths = root.selectedPaths();
        root.dragPaths = paths;
        root.dragAnchor = item.filePath;
        dragSource.Drag.mimeData = { "text/uri-list": paths.map(root.fileUrl).join("\r\n") + "\r\n" };
        dragSource.Drag.imageSource = item.dragImage;
        dragSource.Drag.hotSpot = hotSpot;
        root.internalDrag = true;
        // startDrag() only works on an active Drag; it blocks until the drop.
        dragSource.Drag.active = true;
        dragSource.Drag.startDrag(Qt.CopyAction | Qt.MoveAction | Qt.LinkAction);
        dragSource.Drag.active = false;
        root.internalDrag = false;
        dropHint.cell = -1;
    }

    // --- icons ---------------------------------------------------------------------------

    Repeater {
        model: userModel
        delegate: desktopItem
    }
    Repeater {
        model: publicModel
        delegate: desktopItem
    }

    Rectangle {
        // More icons than cells: the last cell opens the Desktop folder.
        visible: root.overflowCount > 0
        x: root.cellX(Math.max(0, root.overflowCell)) + 8
        y: root.cellY(Math.max(0, root.overflowCell)) + 8
        width: root.cellWidth - 16
        height: root.cellHeight - 16
        radius: Appearance.rounding.normal
        color: overflowMouse.containsMouse ? ColorUtils.transparentize(Appearance.colors.colLayer1, 0.2) : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.45)
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("%1 more").arg(root.overflowCount)
            color: Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: overflowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: Quickshell.execDetached(["xdg-open", root.nativePath(root.userDesktop)])
        }
    }

    Component {
        id: desktopItem

        Item {
            id: item
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            readonly property int cell: root.cells[filePath] ?? -1
            readonly property bool selected: root.selection[filePath] === true
            readonly property bool renaming: root.renamingPath === filePath
            property url dragImage
            visible: cell >= 0
            x: root.cellX(Math.max(0, cell))
            y: root.cellY(Math.max(0, cell))
            z: renaming ? 2 : selected ? 1 : 0
            width: root.cellWidth
            height: root.cellHeight

            Behavior on x {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: item.selected || folderDrop.containsDrag ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.15)
                     : mouse.containsMouse ? ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                     : "transparent"
                border.width: root.keyboardUsed && root.activeFocus && root.currentPath === item.filePath ? 2 : 0
                border.color: Appearance.colors.colPrimary
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
                // Cut files look faded, as in Explorer? Windows does not report that; keep it simple.
            }

            StyledText {
                id: label
                visible: !item.renaming
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
                maximumLineCount: item.selected && root.selectionCount === 1 ? 4 : 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: item.selected ? Appearance.colors.colOnPrimaryContainer : "white"
                text: root.displayName(item.fileName)
                style: item.selected ? Text.Normal : Text.Outline
                styleColor: ColorUtils.transparentize("black", 0.55)
                // The shadow Windows puts under the names, so they read on any wallpaper.
                layer.enabled: (Config.options.background.widgets.desktopIcons.textShadow ?? true) && !item.selected
                layer.effect: MultiEffect {
                    autoPaddingEnabled: true
                    shadowEnabled: true
                    shadowColor: "black"
                    shadowOpacity: 0.9
                    shadowBlur: 0.55
                    shadowHorizontalOffset: 1
                    shadowVerticalOffset: 1
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property point pressPos
                property bool collapseOnRelease: false
                onPressed: event => {
                    root.forceActiveFocus();
                    root.keyboardUsed = false;
                    pressPos = Qt.point(event.x, event.y);
                    collapseOnRelease = false;
                    if (event.button === Qt.RightButton) {
                        if (!item.selected) root.selectOnly(item.filePath);
                        root.currentPath = item.filePath;
                        const p = mapToItem(root, event.x, event.y);
                        root.openItemMenu(p.x, p.y);
                        return;
                    }
                    if (event.modifiers & Qt.ControlModifier) {
                        root.toggle(item.filePath);
                    } else if (event.modifiers & Qt.ShiftModifier) {
                        root.selectRange(root.anchorPath || item.filePath, item.filePath, false);
                    } else if (!item.selected) {
                        root.selectOnly(item.filePath);
                    } else {
                        // Pressing one of several selected icons may start dragging them all;
                        // a plain click selects just this one.
                        collapseOnRelease = root.selectionCount > 1;
                        root.currentPath = item.filePath;
                    }
                    item.grabToImage(result => item.dragImage = result.url, Qt.size(item.width, item.height));
                }
                onPositionChanged: event => {
                    if (!(pressedButtons & Qt.LeftButton) || root.internalDrag) return;
                    if (Math.abs(event.x - pressPos.x) + Math.abs(event.y - pressPos.y) < 10) return;
                    collapseOnRelease = false;
                    root.startDrag(item, pressPos);
                }
                onReleased: event => {
                    if (collapseOnRelease && event.button === Qt.LeftButton) root.selectOnly(item.filePath);
                    collapseOnRelease = false;
                }
                onDoubleClicked: event => {
                    if (event.button === Qt.LeftButton) root.open(root.selectedPaths());
                }
            }

            DropArea {
                id: folderDrop
                // Dropping on a folder moves the files into it.
                anchors.fill: parent
                enabled: item.fileIsDir
                onEntered: drag => {
                    if (root.internalDrag ? root.dragPaths.includes(item.filePath) : !drag.hasUrls) drag.accepted = false;
                }
                onDropped: drop => {
                    const paths = root.internalDrag ? root.dragPaths : Array.from(drop.urls).map(root.pathFromUrl).filter(p => p !== "");
                    if (paths.length === 0) return;
                    const sameDrive = paths[0].substring(0, 2).toLowerCase() === item.filePath.substring(0, 2).toLowerCase();
                    root.files([sameDrive ? "move" : "copy", root.nativePath(item.filePath), ...paths.map(root.nativePath)]);
                    drop.accept(Qt.CopyAction);
                }
            }

            Loader {
                // In-place rename, as in Explorer: Enter or clicking away saves, Esc cancels.
                active: item.renaming
                anchors {
                    top: icon.bottom
                    topMargin: 2
                    left: parent.left
                    right: parent.right
                    leftMargin: -6
                    rightMargin: -6
                }
                sourceComponent: Rectangle {
                    implicitHeight: editor.contentHeight + 8
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colPrimary

                    TextInput {
                        id: editor
                        property bool done: false
                        anchors.fill: parent
                        anchors.margins: 4
                        horizontalAlignment: TextInput.AlignHCenter
                        wrapMode: TextInput.WrapAnywhere
                        selectByMouse: true
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        selectionColor: Appearance.colors.colPrimary
                        selectedTextColor: Appearance.colors.colOnPrimary
                        text: root.displayName(item.fileName)
                        Component.onCompleted: {
                            forceActiveFocus();
                            // Select the name without its extension.
                            const dot = item.fileIsDir ? -1 : text.lastIndexOf(".");
                            select(0, dot > 0 ? dot : text.length);
                        }
                        function finish(save) {
                            if (done) return;
                            done = true;
                            if (save) root.commitRename(item.filePath, text);
                            else root.renamingPath = "";
                            root.forceActiveFocus();
                        }
                        Keys.onReturnPressed: finish(true)
                        Keys.onEnterPressed: finish(true)
                        Keys.onEscapePressed: finish(false)
                        onActiveFocusChanged: if (!activeFocus) finish(true)
                    }
                }
            }
        }
    }
}
