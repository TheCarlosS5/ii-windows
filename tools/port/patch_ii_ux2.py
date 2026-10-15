"""UX round of 2026-10-15, part 2: AI models, features that do not work, welcome, about, settings.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- Gemini: the models this key can use today, from Google itself -----------------------------------------
# The built-in list (2.5 Flash, 3 Flash preview) ages: with a free key Google offers newer models and the
# old ones stop answering. The list comes from ListModels with the user's key (through ii-shim ai-request
# {"method":"GET"}); the built-in ones stay as the fallback (offline, no key, older ii-shim).
edit(path('services', 'Ai.qml'), [
    ('''    property var modelList: Object.keys(root.models)
''',
     '''    // --- ii-windows: Gemini models from Google's ListModels ---------------------------------------
    property bool geminiListed: false
    function geminiModelRank(id) {
        // Newer version first, then flash > flash-lite > pro for a free key.
        const v = /gemini-(\\d+(?:\\.\\d+)?)/.exec(id);
        const version = v ? parseFloat(v[1]) : 0;
        const tier = id.includes("flash-lite") ? 1 : id.includes("flash") ? 2 : id.includes("pro") ? 0 : -1;
        return version * 10 + tier;
    }
    function applyGeminiList(text) {
        let parsed;
        try { parsed = JSON.parse(text); } catch (e) { return; }
        const list = (parsed.models ?? []).filter(m => {
            const id = (m.name ?? "").replace("models/", "");
            return id.startsWith("gemini-") && (m.supportedGenerationMethods ?? []).includes("generateContent")
                && !/embedding|tts|image|audio|live|robotics|computer-use|aqa|imagen|exp-|-001$|-002$|-latest$|\\d{2}-\\d{2}$|\\d{4}$|customtools/.test(id);
        }).map(m => ({ id: m.name.replace("models/", ""), name: m.displayName || m.name, description: m.description || "" }));
        if (list.length === 0) return;
        list.sort((a, b) => root.geminiModelRank(b.id) - root.geminiModelRank(a.id));
        const keep = {};
        for (const key of Object.keys(root.models))
            if (root.models[key].api_format !== "gemini") keep[key] = root.models[key];
        const next = {};
        for (const m of list.slice(0, 8)) {
            next[root.safeModelName(m.id)] = aiModelComponent.createObject(root, {
                "name": m.name,
                "icon": "google-gemini-symbolic",
                "description": Translation.tr("Online | Google's model | Available with your key") + "\\n" + m.description,
                "homepage": "https://aistudio.google.com",
                "endpoint": `https://generativelanguage.googleapis.com/v1beta/models/${m.id}:streamGenerateContent`,
                "model": m.id,
                "requires_key": true,
                "key_id": "gemini",
                "key_get_link": "https://aistudio.google.com/app/apikey",
                "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\\n\\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
                "api_format": "gemini",
            });
        }
        root.models = Object.assign({}, next, keep);
        root.modelList = Object.keys(root.models);
        root.geminiListed = true;
        if (!root.models[root.currentModelId]) {
            // The model that was chosen is gone: the newest flash this key offers.
            const preferred = list.find(m => m.id.includes("flash") && !m.id.includes("lite")) ?? list[0];
            root.setModel(root.safeModelName(preferred.id), false, false);
        }
    }
    function refreshGeminiModels() {
        const key = root.apiKeys["gemini"] ?? "";
        if (!key || key.length === 0 || geminiListProc.running) return;
        const requestPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath).replace(/\\.sh$/, "") + ".models." + Quickshell.instanceId + ".json";
        const content = JSON.stringify({ "method": "GET", "url": "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=${API_KEY}", "headers": {} });
        geminiListFile.path = Qt.resolvedUrl(requestPath);
        geminiListFile.setText(content);
        geminiListFile.reload();
        geminiListProc.environment["API_KEY"] = key;
        geminiListProc.command = ["ii-shim", "ai-request", requestPath];
        geminiListProc.running = true;
    }
    FileView {
        id: geminiListFile
        blockWrites: true
        blockAllReads: true
    }
    Process {
        id: geminiListProc
        stdout: StdioCollector {
            onStreamFinished: root.applyGeminiList(text)
        }
    }
    Connections {
        target: KeyringStorage
        function onLoadedChanged() { if (KeyringStorage.loaded) root.refreshGeminiModels(); }
        function onDataChanged() { root.refreshGeminiModels(); }
    }

    property var modelList: Object.keys(root.models)
'''),
])


# --- Overview: GNOME-style search (overlay: Overview.qml, SearchWidget.qml, AppGrid.qml) ----------------------
# SearchBar: no Google Lens / music recognition buttons (neither works here); the keys that move
# through the results go to SearchWidget; the pill keeps one width.
edit(path('modules', 'ii', 'overview', 'SearchBar.qml'), [
    ('''    property string searchingText

    function forceFocus() {''',
     '''    property string searchingText
    property bool navigating: false
    signal navigate(string direction)
    signal activate()

    function forceFocus() {'''),
    ('''        implicitWidth: root.searchingText == "" ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth
''',
     '''        implicitWidth: 400
'''),
    ('''        onTextChanged: LauncherSearch.query = text

        onAccepted: {
            if (appResults.count > 0) {
                // Get the first visible delegate and trigger its click
                let firstItem = appResults.itemAtIndex(0);
                if (firstItem && firstItem.clicked) {
                    firstItem.clicked();
                }
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab) {
                if (LauncherSearch.results.length === 0) return;
                const tabbedText = LauncherSearch.results[0].name;
                LauncherSearch.query = tabbedText;
                searchInput.text = tabbedText;
                event.accepted = true;
            }
        }
''',
     '''        onTextChanged: {
            LauncherSearch.query = text;
            root.navigating = false;
        }

        onAccepted: root.activate()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab) {
                if (LauncherSearch.results.length === 0) return;
                const tabbedText = LauncherSearch.results[0].name;
                LauncherSearch.query = tabbedText;
                searchInput.text = tabbedText;
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                root.navigating = true;
                root.navigate(event.key === Qt.Key_Down ? "down" : "up");
                event.accepted = true;
            } else if (root.navigating && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                root.navigate(event.key === Qt.Key_Left ? "left" : "right");
                event.accepted = true;
            }
        }
'''),
])
_sb = open(path('modules', 'ii', 'overview', 'SearchBar.qml'), encoding='utf-8', newline='').read().replace('\r\n', '\n')
_a = _sb.index('    IconToolbarButton {\n        Layout.topMargin: 4\n        Layout.bottomMargin: 4\n        onClicked: {\n            GlobalStates.overviewOpen = false;')
_sb = _sb[:_a].rstrip() + '\n}\n'
open(path('modules', 'ii', 'overview', 'SearchBar.qml'), 'w', encoding='utf-8', newline='').write(_sb)
print('patched', path('modules', 'ii', 'overview', 'SearchBar.qml'), '(buttons removed)')

edit(path('modules', 'ii', 'overview', 'SearchItem.qml'), [
    ('    readonly property bool selected: (root.hovered || root.focus)\n',
     '    property bool forcedSelected: false // ii-windows: the keyboard selection of the grid-style results\n'
     '    readonly property bool selected: (root.hovered || root.focus || root.forcedSelected)\n'),
])


def add_translations(code, strings):
    import json
    file = path('translations', code + '.json')
    with open(file, encoding='utf-8') as f:
        data = json.load(f)
    for key, value in strings.items():
        data.setdefault(key, value)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


ES_UX2 = {
    "Show applications": "Mostrar aplicaciones",
    "Online | Google's model | Available with your key": "En línea | Modelo de Google | Disponible con tu clave",
}
add_translations('es_MX', ES_UX2)


# --- Lock keys indicator, Windows' wallpaper adopted, wallpaper refits on a new resolution -----------------------
edit(path('panelFamilies', 'IllogicalImpulseFamily.qml'), [
    ('    PanelLoader { component: OnScreenDisplay {} }\n',
     '    PanelLoader { component: OnScreenDisplay {} }\n    PanelLoader { component: LockKeysOsd {} } // ii-windows: Caps/Num/Scroll Lock\n'),
    # "Overlay widgets" (crosshair, FPS limiter, recorder, mixer, notes, ...): nobody asked for them and
    # they cost memory and time at start, so the panel is not loaded at all.
    ('    PanelLoader { component: Overlay {} }\n', ''),
])
edit(path('shell.qml'), [
    ("        DesktopCleanup.load() // ii-windows: empty desktops don't pile up\n",
     "        DesktopCleanup.load() // ii-windows: empty desktops don't pile up\n"
     "        LockKeys.load() // ii-windows: Caps/Num/Scroll Lock indicator\n"
     "        Quickshell.execDetached([\"switchwall\", \"--adopt-windows\"]) // ii-windows: the wallpaper Windows has is ii's too\n"),
])
edit(path('modules', 'common', 'Config.qml'), [
    ('''            property JsonObject osd: JsonObject {
                property int timeout: 1000
''',
     '''            property JsonObject osd: JsonObject {
                property int timeout: 1000
                property bool lockKeys: true // ii-windows: "Caps Lock on" and the like
'''),
])
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''            onValueChanged: {
                Config.options.osd.timeout = value;
            }
        }
''',
     '''            onValueChanged: {
                Config.options.osd.timeout = value;
            }
        }
        ConfigSwitch {
            buttonIcon: "keyboard_capslock"
            text: Translation.tr("Show Caps Lock, Num Lock and Scroll Lock")
            checked: Config.options.osd.lockKeys
            onCheckedChanged: Config.options.osd.lockKeys = checked
        }
'''),
])
# A new resolution or display scale refits the picture (it was measured once, when the wallpaper changed).
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('''        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }
''',
     '''        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }
        // ii-windows: a new resolution or display scale refits the picture.
        readonly property real fitKey: screen.width * 100003 + screen.height * 7 + (screen.devicePixelRatio ?? 1) * 1000
        onFitKeyChanged: updateZoomScale()
'''),
])
# The song-recognition toggle is not offered any more (SongRec does not exist on Windows).
edit(path('modules', 'common', 'Config.qml'), [
    ('"mic", "musicRecognition", "notifications"', '"mic", "notifications"'),
])

ES_UX4 = {
    "Caps Lock on": "Bloq Mayús activado",
    "Caps Lock off": "Bloq Mayús desactivado",
    "Num Lock on": "Bloq Num activado",
    "Num Lock off": "Bloq Num desactivado",
    "Scroll Lock on": "Bloq Despl activado",
    "Scroll Lock off": "Bloq Despl desactivado",
    "Show Caps Lock, Num Lock and Scroll Lock": "Mostrar Bloq Mayús, Bloq Num y Bloq Despl",
}
add_translations('es_MX', ES_UX4)


# --- Right sidebar: the toggles act in place (they used to open Windows' Settings for one switch) --------------
edit(path('modules', 'common', 'models', 'quickToggles', 'GameModeToggle.qml'), [
    ('''    toggled: false
    hasStatusText: false
    icon: "gamepad"

    mainAction: () => {
        Quickshell.execDetached(["xdg-open", "ms-settings:gaming-gamemode"]);
    }
''',
     '''    // Windows' Game Mode (priority for the game in front): HKCU\\Software\\Microsoft\\GameBar. Absent = on.
    toggled: true
    hasStatusText: false
    icon: "gamepad"

    mainAction: () => {
        setProc.command = ["reg", "add", "HKCU\\\\Software\\\\Microsoft\\\\GameBar", "/v", "AutoGameModeEnabled", "/t", "REG_DWORD", "/d", root.toggled ? "0" : "1", "/f"];
        setProc.running = true;
    }
    Process {
        id: readProc
        running: true
        command: ["reg", "query", "HKCU\\\\Software\\\\Microsoft\\\\GameBar", "/v", "AutoGameModeEnabled"]
        stdout: StdioCollector {
            onStreamFinished: root.toggled = !/0x0\\s*$/m.test(text)
        }
    }
    Process {
        id: setProc
        onExited: readProc.running = true
    }
'''),
])
edit(path('modules', 'common', 'models', 'quickToggles', 'OnScreenKeyboardToggle.qml'), [
    ('''        Quickshell.execDetached(["xdg-open", "ms-settings:easeofaccess-keyboard"]);''',
     '''        Quickshell.execDetached(["osk.exe"]); // Windows' on-screen keyboard, right away'''),
])


# --- Right sidebar on short screens (laptops at 125-150 %): notifications and the calendar no longer pile up ---------
# The notification list got whatever the calendar left; on 720-800 px-high screens that was nothing and its
# buttons ended up under the quick toggles. The list keeps a minimum and the calendar folds itself.
edit(path('modules', 'ii', 'sidebarRight', 'SidebarRightContent.qml'), [
    ('''            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
            }

            BottomWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
            }''',
     '''            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.minimumHeight: 160 // ii-windows: never squeezed into the toggles
            }

            BottomWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                // ii-windows: on a short screen the calendar folds to its header (the arrow opens it).
                forceCollapsed: root.height < 790
            }'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'BottomWidgetGroup.qml'), [
    ('''    property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
''',
     '''    property bool forceCollapsed: false // ii-windows: short screens fold the calendar...
    property bool userExpanded: false // ...until the arrow is pressed
    property bool collapsed: (forceCollapsed && !userExpanded) || Persistent.states.sidebar.bottomGroup.collapsed
'''),
    ('''    function setCollapsed(state) {
        Persistent.states.sidebar.bottomGroup.collapsed = state;''',
     '''    function setCollapsed(state) {
        root.userExpanded = !state;
        Persistent.states.sidebar.bottomGroup.collapsed = state;'''),
])


# --- small things found testing the settings ----------------------------------------------------------------------
edit(path('modules', 'settings', 'QuickConfig.qml'), [
    ('''    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr('Not all options are available in this app.''',
     '''    NoticeBox {
        visible: false // ii-windows: a note about a config file nobody has to touch
        Layout.fillWidth: true
        text: Translation.tr('Not all options are available in this app.'''),
])
edit(path('settings.qml'), [
    ('    title: "illogical-impulse Settings"\n', '    title: "ii-windows"\n'),
])


def read(p):
    return open(p, encoding='utf-8', newline='').read().replace('\r\n', '\n')


def write(p, text):
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    print('patched', p)


# --- Start-up in stages: the bar, the dock and the wallpaper first -------------------------------------------------
# ii created every panel (sidebars, overview, lock, region selector, ...) and loaded every service they use before
# showing anything. On a slow laptop that is what "ii is loading" waited for. Now phase 1 (wallpaper, bar, dock)
# comes up first; phase 2 (notifications, right sidebar, search, OSD) ~2.5 s later; phase 3 (AI sidebar, lock,
# screenshots, tour ...) ~5 s later, while the user already has a working desktop. A shortcut pressed in the first
# seconds finds the panel not yet there; that is the price.
edit(path('GlobalStates.qml'), [
    ('    property bool overviewOpen: false\n',
     '    property bool overviewOpen: false\n'
     '    property int startupPhase: 1 // ii-windows: panels load in stages, see panelFamilies/PanelLoader.qml\n'),
])
edit(path('panelFamilies', 'PanelLoader.qml'), [
    ('import QtQuick\nimport Quickshell\n', 'import QtQuick\nimport Quickshell\n\nimport qs\n'),
    ('''    property bool extraCondition: true
    active: Config.ready && extraCondition
''',
     '''    property bool extraCondition: true
    property int phase: 1 // ii-windows: 1 = at once, 2 and 3 = a little later (GlobalStates.startupPhase)
    active: Config.ready && extraCondition && GlobalStates.startupPhase >= phase
'''),
])
_family = read(path('panelFamilies', 'IllogicalImpulseFamily.qml'))
_phases = {
    'Cheatsheet': 3, 'Lock': 3, 'MediaControls': 2, 'NotificationPopup': 2, 'OnScreenDisplay': 2, 'LockKeysOsd': 2,
    'OnScreenKeyboard': 3, 'Overview': 2, 'Polkit': 3, 'RegionSelector': 3, 'ScreenCorners': 2, 'ScreenTranslator': 3,
    'SessionScreen': 3, 'SidebarLeft': 3, 'SidebarRight': 2, 'WallpaperSelector': 3,
}
for _name, _phase in _phases.items():
    _old = 'component: ' + _name + ' {}'
    if _family.count(_old) != 1:
        raise SystemExit('IllogicalImpulseFamily.qml: expected one "' + _old + '"')
    _family = _family.replace(_old, 'phase: ' + str(_phase) + '; ' + _old)
if 'import qs\n' not in _family:
    _family = _family.replace('import qs.modules.common\n', 'import qs\nimport qs.modules.common\n', 1)
_family = _family.replace('''Scope {
    PanelLoader''', '''Scope {
    // ii-windows: the stages of start-up (see PanelLoader.qml).
    Timer {
        running: Config.ready
        interval: 2500
        repeat: true
        onTriggered: {
            if (GlobalStates.startupPhase < 3) GlobalStates.startupPhase += 1;
            else running = false;
            interval = 2500;
        }
    }
    PanelLoader''', 1)
write(path('panelFamilies', 'IllogicalImpulseFamily.qml'), _family)


# The desktop's widgets and icons wait for phase 2: the wallpaper, the bar and the dock come first.
_bg = read(path('modules', 'ii', 'background', 'Background.qml'))
_bg, _n = re.subn(r'shown: Config\.options\.background\.widgets\.(\w+)\.enable', r'shown: GlobalStates.startupPhase >= 2 && Config.options.background.widgets.\1.enable', _bg)
if _n < 10:
    raise SystemExit('Background.qml: expected the desktop widget loaders, found ' + str(_n))
_old = 'active: Config.options.background.widgets.desktopIcons.enable && !GlobalStates.screenLocked'
if _bg.count(_old) != 1:
    raise SystemExit('Background.qml: desktop icons loader not found')
_bg = _bg.replace(_old, 'active: GlobalStates.startupPhase >= 2 && Config.options.background.widgets.desktopIcons.enable && !GlobalStates.screenLocked')
write(path('modules', 'ii', 'background', 'Background.qml'), _bg)


# --- "Reduce animations" applies to every animation that goes through Appearance --------------------------------------
# (panels sliding in, popups, ripples, the overview, the dock's slide ...): their durations become 0. Costs nothing when
# off. It also saves CPU/GPU: no frames are drawn for movement that is not there.
_app = read(path('modules', 'common', 'Appearance.qml'))
_app, _n1 = re.subn(r'readonly property real (expressive\w+Duration): (\d+)', r'readonly property real \1: \2 * root.motionFactor', _app)
_app, _n2 = re.subn(r'(property int duration): (\d+)\n', r'\1: \2 * root.motionFactor\n', _app)
if _n1 != 4 or _n2 < 5:
    raise SystemExit('Appearance.qml: animation durations not as expected (%d, %d)' % (_n1, _n2))
_marker = '    animationCurves: QtObject {'
if _app.count(_marker) != 1:
    raise SystemExit('Appearance.qml: animationCurves not found')
_app = _app.replace(_marker, '    // ii-windows: 0 with "Reduce animations" (Settings > Appearance), 1 otherwise.\n    readonly property real motionFactor: (Config?.options?.appearance?.reduceMotion ?? false) ? 0 : 1\n\n' + _marker)
write(path('modules', 'common', 'Appearance.qml'), _app)


# The overview: no giant desktop number behind the windows (the desktop strip above names them).
edit(path('modules', 'ii', 'overview', 'OverviewWidget.qml'), [
    ('''                            StyledText {
                                anchors.centerIn: parent
                                text: workspace.workspaceValue
''',
     '''                            StyledText {
                                visible: false // ii-windows: the desktop strip above names the desktop
                                anchors.centerIn: parent
                                text: workspace.workspaceValue
'''),
])


# Transparency without blur: on Hyprland ii's panels sit on a blurred wallpaper; Windows has no blur behind our
# panels, so text behind (a terminal under the sidebar) showed through and was hard to read. The automatic amount
# is capped lower: panels stay translucent, not glassy.
edit(path('modules', 'common', 'Appearance.qml'), [
    ('        return Math.max(0, Math.min(0.22, y)) - 0.12 * (m3colors.darkmode ? 0 : 1)',
     '        return Math.max(0, Math.min(0.11, y)) - 0.06 * (m3colors.darkmode ? 0 : 1) // ii-windows: capped (no blur behind panels here)'),
])
