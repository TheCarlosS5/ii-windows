"""Plan of 2026-10-31 (docs/PLAN-2026-10-31). Exact-match edits of the staged tree; every edit fails loudly if upstream
moved the code."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


def add_translations(code, strings):
    file = path('translations', code + '.json')
    with open(file, encoding='utf-8') as f:
        data = json.load(f)
    for key, value in strings.items():
        data.setdefault(key, value)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


# --- A2: the media card without warnings and without a file that never exists -----------------------------------------
# A track without a cover left artUrl undefined: the card then looked for coverart/<md5 of "undefined">
# (5e543256...), kept "downloaded" from the previous track, and the image and colour quantizer failed on every change
# (the shell logs of 2026-10-25 are full of it). isPlaying of a player that just went is undefined too.
edit(path('modules', 'ii', 'mediaControls', 'PlayerControl.qml'), [
    ('''    property var artUrl: player?.trackArtUrl
''', '''    property string artUrl: player?.trackArtUrl ?? ""
'''),
    ('''        if (!root.artUrl || root.artUrl.length == 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            return;
        }
''', '''        if (!root.artUrl || root.artUrl.length == 0) {
            coverArtDownloader.running = false;
            root.downloaded = false; // ii-windows: no cover, nothing to show (not the previous track's file)
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            return;
        }
'''),
    ('''            live: root.player?.isPlaying
''', '''            live: root.player?.isPlaying ?? false
'''),
    ('''                                    wavy: root.player?.isPlaying
''', '''                                    wavy: root.player?.isPlaying ?? false
'''),
])


# --- D7: no QML warnings in a normal session ---------------------------------------------------------------------------
# Seen in every 0.6.0 log: Translation.qml[21] (the scanner has no "running"), the user's generated translations folder
# (optional: most people never generate one), CookieClock's wallpaper category (only written by the AI wallpaper
# categorisation), and BarContent.qml[134] (Workspaces has no widgetPadding on Windows; BarGroup's default is 5).
edit(path('services', 'Translation.qml'), [
    ('''    property bool isScanning: scanLanguagesProcess.running
''', '''    property bool isScanning: scanLanguagesProcess.running ?? false
'''),
    ('''        id: generatedTranslationFileView
        translationsDir: root.generatedTranslationsDir
''', '''        id: generatedTranslationFileView
        translationsDir: root.generatedTranslationsDir
        printErrors: false // ii-windows: optional, most installs never generate a translation
'''),
])
edit(path('modules', 'ii', 'background', 'widgets', 'clock', 'CookieClock.qml'), [
    ('''        id: categoryFileView
''', '''        id: categoryFileView
        printErrors: false // ii-windows: only the AI wallpaper categorisation writes it
'''),
])
edit(path('modules', 'ii', 'bar', 'BarContent.qml'), [
    ('''            padding: workspacesWidget.widgetPadding
''', '''            padding: workspacesWidget.widgetPadding ?? 5
'''),
])


# --- A4/A9: Configuración > Avanzado > Diagnóstico (overlay/ii/modules/settings/DiagnosticsSection.qml) -------------
edit(path('modules', 'settings', 'AdvancedConfig.qml'), [
    ('''    ContentSection {
        icon: "health_and_safety"
''', '''    DiagnosticsSection {} // ii-windows: safe mode, error reports (plan 2026-10-31)

    ContentSection {
        icon: "health_and_safety"
'''),
])

add_translations('es_MX', {
    "Diagnostics": "Diagnóstico",
    "music and videos": "la música y los videos",
    "reading Windows notifications": "la lectura de notificaciones de Windows",
    "battery": "la batería",
    "Bluetooth": "el Bluetooth",
    "drawing with the graphics card": "el dibujo con la tarjeta gráfica",
    "ii is in safe mode: it closed several times in a row, so it starts with the minimum.":
        "ii está en modo seguro: se cerró varias veces seguidas, así que arranca con lo mínimo.",
    "Switched off after repeated errors: %1.": "Apagado después de errores repetidos: %1.",
    "Everything is on.": "Todo está encendido.",
    "No error reports on this PC.": "No hay informes de error en esta PC.",
    "Error reports kept on this PC: %1 (the newest: %2). They stay here; nothing is sent.":
        "Informes de error guardados en esta PC: %1 (el más reciente: %2). Se quedan aquí; no se envía nada.",
    "Turn everything on again": "Reactivar todo",
    "Restart ii": "Reiniciar ii",
    "Open the error reports": "Abrir los informes de error",
    "Report a problem": "Reportar un problema",
})


# --- C5: open Configuración on a given page (II_SETTINGS_PAGE), like the store's II_STORE_PAGE ----------------------
# The value is matched against the page's file name ("advanced" -> AdvancedConfig.qml, "about" -> About.qml) or is
# the page's index. Used by GlobalStates.openSettings(page) and by tools\dev\settings-check.ps1.
edit(path('settings.qml'), [
    ('''    property int currentPage: 0
''', '''    property int currentPage: initialPage()
    function initialPage() { // ii-windows: II_SETTINGS_PAGE (plan 2026-10-31, C5)
        const wanted = (Quickshell.env("II_SETTINGS_PAGE") || "").toLowerCase().split("/")[0];
        if (!wanted) return 0;
        const index = parseInt(wanted);
        if (!isNaN(index) && index >= 0 && index < root.pages.length) return index;
        for (let i = 0; i < root.pages.length; ++i) {
            const file = root.pages[i].component.split("/").pop().toLowerCase().replace(".qml", "");
            if (file === wanted || file === wanted + "config") return i;
        }
        return 0;
    }
'''),
    ('''                    Component.onCompleted: {
                        source = root.pages[0].component
                    }
''', '''                    Component.onCompleted: {
                        source = root.pages[root.currentPage].component
                    }
'''),
])


# --- C0/C8: how long each settings page takes to load (II_SETTINGS_BENCH=1; tools\dev\settings-check.ps1 reads it) ----
edit(path('settings.qml'), [
    ('''                    id: pageLoader
''', '''                    id: pageLoader
                    // ii-windows (plan 2026-10-31, C0): page load time, from setting the source to the page built.
                    property real benchStarted: Date.now()
                    onLoaded: {
                        if (Quickshell.env("II_SETTINGS_BENCH") === "1")
                            console.info(`settings-bench: ${String(source).split("/").pop()} ${Date.now() - benchStarted} ms`);
                    }
'''),
    ('''                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
''', '''                        ScriptAction { script: pageLoader.benchStarted = Date.now() } // ii-windows: page load time
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
'''),
])

# The navigation rail's "Config file" button: the text is centred in the Revealer, whose height was its children's
# (a binding loop warned on every settings page).
edit(path('modules', 'common', 'widgets', 'FloatingActionButton.qml'), [
    ('''                implicitWidth: reveal ? (buttonText.implicitWidth + root.elementSpacing + contentRowLayout.horizontalMargins) : 0
''', '''                implicitWidth: reveal ? (buttonText.implicitWidth + root.elementSpacing + contentRowLayout.horizontalMargins) : 0
                implicitHeight: buttonText.implicitHeight // ii-windows: no binding loop with the centred text
'''),
])


# A MouseArea filling a row that a layout manages (warned on the Panels page): a HoverHandler does the same.
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        StyledToolTip {
                            extraVisibleCondition: mouseArea.containsMouse
                            text: Translation.tr("Why this is cool:\\nFor non-0 values, it won't trigger when you reach the\\nscreen corner along the horizontal edge, but it will when\\nyou do along the vertical edge")
                        }
                    }
''', '''                    HoverHandler { id: offsetHover } // ii-windows: not a MouseArea inside the row's layout
                    StyledToolTip {
                        extraVisibleCondition: offsetHover.hovered
                        text: Translation.tr("Why this is cool:\\nFor non-0 values, it won't trigger when you reach the\\nscreen corner along the horizontal edge, but it will when\\nyou do along the vertical edge")
                    }
'''),
])
