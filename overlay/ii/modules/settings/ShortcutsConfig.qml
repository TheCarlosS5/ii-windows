import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "shortcuts-data.js" as Data

// ii-windows (plan 2026-10-31, E16): Configuración > Atajos. ii's keyboard actions (shared/actions.json), each with the
// combination in use; those ii-host takes can get another one or none ([keys] of %LOCALAPPDATA%\ii-windows\shortcuts.ini,
// which ii-host reads again as soon as it changes). Also the options of that file that were only set by hand: games and
// full screen, and the volume and media keys.
ContentPage {
    id: page
    forceWidth: true

    readonly property string dataDir: Quickshell.env("II_DATA_DIR") || (Quickshell.env("LOCALAPPDATA") + "\\ii-windows")
    property var ini: ({})          // section -> { key: value } (lower-case names)
    property bool iniLoaded: false
    property string filter: ""
    property string editingId: ""

    // --- shortcuts.ini ---------------------------------------------------------------------------------------------------
    function parseIni(text) {
        const result = {};
        let section = "";
        for (const raw of (text || "").split(/\r?\n/)) {
            const line = raw.trim();
            if (line.length === 0 || line.startsWith(";") || line.startsWith("#")) continue;
            const header = line.match(/^\[(.+)\]$/);
            if (header) {
                section = header[1].trim().toLowerCase();
                if (!result[section]) result[section] = {};
                continue;
            }
            const eq = line.indexOf("=");
            if (eq <= 0) continue;
            if (!result[section]) result[section] = {};
            result[section][line.slice(0, eq).trim().toLowerCase()] = line.slice(eq + 1).trim();
        }
        return result;
    }
    function serializeIni(sections) {
        const order = ["policy", "yield", "keep", "unhook", "audio", "keys"];
        const names = order.filter(n => sections[n]).concat(Object.keys(sections).filter(n => order.indexOf(n) < 0 && n !== ""));
        let text = "; ii-windows: shortcuts and keyboard rules (Configuración > Atajos writes this file; ii-host reads it again when it changes)\r\n";
        for (const name of names) {
            const keys = Object.keys(sections[name]).filter(k => String(sections[name][k]).length > 0);
            if (keys.length === 0) continue;
            text += `\r\n[${name}]\r\n`;
            for (const k of keys) text += `${k} = ${sections[name][k]}\r\n`;
        }
        return text;
    }
    function iniValue(section, key, fallback) {
        return (page.ini[section] && page.ini[section][key] !== undefined) ? page.ini[section][key] : fallback;
    }
    function setIni(section, key, value) {
        const next = JSON.parse(JSON.stringify(page.ini));
        if (!next[section]) next[section] = {};
        if (value === null || value === undefined || String(value).length === 0) delete next[section][key];
        else next[section][key] = String(value);
        page.ini = next;
        iniFile.setText(page.serializeIni(next));
    }
    FileView {
        id: iniFile
        path: page.dataDir + "\\shortcuts.ini"
        printErrors: false
        onLoaded: {
            page.ini = page.parseIni(iniFile.text());
            page.iniLoaded = true;
        }
        onLoadFailed: page.iniLoaded = true // no file yet: every default
    }

    // --- combinations -------------------------------------------------------------------------------------------------
    readonly property var keyAliases: ({ "period": ".", "comma": ",", "slash": "/", "minus": "-", "plus": "=", "escape": "esc",
        "del": "delete", "printscreen": "print", "control": "ctrl", "super": "win", "meta": "win" })
    readonly property var namedKeys: ["tab", "space", "enter", "esc", "delete", "insert", "home", "end", "pageup", "pagedown",
        "up", "down", "left", "right", "print", "pause", "scrolllock", "backspace"]
    function keyOk(key) {
        if (/^[a-z0-9.,\/\-=;'`\[\]\\]$/.test(key)) return true;
        if (/^f([1-9]|1[0-9]|2[0-4])$/.test(key)) return true;
        return page.namedKeys.indexOf(key) >= 0;
    }
    // "Win + Shift + k" -> { mods: {win, ctrl, alt, shift}, key: "k", text: "win+shift+k" } or null
    function parseCombo(text) {
        const parts = String(text || "").toLowerCase().split("+").map(p => p.trim()).filter(p => p.length > 0);
        const mods = { win: false, ctrl: false, alt: false, shift: false };
        let key = "";
        for (let part of parts) {
            part = page.keyAliases[part] ?? part;
            if (part === "win" || part === "ctrl" || part === "alt" || part === "shift") mods[part] = true;
            else if (key === "") key = part;
            else return null;
        }
        if (key === "" || !page.keyOk(key)) return null;
        const names = ["win", "ctrl", "alt", "shift"].filter(m => mods[m]);
        return { mods: mods, key: key, text: names.concat([key]).join("+") };
    }
    function special(key) { return /^f([1-9]|1[0-9]|2[0-4])$/.test(key) || key === "print" || key === "pause" || key === "scrolllock"; }
    function jsonCombo(k) { // a key entry of actions.json -> the same text form
        const map = { "Period": ".", "Slash": "/", "Escape": "esc", "Delete": "delete", "Up": "up", "Tab": "tab", "End": "end", "Print": "print" };
        const key = map[k.key] ?? k.key.toLowerCase();
        if (key === "super_l") return key; // the Win key itself, tapped
        return ["win", "ctrl", "alt", "shift"].filter(m => k.mods.indexOf(m) >= 0).concat([key]).join("+");
    }
    // What an action's combinations are now: [] for none, or texts like "win+s".
    function combosOf(action) {
        const custom = page.iniValue("keys", action.id, "");
        if (custom.length > 0) {
            if (custom.toLowerCase() === "off" || custom.toLowerCase() === "none") return [];
            const parsed = page.parseCombo(custom);
            return parsed ? [parsed.text] : action.keys.map(k => page.jsonCombo(k)); // ii-host ignores a bad one too
        }
        return action.keys.map(k => page.jsonCombo(k));
    }
    function display(combo) {
        const names = { "win": "Win", "ctrl": "Ctrl", "alt": "Alt", "shift": Translation.tr("Shift"), "print": Translation.tr("Print Screen"),
            "esc": "Esc", "delete": Translation.tr("Del"), "tab": "Tab", "up": "↑", "down": "↓", "left": "←", "right": "→",
            "super_l": Translation.tr("Win (tap)"), "left/right": "← →", "1-0": "1…0", "space": Translation.tr("Space"), "enter": "Enter" };
        return combo.split("+").map(p => names[p] ?? (p.length === 1 ? p.toUpperCase() : p.charAt(0).toUpperCase() + p.slice(1))).join(" + ");
    }
    readonly property var reserved: ({ "win+l": Translation.tr("Windows locks the PC with it; no program can take it"),
        "ctrl+alt+delete": Translation.tr("Windows' secure combination; no program can take it") })
    readonly property var windowsCombos: ({ "win+e": "Explorador de archivos", "win+r": "Ejecutar", "win+p": "Proyectar",
        "win+k": "Transmitir", "win+h": "Dictado", "win+g": "Game Bar", "win+alt+r": "Game Bar (grabar)", "win+c": "Copilot",
        "win+z": "Diseños de ajuste", "win+up": "Maximizar", "win+down": "Minimizar", "win+left": "Ajustar a la izquierda",
        "win+right": "Ajustar a la derecha", "win+ctrl+d": "Escritorio nuevo", "win+ctrl+f4": "Cerrar escritorio",
        "win+ctrl+left": "Escritorio anterior", "win+ctrl+right": "Escritorio siguiente", "win+space": "Cambiar de idioma del teclado",
        "win+,": "Ver el escritorio un momento", "win+home": "Minimizar las demás", "win+=": "Lupa", "win+-": "Lupa",
        "win+ctrl+enter": "Narrador", "win+ctrl+c": "Filtros de color", "win+print": "Captura de pantalla completa",
        "ctrl+shift+esc": "Administrador de tareas", "alt+tab": "Cambiar de ventana", "alt+f4": "Cerrar la ventana", "win+u": "Accesibilidad",
        "win+a": "Configuración rápida de Windows", "win+n": "Notificaciones de Windows", "win+w": "Widgets de Windows" })
    readonly property var powerToysCombos: ({ "win+shift+c": "Selector de color", "alt+space": "PowerToys Run / Paleta de comandos",
        "win+shift+t": "Extractor de texto", "win+ctrl+t": "Siempre visible", "win+shift+/": "Guía de atajos",
        "win+shift+v": "Pegado avanzado", "win+ctrl+shift+t": "Recortar y bloquear", "win+shift+h": "Resaltar el mouse",
        "win+ctrl+alt+r": "Grabar pantalla (Ajustes)" })
    // { block: "why it cannot be used" } or { warn: "what else uses it" } or {} for a combination given to `action`.
    function check(combo, action) {
        if (!combo) return { block: Translation.tr("Not a combination ii can take: one key, like K, F9 or Print Screen, with Win, Ctrl or Alt") };
        if (!combo.mods.win && !combo.mods.ctrl && !combo.mods.alt && !page.special(combo.key))
            return { block: Translation.tr("It needs Win, Ctrl or Alt: alone (or with Shift) that key is for typing") };
        if (page.reserved[combo.text]) return { block: page.reserved[combo.text] };
        for (const other of Data.actions) {
            if (other.id === action.id) continue;
            if (page.combosOf(other).indexOf(combo.text) >= 0)
                return { block: Translation.tr("ii already uses it for \"%1\"").arg(Translation.tr(other.text)) };
        }
        if (page.windowsCombos[combo.text]) return { warn: Translation.tr("Windows uses it for \"%1\": ii takes it while ii is on").arg(page.windowsCombos[combo.text]) };
        if (page.powerToysCombos[combo.text]) return { warn: Translation.tr("PowerToys uses it for \"%1\" if you have it: one of the two will not get it").arg(page.powerToysCombos[combo.text]) };
        return {};
    }
    function supportText(action) {
        if (action.support === "external") return Translation.tr("Windows'");
        if (action.support === "partial") return Translation.tr("In part");
        if (action.support === "unsupported") return Translation.tr("Not yet");
        return "";
    }
    readonly property var shown: Data.actions.filter(a => {
        if (page.filter === "") return true;
        const hay = (Translation.tr(a.text) + " " + a.text + " " + Translation.tr(a.group) + " " + page.combosOf(a).map(c => page.display(c)).join(" ")).toLowerCase();
        return page.filter.split(/\s+/).every(w => hay.includes(w));
    })
    readonly property int changedCount: Object.keys(page.ini["keys"] ?? {}).length

    // --- the list -------------------------------------------------------------------------------------------------
    ContentSection {
        icon: "keyboard"
        title: Translation.tr("ii's shortcuts")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("What each combination does with ii. Those with \"Change\" can take another combination or none; the change works at once. Ctrl+Alt+Shift+R (restore Windows) is never changed.")
        }
        RowLayout {
            Layout.fillWidth: true
            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search shortcuts")
                onTextChanged: page.filter = text.toLowerCase().trim()
            }
            RippleButtonWithIcon {
                visible: page.changedCount > 0
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restore all (%1)").arg(page.changedCount)
                onClicked: {
                    const next = JSON.parse(JSON.stringify(page.ini));
                    delete next["keys"];
                    page.ini = next;
                    iniFile.setText(page.serializeIni(next));
                    page.editingId = "";
                }
            }
        }

        Repeater {
            model: page.shown
            delegate: ColumnLayout {
                id: row
                required property var modelData
                required property int index
                readonly property var combos: page.combosOf(row.modelData)
                readonly property bool changed: page.iniValue("keys", row.modelData.id, "") !== ""
                readonly property bool editing: page.editingId === row.modelData.id
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel { // the group, before its first action
                    visible: row.index === 0 || page.shown[row.index - 1].group !== row.modelData.group
                    Layout.topMargin: row.index === 0 ? 4 : 12
                    text: Translation.tr(row.modelData.group)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr(row.modelData.text)
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: row.modelData.reason.length > 0 && row.modelData.support !== "available"
                            text: Translation.tr(row.modelData.reason)
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    StyledText {
                        visible: page.supportText(row.modelData).length > 0
                        text: page.supportText(row.modelData)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    Repeater {
                        model: row.combos.length > 0 ? row.combos : [""]
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: comboText.implicitWidth + 16
                            implicitHeight: comboText.implicitHeight + 8
                            radius: Appearance.rounding.small
                            color: row.changed ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                            StyledText {
                                id: comboText
                                anchors.centerIn: parent
                                text: modelData === "" ? Translation.tr("None") : page.display(modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: modelData === "" ? Appearance.font.family.main : Appearance.font.family.monospace
                                color: row.changed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                            }
                        }
                    }
                    RippleButtonWithIcon {
                        visible: row.modelData.editable
                        materialIcon: row.editing ? "close" : "edit"
                        mainText: row.editing ? Translation.tr("Cancel") : Translation.tr("Change")
                        onClicked: page.editingId = row.editing ? "" : row.modelData.id
                    }
                }

                // The editor: modifiers as chips, the key typed (ii-host takes the combinations, so they cannot be
                // pressed here to record them).
                Rectangle {
                    visible: row.editing
                    Layout.fillWidth: true
                    implicitHeight: editor.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    ColumnLayout {
                        id: editor
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6
                        property var mods: ({ win: true, ctrl: false, alt: false, shift: false })
                        property string key: ""
                        readonly property var combo: page.parseCombo(["win", "ctrl", "alt", "shift"].filter(m => editor.mods[m]).concat([editor.key]).join("+"))
                        readonly property var verdict: editor.key.length > 0 ? page.check(editor.combo, row.modelData) : ({})
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: ["win", "ctrl", "alt", "shift"]
                                delegate: RippleButton {
                                    required property string modelData
                                    toggled: editor.mods[modelData]
                                    implicitHeight: 34
                                    implicitWidth: chipText.implicitWidth + 24
                                    buttonRadius: Appearance.rounding.full
                                    onClicked: {
                                        const next = Object.assign({}, editor.mods);
                                        next[modelData] = !next[modelData];
                                        editor.mods = next;
                                    }
                                    contentItem: StyledText {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: page.display(modelData)
                                        color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                            StyledText { text: "+"; color: Appearance.colors.colSubtext }
                            MaterialTextField {
                                Layout.preferredWidth: 150
                                placeholderText: Translation.tr("Key: K, F9, Tab…")
                                onTextChanged: editor.key = text.trim().toLowerCase()
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: editor.key.length > 0
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: editor.verdict.block ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                            text: editor.verdict.block ?? editor.verdict.warn ?? (editor.combo ? Translation.tr("Free: %1").arg(page.display(editor.combo.text)) : "")
                        }
                        RowLayout {
                            spacing: 6
                            RippleButtonWithIcon {
                                enabled: editor.combo !== null && !editor.verdict.block
                                materialIcon: "check"
                                mainText: Translation.tr("Save")
                                onClicked: {
                                    page.setIni("keys", row.modelData.id, editor.combo.text);
                                    page.editingId = "";
                                }
                            }
                            RippleButtonWithIcon {
                                materialIcon: "block"
                                mainText: Translation.tr("No shortcut")
                                onClicked: {
                                    page.setIni("keys", row.modelData.id, "off");
                                    page.editingId = "";
                                }
                            }
                            RippleButtonWithIcon {
                                visible: row.changed
                                materialIcon: "restart_alt"
                                mainText: Translation.tr("Restore")
                                onClicked: {
                                    page.setIni("keys", row.modelData.id, null);
                                    page.editingId = "";
                                }
                            }
                        }
                    }
                }
            }
        }
        StyledText {
            visible: page.shown.length === 0
            text: Translation.tr("No shortcut matches \"%1\"").arg(page.filter)
            color: Appearance.colors.colSubtext
        }
    }

    // --- games and full screen -----------------------------------------------------------------------------------------
    ContentSection {
        icon: "sports_esports"
        title: Translation.tr("Games and full screen")

        ContentSubsection {
            title: Translation.tr("ii's shortcuts step aside")
            tooltip: Translation.tr("Automatic: with exclusive full screen and borderless full-screen windows (not browsers). Only exclusive: only exclusive full screen (D3D). Never: ii's shortcuts always work.")
            ConfigSelectionArray {
                currentValue: page.iniValue("policy", "fullscreen", "auto").toLowerCase()
                onSelected: newValue => page.setIni("policy", "fullscreen", newValue === "auto" ? null : newValue)
                options: [
                    { displayName: Translation.tr("Automatic"), icon: "auto_mode", value: "auto" },
                    { displayName: Translation.tr("Only exclusive"), icon: "fullscreen", value: "geometry" },
                    { displayName: Translation.tr("Never"), icon: "block", value: "never" }
                ]
            }
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Programs where ii's shortcuts always step aside (game.exe; other.exe)")
            text: page.iniValue("yield", "processes", "")
            onEditingFinished: if (text !== page.iniValue("yield", "processes", "")) page.setIni("yield", "processes", text.trim())
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Programs where ii does not watch the keyboard at all (anti-cheat games)")
            text: page.iniValue("unhook", "processes", "")
            onEditingFinished: if (text !== page.iniValue("unhook", "processes", "")) page.setIni("unhook", "processes", text.trim())
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: Translation.tr("Valorant, League of Legends, Fortnite, Apex, Rainbow Six and Tarkov are already on ii's own list. Names separated by ;")
        }
    }

    // --- volume and media keys ------------------------------------------------------------------------------------------
    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Volume and media keys")

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("ii handles the volume keys (its own indicator instead of Windows')")
            checked: page.iniValue("audio", "volumekeys", "ii").toLowerCase() !== "windows"
            onCheckedChanged: {
                if (!page.iniLoaded) return;
                const want = checked ? null : "windows";
                if ((page.iniValue("audio", "volumekeys", "") || null) !== want) page.setIni("audio", "volumekeys", want);
            }
        }
        ConfigSwitch {
            buttonIcon: "play_pause"
            text: Translation.tr("ii handles play/pause, next and previous (its player and pill)")
            checked: page.iniValue("audio", "mediakeys", "windows").toLowerCase() === "ii"
            onCheckedChanged: {
                if (!page.iniLoaded) return;
                const want = checked ? "ii" : null;
                if ((page.iniValue("audio", "mediakeys", "") || null) !== want) page.setIni("audio", "mediakeys", want);
            }
        }
    }
}
