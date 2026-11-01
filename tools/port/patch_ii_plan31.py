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


# --- B3: the updater's options (read by ii-host and ii-shim update; Configuración > Actualizaciones) ---------------
edit(path('modules', 'common', 'Config.qml'), [
    ('''            property JsonObject tour: JsonObject {
                property bool showOnFirstStart: true // ii-windows: guided tour (modules/ii/tour)
            }
''', '''            property JsonObject tour: JsonObject {
                property bool showOnFirstStart: true // ii-windows: guided tour (modules/ii/tour)
            }

            property JsonObject updates: JsonObject { // ii-windows (plan 2026-10-31, block B)
                property bool autoCheck: true // look for a new version now and then (never during a game)
                property bool autoDownload: true // download it by itself, only on Wi-Fi or cable
                property string channel: "stable" // "stable" | "beta" (prereleases, for testers)
                property bool notify: true // a notification when there is one (else only the dot in the bar)
            }
'''),
])


# --- B3: updates in Configuración (overlay UpdatesConfig.qml), in About and as a dot in the bar ---------------------------
edit(path('settings.qml'), [
    ('''        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
''', '''        {
            name: Translation.tr("Updates"), // ii-windows (plan 2026-10-31, block B)
            icon: "system_update",
            component: "modules/settings/UpdatesConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
'''),
])
edit(path('modules', 'settings', 'About.qml'), [
    ('''                            { icon: "desktop_windows", text: page.windowsName }
''', '''                            { icon: "desktop_windows", text: page.windowsName },
                            { icon: "system_update", text: Updates.attention ? Translation.tr("Update: %1").arg(Updates.latestVersion) : "" }
'''),
    ('''                materialIcon: "system_update_alt"
                mainText: Translation.tr("Check for updates")
                onClicked: Qt.openUrlExternally("https://github.com/TheCarlosS5/ii-windows/releases/latest")
''', '''                materialIcon: "system_update_alt"
                // ii-windows (plan 2026-10-31): the updater, not the releases page.
                mainText: Updates.ready ? Translation.tr("Restart ii now")
                    : Updates.attention ? Translation.tr("Update to %1").arg(Updates.latestVersion) : Translation.tr("Check for updates")
                onClicked: Updates.ready ? Updates.restartNow() : Updates.attention ? Updates.install() : Updates.check()
'''),
])
edit(path('modules', 'ii', 'bar', 'BarContent.qml'), [
    ('''                    spacing: 0

                    Revealer {
                        reveal: Audio.sink?.audio?.muted ?? false
''', '''                    spacing: 0

                    Revealer { // ii-windows (plan 2026-10-31, B3): a new version of ii is there
                        reveal: Updates.attention
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: Updates.ready ? "restart_alt" : "system_update"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Updates.critical ? Appearance.colors.colPrimary : rightSidebarButton.colText
                        }
                    }
                    Revealer {
                        reveal: Audio.sink?.audio?.muted ?? false
'''),
])

add_translations('es_MX', {
    "Updates": "Actualizaciones",
    "Looking for a new version…": "Buscando una versión nueva…",
    "ii %1 is available": "ii %1 está disponible",
    "ii %1 will download on Wi-Fi or cable": "ii %1 se descargará con Wi-Fi o cable",
    "Downloading ii %1… %2%": "Descargando ii %1… %2 %",
    "Checking the download…": "Comprobando la descarga…",
    "ii %1 is downloaded": "ii %1 está descargada",
    "Preparing ii %1…": "Preparando ii %1…",
    "ii %1 is ready: it applies when ii restarts": "ii %1 está lista: se aplica al reiniciar ii",
    "Could not update: %1": "No se pudo actualizar: %1",
    "ii is up to date": "ii está al día",
    "Installed: %1": "Instalada: %1",
    "Last check: %1": "Última búsqueda: %1",
    "%1 MB": "%1 MB",
    "Recommended: it fixes important errors.": "Recomendada: arregla errores importantes.",
    "From your version this one has to be installed by hand: download the Setup from GitHub.":
        "Desde tu versión hay que instalarla a mano: descarga el instalador desde GitHub.",
    "Check now": "Buscar ahora",
    "Download and install": "Descargar e instalar",
    "Restart ii now": "Reiniciar ii ahora",
    "Skip this version": "Omitir esta versión",
    "See on GitHub": "Ver en GitHub",
    "What's new in %1": "Novedades de %1",
    "Options": "Opciones",
    "Look for updates by itself (never during a game)": "Buscar actualizaciones solo (nunca durante un juego)",
    "Download them by itself, only on Wi-Fi or cable": "Descargarlas solo, únicamente con Wi-Fi o cable",
    "Tell me with a notification (otherwise only the dot in the bar)": "Avisarme con una notificación (si no, solo el puntito en la barra)",
    "Channel": "Canal",
    "Beta gets test versions first, for the people who try them": "Beta recibe primero las versiones de prueba, para quienes las prueban",
    "Stable": "Estable",
    "Beta": "Beta",
    "Only versions signed by ii-windows are installed, next to the one you have: if the new one does not start, ii goes back by itself. The only thing sent is a question to GitHub.":
        "Solo se instalan versiones firmadas por ii-windows, al lado de la que tienes: si la nueva no arranca, ii vuelve sola. Lo único que se envía es una consulta a GitHub.",
    "Previous version": "Versión anterior",
    "%1 is still on this PC. Going back restarts ii with it.": "%1 sigue en esta PC. Volver a ella reinicia ii con esa versión.",
    "Go back to %1": "Volver a %1",
    "Update: %1": "Actualización: %1",
    "Update to %1": "Actualizar a %1",
    "Check for updates": "Buscar actualizaciones",
})
