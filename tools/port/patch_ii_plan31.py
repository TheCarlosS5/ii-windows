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

            property JsonObject iiUpdates: JsonObject { // ii-windows (plan 2026-10-31, block B; "updates" is upstream's Arch checker)
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
                            { icon: "system_update", text: IiUpdates.attention ? Translation.tr("Update: %1").arg(IiUpdates.latestVersion) : "" }
'''),
    ('''                materialIcon: "system_update_alt"
                mainText: Translation.tr("Check for updates")
                onClicked: Qt.openUrlExternally("https://github.com/TheCarlosS5/ii-windows/releases/latest")
''', '''                materialIcon: "system_update_alt"
                // ii-windows (plan 2026-10-31): the updater, not the releases page.
                mainText: IiUpdates.ready ? Translation.tr("Restart ii now")
                    : IiUpdates.attention ? Translation.tr("Update to %1").arg(IiUpdates.latestVersion) : Translation.tr("Check for updates")
                onClicked: IiUpdates.ready ? IiUpdates.restartNow() : IiUpdates.attention ? IiUpdates.install() : IiUpdates.check()
'''),
])
edit(path('modules', 'ii', 'bar', 'BarContent.qml'), [
    ('''                    spacing: 0

                    Revealer {
                        reveal: Audio.sink?.audio?.muted ?? false
''', '''                    spacing: 0

                    Revealer { // ii-windows (plan 2026-10-31, B3): a new version of ii is there
                        reveal: IiUpdates.attention
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: IiUpdates.ready ? "restart_alt" : "system_update"
                            iconSize: Appearance.font.pixelSize.larger
                            color: IiUpdates.critical ? Appearance.colors.colPrimary : rightSidebarButton.colText
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


# --- F1/E10: microphone, camera and location in use (Windows shows them in its own taskbar, which ii hides) ---------
# Quickshell.Windows PrivacyMonitor (fork, services/privacy.cpp). In the bar's right-side indicators, always visible
# while in use, with the apps' names on hover.
edit(path('modules', 'ii', 'bar', 'BarContent.qml'), [
    ('''                    Revealer { // ii-windows (plan 2026-10-31, B3): a new version of ii is there
''', '''                    Repeater { // ii-windows (plan 2026-10-31, F1): privacy indicators
                        model: [
                            { icon: "mic", apps: PrivacyMonitor.microphone, what: Translation.tr("Using the microphone: %1") },
                            { icon: "videocam", apps: PrivacyMonitor.camera, what: Translation.tr("Using the camera: %1") },
                            { icon: "location_on", apps: PrivacyMonitor.location, what: Translation.tr("Using your location: %1") }
                        ]
                        delegate: Revealer {
                            id: privacyIndicator
                            required property var modelData
                            reveal: (modelData.apps?.length ?? 0) > 0
                            Layout.fillHeight: true
                            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                            Behavior on Layout.rightMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            HoverHandler { id: privacyHover }
                            MaterialSymbol {
                                text: privacyIndicator.modelData.icon
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.m3colors.m3error
                            }
                            StyledToolTip {
                                extraVisibleCondition: privacyHover.hovered
                                text: privacyIndicator.modelData.what.arg((privacyIndicator.modelData.apps ?? []).join(", "))
                            }
                        }
                    }
                    Revealer { // ii-windows (plan 2026-10-31, B3): a new version of ii is there
'''),
    ('''import QtQuick
''', '''import QtQuick
import Quickshell.Windows // ii-windows: PrivacyMonitor
''', 1),
])

add_translations('es_MX', {
    "Using the microphone: %1": "Usando el micrófono: %1",
    "Using the camera: %1": "Usando la cámara: %1",
    "Using your location: %1": "Usando tu ubicación: %1",
})


# --- C5: one Configuración window (Quickshell.Windows SingleInstance): a second Win+I brings the open one forward, on
# the page asked for, instead of opening another process and window.
edit(path('settings.qml'), [
    ('''import Quickshell
''', '''import Quickshell
import Quickshell.Windows // ii-windows: SingleInstance
''', 1),
    ('''    visible: true
    onClosing: Qt.quit()
''', '''    // ii-windows (plan 2026-10-31, C5): shown only once it is clear this is the one settings window.
    visible: false
    onClosing: Qt.quit()
    Connections {
        target: SingleInstance
        function onActivated(argument) {
            const index = root.pageIndex(argument);
            if (index >= 0) root.currentPage = index;
            if (root.visibility === Window.Minimized) root.showNormal();
            root.raise();
            root.requestActivate();
        }
    }
'''),
    ('''    function initialPage() { // ii-windows: II_SETTINGS_PAGE (plan 2026-10-31, C5)
        const wanted = (Quickshell.env("II_SETTINGS_PAGE") || "").toLowerCase().split("/")[0];
        if (!wanted) return 0;
''', '''    function initialPage() { // ii-windows: II_SETTINGS_PAGE (plan 2026-10-31, C5)
        return Math.max(0, root.pageIndex(Quickshell.env("II_SETTINGS_PAGE") || ""));
    }
    function pageIndex(name) { // -1: not a page
        const wanted = (name || "").toLowerCase().split("/")[0];
        if (!wanted) return -1;
'''),
    ('''            if (file === wanted || file === wanted + "config") return i;
        }
        return 0;
    }
''', '''            if (file === wanted || file === wanted + "config") return i;
        }
        return -1;
    }
'''),
    ('''    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
''', '''    Component.onCompleted: {
        if (!SingleInstance.claim("ii-settings", Quickshell.env("II_SETTINGS_PAGE") || "")) {
            Qt.callLater(() => Qt.exit(0)); // the open settings window came forward instead (after the event loop starts)
            return;
        }
        root.visible = true;
        MaterialThemeLoader.reapplyTheme()
'''),
])


# --- C4.2: a slider does not rewrite config.json (and make the shell reload all of it) on every step ----------------
# Config's write timer restarts on every change: with 300 ms instead of 0, dragging writes once, when it stops.
edit(path('settings.qml'), [
    ('''        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
''', '''        Config.readWriteDelay = 300 // ii-windows (plan 2026-10-31, C4.2): sliders write once they stop, not on every step
'''),
])


# --- H1: every text of the modules ii-windows uses has its Spanish (tools/dev/find-untranslated.py) -----------------
add_translations('es_MX', {
    "\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position": "\nClic izquierdo: activar o desactivar\nClic derecho: cambiar el tamaño\nRueda: cambiar de lugar",
    "Always connect": "Conectar siempre",
    "Anti-flash: Strong": "Antidestello: fuerte",
    "Anti-flash: Weak": "Antidestello: suave",
    "Auto, ": "Automático, ",
    "Can only be turned on using the 'Dots' or 'Full' dial style for aesthetic reasons": "Solo se puede activar con la esfera de estilo «Puntos» o «Completa», por estética",
    "Can't be turned on when using 'Numbers' dial style for aesthetic reasons": "No se puede activar con la esfera de estilo «Números», por estética",
    "Checking whether this Windows allows it…": "Comprobando si este Windows lo permite…",
    "Close the last desktop when I leave it empty": "Cerrar el último escritorio cuando lo dejo vacío",
    "Confirm": "Confirmar",
    "Could not save the AI request. Check free disk space and permissions, then send your message again.": "No se pudo guardar la petición a la IA. Revisa el espacio libre y los permisos, y envía el mensaje otra vez.",
    "Download failed": "La descarga falló",
    "Empty desktops are no longer closed automatically": "Los escritorios vacíos ya no se cierran solos",
    "Error": "Error",
    "File attachments are not supported on Windows yet. The attachment was cleared; send your message again without it.": "Los archivos adjuntos aún no funcionan en Windows. Se quitó el adjunto; envía el mensaje otra vez sin él.",
    "Gelbooru key saved (encrypted for your Windows user).": "Clave de Gelbooru guardada (cifrada para tu usuario de Windows).",
    "Gelbooru needs an API key. Create one at gelbooru.com > My Account > Options, then type /gelbooru <user id> <api key> here. It is stored encrypted for your Windows user, not in config.json": "Gelbooru necesita una clave de API. Créala en gelbooru.com > My Account > Options y escribe aquí /gelbooru <id de usuario> <clave>. Se guarda cifrada para tu usuario de Windows, no en config.json",
    "Getting ready to translate": "Preparando la traducción",
    "Images (*.jpg *.jpeg *.png *.gif *.webp *.bmp)": "Imágenes (*.jpg *.jpeg *.png *.gif *.webp *.bmp)",
    "Invalid API provider. Supported: \n- ": "Proveedor de API no válido. Disponibles: \n- ",
    "Invalid model. Supported: \n```\n": "Modelo no válido. Disponibles: \n```\n",
    "Keep the music icon moving when nothing plays (uses a little power)": "Mantener el icono de música en movimiento cuando no suena nada (gasta un poco de energía)",
    "Key input": "Clave",
    "Looks a bit softer and more consistent with different number of sides,\nbut has less impressive morphing": "Se ve un poco más suave y uniforme con distinto número de lados,\npero la transformación es menos llamativa",
    "Makes the clock always rotate. This is extremely expensive\n(expect 50% usage on Intel UHD Graphics) and thus impractical.": "Hace que el reloj gire siempre. Es muy costoso\n(hasta 50 % de uso en gráficas Intel UHD), así que no es práctico.",
    "No connection to the site. Check your internet": "No hay conexión con el sitio. Revisa tu internet",
    "Not available on this version of Windows.": "No disponible en esta versión de Windows.",
    "Not available on this version of Windows: %1": "No disponible en esta versión de Windows: %1",
    "Not available on this version of Windows: its virtual desktops could not be read safely.": "No disponible en esta versión de Windows: sus escritorios virtuales no se pudieron leer con seguridad.",
    "Only a desktop with no windows that you did not name, and only if nothing changed meanwhile. Desktop 1 stays.": "Solo un escritorio sin ventanas y sin nombre puesto por ti, y solo si nada cambió entretanto. El escritorio 1 se queda.",
    "Paste service account key JSON here": "Pega aquí el JSON de la clave de la cuenta de servicio",
    "Provider set to ": "Proveedor cambiado a ",
    "Reading image": "Leyendo la imagen",
    "Reduce motion: no decorative animation in desktop widgets": "Reducir movimiento: sin animaciones decorativas en los widgets del escritorio",
    "Save your Gelbooru user id and API key (stored encrypted, not in config.json)": "Guarda tu id de usuario y tu clave de API de Gelbooru (se guardan cifrados, no en config.json)",
    "Saved    ": "Guardado    ",
    "Screen Translator": "Traductor de pantalla",
    "See setup instructions on the wiki": "Mira las instrucciones de configuración en la wiki",
    "Set your Google Cloud service account key": "Configura la clave de tu cuenta de servicio de Google Cloud",
    "Strong": "Fuerte",
    "The computer will sleep in one minute unless you plug in the charger": "El equipo se suspenderá en un minuto si no conectas el cargador",
    "The site refused the request (%1). It may be blocking this connection, try another provider": "El sitio rechazó la petición (%1). Puede estar bloqueando esta conexión; prueba otro proveedor",
    "Too many requests. Wait a moment and try again": "Demasiadas peticiones. Espera un momento y vuelve a intentarlo",
    "Translating": "Traduciendo",
    "Unknown command: ": "Comando desconocido: ",
    "Unsupported AI authorization header format.": "Formato de cabecera de autorización de IA no admitido.",
    "Uploading image": "Subiendo la imagen",
    "Usage: /gelbooru <user id> <api key>": "Uso: /gelbooru <id de usuario> <clave de API>",
    "Weak": "Suave",
    "You can turn it back on in Settings > Bar > Workspaces.": "Puedes volver a activarlo en Configuración > Barra > Espacios de trabajo.",
})


# --- C2: the widget gallery's texts (overlay WidgetGallery.qml; tools/port/gen_widget_pages.py builds the rest) --------
add_translations('es_MX', {
    "Widgets": "Widgets",
    "Search widgets": "Buscar widgets",
    "%1 of %2 on the desktop. Right click the desktop > Edit desktop to move and resize them.":
        "%1 de %2 en el escritorio. Clic derecho en el escritorio > Editar escritorio para moverlos y cambiarles el tamaño.",
    "Customize": "Personalizar",
    "All widgets": "Todos los widgets",
    "Loading…": "Cargando…",
})

# --- C2/C6: a widget's gear in the desktop's edit mode opens Configuración > Escritorio on that widget's settings ------
edit(path('settings.qml'), [
    ('''        function onActivated(argument) {
            const index = root.pageIndex(argument);
''', '''        function onActivated(argument) {
            SettingsRequest.request(argument); // "page/sub": the page's own part (a widget's settings) follows it
            const index = root.pageIndex(argument);
'''),
])
edit(path('modules', 'ii', 'background', 'widgets', 'WidgetEditFrame.qml'), [
    ('''import QtQuick.Layouts
import qs
''', '''import QtQuick.Layouts
import Quickshell
import qs
'''),
    ('''            EditButton {
                symbol: "visibility_off"
''', '''            EditButton { // ii-windows (plan 2026-10-31, C6): this widget's settings, in the open Configuración if any
                symbol: "settings"
                tip: Translation.tr("Widget settings")
                onClicked: Quickshell.execDetached({
                    command: ["qs", "-p", Quickshell.shellPath("settings.qml")],
                    environment: { "II_SETTINGS_PAGE": "backgroundconfig/" + root.widget.configEntryName }
                })
            }
            EditButton {
                symbol: "visibility_off"
'''),
])
add_translations('es_MX', {
    "Widget settings": "Ajustes del widget",
})

# --- C3: the settings search (overlay SettingsSearchBar.qml / SettingsSearchResults.qml; the index is made by
# tools/port/gen_settings_index.py after this). A result opens its page, scrolls to the setting and lights it up.
edit(path('settings.qml'), [
    ('''import qs.modules.common.widgets
import qs.modules.common.functions as CF
''', '''import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.settings // ii-windows: the settings search
'''),
    ('''            if (file === wanted || file === wanted + "config") return i;
        }
        return -1;
    }
''', '''            if (file === wanted || file === wanted + "config") return i;
        }
        return -1;
    }

    // ii-windows (plan 2026-10-31, C3): the settings search. A result opens its page (and the widget's settings in
    // the gallery), then scrolls to the setting and lights it up for a moment.
    property var searchTarget: null
    function openSearchResult(entry) {
        if (!entry) return;
        searchBar.clear();
        const index = root.pageIndex(entry.p);
        if (entry.sub) SettingsRequest.request(entry.p + "/" + entry.sub);
        if (index >= 0 && index !== root.currentPage) root.currentPage = index;
        root.searchTarget = entry;
        locateTimer.tries = 0;
        locateTimer.restart();
    }
    function loadLazySections(item) { // true if a section had to be made
        if (!item) return false;
        let made = false;
        if (item.isLazySection === true && !item.load) {
            item.load = true;
            made = true;
        }
        const kids = item.children || [];
        for (let i = 0; i < kids.length; ++i) made = root.loadLazySections(kids[i]) || made;
        return made;
    }
    function findSetting(item, text, found) {
        if (!item || found.length > 40) return;
        if (item.title === text || item.text === text || item.mainText === text || item.placeholderText === text)
            found.push(item);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; ++i) root.findSetting(kids[i], text, found);
    }
    function locateSetting(lastTry) { // true once found (or given up on)
        const entry = root.searchTarget;
        const page = pageLoader.item;
        if (!entry || !page || switchAnim.running || pageLoader.status !== Loader.Ready) return false;
        if (root.loadLazySections(page)) return false; // made just now (C4.1): look once they are laid out
        const found = [];
        root.findSetting(page, Translation.tr(entry.l), found);
        const shown = found.filter(i => i.visible && i.width > 0);
        const section = Translation.tr(entry.s);
        const inSection = it => {
            for (let p = it; p; p = p.parent) if (p.title === section) return true;
            return false;
        };
        // In a tab not shown (the clock's settings, C2.4): show that tab, look again once it is laid out.
        const hidden = found.find(i => (!entry.s || inSection(i)) && !i.visible);
        for (let p = hidden; p && !shown.some(i => !entry.s || inSection(i)); p = p.parent) {
            if (p.settingsTab !== undefined && p.tabBar && p.tabBar.currentIndex !== p.settingsTab) {
                p.tabBar.currentIndex = p.settingsTab;
                return false;
            }
        }
        // In its own section ("Activar" is in every widget's); any match only when there is nothing better.
        const item = shown.find(i => !entry.s || inSection(i)) ?? (lastTry ? shown[0] : null);
        if (!item) return false;
        let flick = item.parent;
        while (flick && flick.flickableDirection === undefined) flick = flick.parent;
        const p = item.mapToItem(contentContainer, 0, 0);
        let y = p.y;
        if (flick) { // scrolled with an animation (StyledFlickable): light up where the setting ends up
            const inContent = item.mapToItem(flick.contentItem, 0, 0).y;
            const target = Math.max(0, Math.min(inContent - 60, flick.contentHeight - flick.height));
            if (flick.scrollTargetY !== undefined) flick.scrollTargetY = target;
            flick.contentY = target;
            y = flick.mapToItem(contentContainer, 0, 0).y + inContent - target;
        }
        searchHighlight.x = p.x - 8;
        searchHighlight.y = y - 4;
        searchHighlight.width = item.width + 16;
        searchHighlight.height = item.height + 8;
        searchHighlight.flash();
        return true;
    }
    Timer {
        id: locateTimer
        property int tries: 0
        interval: 120
        repeat: true
        onTriggered: {
            locateTimer.tries += 1;
            if (root.locateSetting(locateTimer.tries >= 20) || locateTimer.tries >= 25) locateTimer.stop();
        }
    }
    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: searchBar.focusField()
    }
'''),
    ('''                                onPressed: root.currentPage = index;
''', '''                                onPressed: { searchBar.clear(); root.currentPage = index; } // ii-windows: leave the search
'''),
    ('''            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
''', '''            Rectangle { // Content container
                id: contentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                // ii-windows (plan 2026-10-31, C3): the settings search, its results over the page while it has text.
                SettingsSearchBar {
                    id: searchBar
                    z: 2
                    anchors { top: parent.top; topMargin: 12; horizontalCenter: parent.horizontalCenter }
                    width: Math.min(600, parent.width - 40)
                    onAccepted: root.openSearchResult(searchResults.results[searchResults.currentIndex] ?? searchResults.results[0])
                    onMoved: step => searchResults.currentIndex = Math.max(0, Math.min(searchResults.results.length - 1, searchResults.currentIndex + step))
                    onQueryChanged: searchResults.currentIndex = 0
                }
                SettingsSearchResults {
                    id: searchResults
                    z: 2
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: searchBar.bottom; topMargin: 4 }
                    visible: searchBar.query !== ""
                    pages: root.pages
                    query: searchBar.query
                    onChosen: entry => root.openSearchResult(entry)
                }
                Rectangle { // the setting a search result led to, lit up for a moment
                    id: searchHighlight
                    z: 3
                    visible: opacity > 0
                    opacity: 0
                    color: "transparent"
                    radius: Appearance.rounding.normal
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                    function flash() { flashAnim.restart(); }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Appearance.colors.colPrimary
                        opacity: 0.12
                    }
                    SequentialAnimation {
                        id: flashAnim
                        NumberAnimation { target: searchHighlight; property: "opacity"; to: 1; duration: 150 }
                        PauseAnimation { duration: 1600 }
                        NumberAnimation { target: searchHighlight; property: "opacity"; to: 0; duration: 500 }
                    }
                }
'''),
    ('''                    anchors.fill: parent
                    opacity: 1.0
''', '''                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: searchBar.bottom }
                    visible: searchBar.query === "" // ii-windows (C3): the search results show instead
                    opacity: 1.0
'''),
])
def fix_translations(code, strings):
    """Replace upstream translations that are wrong (add_translations never overwrites)."""
    file = path('translations', code + '.json')
    with open(file, encoding='utf-8') as f:
        data = json.load(f)
    data.update(strings)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


fix_translations('es_MX', {
    "Earbang protection": "Protección contra subidas bruscas de volumen",  # was "destellos" (flashes)
})
add_translations('es_MX', {
    "Search settings (Ctrl+F)": "Buscar ajustes (Ctrl+F)",
    "Nothing found for \"%1\"": "No se encontró nada para «%1»",
    "%1 results": "%1 resultados",
})

# --- C1/C7: a new page, Rendimiento, made by tools/port/compose_settings_pages.py from sections of the others (which also
# moves window animations and live wallpapers to Apariencia, the bar's notifications to Paneles); General becomes
# Sistema (audio, battery, language, time, sounds).
edit(path('settings.qml'), [
    ('''        {
            name: Translation.tr("General"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
''', '''        {
            name: Translation.tr("System"), // ii-windows (C1): was "General"
            icon: "computer",
            component: "modules/settings/GeneralConfig.qml"
        },
'''),
    ('''        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
''', '''        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Performance"), // ii-windows (plan 2026-10-31, C1): light mode, drawing, other windows
            icon: "speed",
            component: "modules/settings/PerformanceConfig.qml"
        },
'''),
])
add_translations('es_MX', {
    "System": "Sistema",
    "Effects": "Efectos",
    "Performance": "Rendimiento",
})
fix_translations('es_MX', {  # too long beside its number box
    "Timeout duration (if not defined by notification) (ms)": "Tiempo en pantalla (ms) si la app no lo indica",
})

# --- D2: the desktop clocks follow DesktopTime (overlay services/DesktopTime.qml), whose clock stops while apps cover
# every screen: a clock with seconds no longer repaints the wallpaper window each second behind a maximized window.
def desktop_time():
    base = path('modules', 'ii', 'background', 'widgets', 'clock')
    count = 0
    for folder, _, names in os.walk(base):
        for name in names:
            if not name.endswith('.qml'):
                continue
            file = os.path.join(folder, name)
            with open(file, encoding='utf-8', newline='') as f:
                text = f.read()
            new = text
            for old in ('DateTime.clock', 'DateTime.time', 'DateTime.longDate'):
                new = new.replace(old, 'DesktopTime' + old[len('DateTime'):])
            if new != text:
                count += text.count('DateTime.') - new.count('DateTime.')
                with open(file, 'w', encoding='utf-8', newline='') as f:
                    f.write(new)
    if count < 8:
        sys.exit(f'patch_ii_plan31.py (D2): only {count} DateTime uses in the desktop clocks, did upstream move them?')


desktop_time()

# --- F2/F14: Windows waiting for a restart, a full system drive (ii-host syshealth.cpp; services/SystemStatus.qml) ----
edit(path('modules', 'common', 'Config.qml'), [
    ('''            property JsonObject iiUpdates: JsonObject {''', '''            property JsonObject iiSystem: JsonObject { // ii-windows (plan 2026-10-31, F2/F14; read by ii-host)
                property bool restartNotice: true // a notice when Windows needs a restart to finish its updates
                property bool lowDiskNotice: true // a notice (at most daily) when the system drive is nearly full
            }

            property JsonObject iiUpdates: JsonObject {'''),
])
edit(path('modules', 'ii', 'sessionScreen', 'SessionScreen.qml'), [
    ('''                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Reboot")
''', '''                        // ii-windows (plan 2026-10-31, F2): a restart now also installs what Windows Update has waiting.
                        buttonIcon: SystemStatus.rebootRequired ? "system_update_alt" : "restart_alt"
                        buttonText: SystemStatus.rebootRequired ? Translation.tr("Update and reboot") : Translation.tr("Reboot")
'''),
])


def add_section_at_end(file, line):
    with open(file, encoding='utf-8', newline='') as f:
        text = f.read()
    nl = '\r\n' if '\r\n' in text else '\n'
    body = text.rstrip()
    if not body.endswith('}'):
        sys.exit(f'patch_ii_plan31.py: {file} does not end with its closing brace')
    with open(file, 'w', encoding='utf-8', newline='') as f:
        f.write(body[:-1].rstrip() + nl + nl + line + nl + '}' + nl)


add_section_at_end(path('modules', 'settings', 'GeneralConfig.qml'),
                   '    WindowsNoticesSection {} // ii-windows (plan 2026-10-31, F2/F14)')
add_translations('es_MX', {
    "Windows notices": "Avisos de Windows",
    "Tell me when Windows needs a restart to finish its updates": "Avisarme cuando Windows necesite reiniciar para terminar de actualizarse",
    "Tell me when the system drive is running out of space": "Avisarme cuando quede poco espacio en el disco del sistema",
    "Now: Windows is waiting for a restart.": "Ahora: Windows espera un reinicio.",
    "Now: %1 has %2 GB free.": "Ahora: %1 tiene %2 GB libres.",
    "Update and reboot": "Actualizar y reiniciar",
})

# --- F4: Windows' energy saver as a quick toggle (overlay EnergySaverToggle / AndroidEnergySaverToggle) -------------
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'AndroidQuickPanel.qml'), [
    ('''"mic", "audio", "notifications", "powerProfile"]''', '''"mic", "audio", "notifications", "powerProfile", "energySaver"] // ii-windows: + energySaver (F4)'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'androidStyle', 'AndroidToggleDelegateChooser.qml'), [
    ('''    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {''', '''    DelegateChoice { roleValue: "energySaver"; AndroidEnergySaverToggle { // ii-windows (plan 2026-10-31, F4)
        required property int index
        required property var modelData
        buttonIndex: modelData.configIndex ?? -1
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {'''),
])
add_translations('es_MX', {
    "Energy saver": "Ahorro de energía",
    "Windows' energy saver: fewer background tasks and a dimmer screen. Opens its settings":
        "Ahorro de energía de Windows: menos tareas en segundo plano y la pantalla más tenue. Abre su configuración",
    "On": "Activado",
    "Off": "Desactivado",
    "%1 apps can be updated in the store": "%1 apps se pueden actualizar en la tienda",
})

# --- F23: with several screens, the bar and the dock on all of them or only on the main one (Windows' main screen is
# the one at 0,0). The bar's screenList (screen names) still narrows it further.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
''', '''                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property string screens: "all" // ii-windows (F23): "all" | "primary" (only the main screen)
'''),
    ('''                property bool showStore: true // ii-windows: the app store as a tile next to the overview button
''', '''                property bool showStore: true // ii-windows: the app store as a tile next to the overview button
                property string screens: "all" // ii-windows (F23): "all" | "primary" (only the main screen)
'''),
])
edit(path('modules', 'ii', 'bar', 'Bar.qml'), [
    ('''            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;''', '''            // ii-windows (plan 2026-10-31, F23): only the main screen (at 0,0) when asked.
            const screens = Quickshell.screens.filter(s => (Config.options.bar.screens ?? "all") !== "primary" || (s.x === 0 && s.y === 0));
            const list = Config.options.bar.screenList;'''),
])
edit(path('modules', 'ii', 'dock', 'Dock.qml'), [
    ('''        // For each monitor
        model: Quickshell.screens
''', '''        // For each monitor (ii-windows, F23: or only the main one, at 0,0)
        model: Quickshell.screens.filter(s => (Config.options?.dock.screens ?? "all") !== "primary" || (s.x === 0 && s.y === 0))
'''),
])
SCREENS_CHOICE = '''{indent}ContentSubsection {{ // ii-windows (plan 2026-10-31, F23)
{indent}    title: Translation.tr("Screens")
{indent}    tooltip: Translation.tr("With more than one screen: on all of them, or only on the main one (Windows' Settings > Display decides which is the main one)")
{indent}    ConfigSelectionArray {{
{indent}        currentValue: Config.options.{key}.screens ?? "all"
{indent}        onSelected: newValue => Config.options.{key}.screens = newValue
{indent}        options: [
{indent}            {{ displayName: Translation.tr("All screens"), icon: "desktop_windows", value: "all" }},
{indent}            {{ displayName: Translation.tr("Main screen only"), icon: "monitor", value: "primary" }}
{indent}        ]
{indent}    }}
{indent}}}
'''
edit(path('modules', 'settings', 'BarConfig.qml'), [
    ('''            ContentSubsection {
                title: Translation.tr("Automatically hide")''', SCREENS_CHOICE.format(indent='            ', key='bar') + '''            ContentSubsection {
                title: Translation.tr("Automatically hide")'''),
])
edit(path('modules', 'settings', 'DockConfig.qml'), [
    ('''        ContentSubsection {
            title: Translation.tr("Position")''', SCREENS_CHOICE.format(indent='        ', key='dock') + '''        ContentSubsection {
            title: Translation.tr("Position")'''),
])
add_translations('es_MX', {
    "Screens": "Pantallas",
    "With more than one screen: on all of them, or only on the main one (Windows' Settings > Display decides which is the main one)":
        "Con más de una pantalla: en todas o solo en la principal (la principal se elige en Configuración de Windows > Pantalla)",
    "All screens": "Todas las pantallas",
    "Main screen only": "Solo la principal",
})

# --- E16: Configuración > Atajos (overlay ShortcutsConfig.qml; its data from shared/actions.json by
# tools/port/gen_shortcuts_data.py; ii-host reads shortcuts.ini [keys]) -------------------------------------------------
edit(path('settings.qml'), [
    ('''            component: "modules/settings/PerformanceConfig.qml"
        },
''', '''            component: "modules/settings/PerformanceConfig.qml"
        },
        {
            name: Translation.tr("Shortcuts"), // ii-windows (plan 2026-10-31, E16)
            icon: "keyboard",
            component: "modules/settings/ShortcutsConfig.qml"
        },
'''),
])
add_translations('es_MX', {
    "Shortcuts": "Atajos",
    "ii's shortcuts": "Atajos de ii",
    "What each combination does with ii. Those with \"Change\" can take another combination or none; the change works at once. Ctrl+Alt+Shift+R (restore Windows) is never changed.":
        "Qué hace cada combinación con ii. Las que tienen \"Cambiar\" pueden tomar otra combinación o ninguna; el cambio funciona al momento. Ctrl+Alt+Mayús+R (restaurar Windows) no se cambia nunca.",
    "Search shortcuts": "Buscar atajos",
    "Restore all (%1)": "Restaurar todos (%1)",
    "None": "Ninguno",
    "Change": "Cambiar",
    "Cancel": "Cancelar",
    "Save": "Guardar",
    "No shortcut": "Sin atajo",
    "Restore": "Restaurar",
    "Key: K, F9, Tab…": "Tecla: K, F9, Tab…",
    "Free: %1": "Libre: %1",
    "No shortcut matches \"%1\"": "Ningún atajo coincide con \"%1\"",
    "Shift": "Mayús",
    "Print Screen": "Impr Pant",
    "Del": "Supr",
    "Win (tap)": "Win (pulsar sola)",
    "Space": "Espacio",
    "Windows locks the PC with it; no program can take it": "Windows bloquea el equipo con ella; ningún programa puede tomarla",
    "Windows' secure combination; no program can take it": "La combinación segura de Windows; ningún programa puede tomarla",
    "Not a combination ii can take: one key, like K, F9 or Print Screen, with Win, Ctrl or Alt":
        "No es una combinación que ii pueda tomar: una tecla, como K, F9 o Impr Pant, con Win, Ctrl o Alt",
    "It needs Win, Ctrl or Alt: alone (or with Shift) that key is for typing": "Necesita Win, Ctrl o Alt: sola (o con Mayús) esa tecla es para escribir",
    "ii already uses it for \"%1\"": "ii ya la usa para \"%1\"",
    "Windows uses it for \"%1\": ii takes it while ii is on": "Windows la usa para \"%1\": ii la toma mientras ii está activo",
    "PowerToys uses it for \"%1\" if you have it: one of the two will not get it": "PowerToys la usa para \"%1\" si lo tienes: uno de los dos no la recibirá",
    "Windows'": "De Windows",
    "In part": "En parte",
    "Not yet": "Aún no",
    "Games and full screen": "Juegos y pantalla completa",
    "ii's shortcuts step aside": "Los atajos de ii ceden el paso",
    "Automatic: with exclusive full screen and borderless full-screen windows (not browsers). Only exclusive: only exclusive full screen (D3D). Never: ii's shortcuts always work.":
        "Automático: con pantalla completa exclusiva y ventanas sin borde a pantalla completa (no navegadores). Solo exclusiva: solo pantalla completa exclusiva (D3D). Nunca: los atajos de ii funcionan siempre.",
    "Only exclusive": "Solo exclusiva",
    "Never": "Nunca",
    "Programs where ii's shortcuts always step aside (game.exe; other.exe)": "Programas donde los atajos de ii siempre ceden (juego.exe; otro.exe)",
    "Programs where ii does not watch the keyboard at all (anti-cheat games)": "Programas donde ii no vigila el teclado en absoluto (juegos con antitrampas)",
    "Valorant, League of Legends, Fortnite, Apex, Rainbow Six and Tarkov are already on ii's own list. Names separated by ;":
        "Valorant, League of Legends, Fortnite, Apex, Rainbow Six y Tarkov ya están en la lista propia de ii. Nombres separados por ;",
    "Volume and media keys": "Teclas de volumen y multimedia",
    "ii handles the volume keys (its own indicator instead of Windows')": "ii maneja las teclas de volumen (su propio indicador en vez del de Windows)",
    "ii handles play/pause, next and previous (its player and pill)": "ii maneja reproducir/pausar, siguiente y anterior (su reproductor y su píldora)",
    # actions.json texts and reasons the cheat sheet had not needed in Spanish yet
    "Left sidebar, detached": "Barra lateral izquierda, separada",
    "Run (Windows): programs, commands, folders and links": "Ejecutar (Windows): programas, órdenes, carpetas y enlaces",
    "Win+T opens the same overview as Win+Tab; moving through the dock with the keyboard needs the dock navigation of C10.":
        "Win+T abre la misma vista de ventanas que Win+Tab; recorrer el dock con el teclado necesita la navegación del dock (C10).",
    "Windows' own combination; it works with ii's desktops.": "Combinación propia de Windows; funciona con los escritorios de ii.",
    "Windows' own combination.": "Combinación propia de Windows.",
    "Win+B is the left sidebar until the tray can be reached from the keyboard (U06).":
        "Win+B es la barra lateral izquierda hasta que la bandeja se pueda usar con el teclado (U06).",
    "Windows' own Run box opens: it runs everything Windows can (cmd, regedit, %appdata%, paths); ii's search is the Win key.":
        "Se abre el Ejecutar de Windows: ejecuta todo lo que Windows puede (cmd, regedit, %appdata%, rutas); la búsqueda de ii es la tecla Win.",
    "Win+X opens ii's session menu; the system tools menu of Windows (Task Manager, Device Manager...) has no ii counterpart yet.":
        "Win+X abre el menú de sesión de ii; el menú de herramientas de Windows (Administrador de tareas, de dispositivos...) aún no tiene equivalente en ii.",
    "The region is chosen; there is no video encoder behind it yet (C03).": "Se elige la región; todavía no hay un codificador de video detrás (C03).",
    "Windows' lock screen is the only secure one (R03/U08).": "La pantalla de bloqueo de Windows es la única segura (R03/U08).",
    "Ctrl+Alt+Del never reaches a program.": "Ctrl+Alt+Supr nunca llega a un programa.",
    "No process center in ii yet (X03).": "ii aún no tiene un centro de procesos (X03).",
    "No file center in ii yet (X02).": "ii aún no tiene un centro de archivos (X02).",
    "ii's display selector with rollback comes with U05.": "El selector de pantallas de ii, con vuelta atrás, llega con U05.",
    "ii's switcher (ii-host's keyboard router, not this table); over a game or with a shell that does not answer, Windows' own.":
        "El selector de ventanas de ii (el enrutador de teclado de ii-host, no esta tabla); sobre un juego o con la shell sin responder, el de Windows.",
    "A system hotkey of ii-host itself: it works with shortcuts suspended and over games.":
        "Una tecla de sistema del propio ii-host: funciona con los atajos suspendidos y sobre juegos.",
})

# --- C2.4: the clock's settings in tabs (tools/port/gen_widget_pages.py) --------------------------------------------
add_translations('es_MX', {
    "Style": "Estilo",
    "Dial": "Esfera",
    "Hands": "Manecillas",
    "These options are for the Cookie style": "Estas opciones son del estilo Cookie",
})

# --- E1: "Buscar todo" (overlay services/SearchPlus.qml + modules/common/functions/search_plus.js): the launcher also
# finds open windows, ii's and Windows' settings, commands and conversions, in one ranking with the apps.
edit(path('services', 'LauncherSearch.qml'), [
    (r'''        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
''', r'''        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        // ii-windows (plan 2026-10-31, E1): Buscar todo (services/SearchPlus.qml). Not with a prefix that asks for
        // something else. SearchPlus.revision: made again when exchange rates or time zones arrive.
        const plainQuery = !startsWithMathPrefix && !startsWithShellCommandPrefix && !startsWithWebSearchPrefix
            && !root.query.startsWith(Config.options.search.prefix.app) && !root.query.startsWith(Config.options.search.prefix.action);
        const plus = plainQuery && SearchPlus.revision >= 0 ? SearchPlus.rows(root.query) : { conversion: null, rows: [] };
'''),
    (r'''        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {''', r'''        if (plus.conversion) { // ii-windows (E1): "5 km a millas", "100 usd a cop", "15% de 230", "hora en tokio"
            result.push(plus.conversion);
        } else if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {'''),
    (r'''        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);
''', r'''        //////////////// Apps //////////////////
        // ii-windows (E1): apps, windows, commands and settings in one ranking, the likeliest first (an app keeps its
        // place among the apps).
        const typed = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app);
        const ranked = appResultObjects.map((r, i) => ({ score: Math.max(SearchPlus.score(typed, r.name), 0.5) - i * 0.0001, result: r }))
            .concat(plus.rows).map((r, i) => ({ score: r.score, result: r.result, order: i }));
        ranked.sort((a, b) => b.score - a.score || a.order - b.order);
        result = result.concat(ranked.map(r => r.result));
'''),
    (r'''            if (!startsWithNumber && !startsWithMathPrefix)
                result.push(mathResultObject);''', r'''            if (!startsWithNumber && !startsWithMathPrefix && root.mathResult !== "") // ii-windows (E1): not an empty row
                result.push(mathResultObject);'''),
])
edit(path('settings.qml'), [
    (r'''    function openSearchResult(entry) {''', r'''    // "locate:{...}" (II_SETTINGS_PAGE or a second start): a setting the launcher found (plan E1), else null.
    function located(argument) {
        if (!(argument || "").startsWith("locate:")) return null;
        try { return JSON.parse(argument.slice(7)); } catch (e) { return null; }
    }
    function openSearchResult(entry) {'''),
    (r'''    function pageIndex(name) { // -1: not a page
''', r'''    function pageIndex(name) { // -1: not a page
        const target = root.located(name);
        if (target) return root.pageIndex(target.p);
'''),
    (r'''            SettingsRequest.request(argument); // "page/sub": the page's own part (a widget's settings) follows it
''', r'''            const target = root.located(argument);
            if (!target) SettingsRequest.request(argument); // "page/sub": the page's own part (a widget's settings) follows it
'''),
    (r'''            root.raise();
            root.requestActivate();
        }
    }''', r'''            root.raise();
            root.requestActivate();
            if (target) root.openSearchResult(target);
        }
    }'''),
    (r'''        root.visible = true;
''', r'''        root.visible = true;
        const target = root.located(Quickshell.env("II_SETTINGS_PAGE") || "");
        if (target) Qt.callLater(() => root.openSearchResult(target)); // plan E1: the setting the launcher found
'''),
])
edit(path('modules', 'common', 'Config.qml'), [
    (r'''                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
''', r'''                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject everything: JsonObject { // ii-windows (plan 2026-10-31, E1): what the launcher finds besides apps
                    property bool windows: true
                    property bool settings: true
                    property bool windowsSettings: true
                    property bool commands: true
                    property bool conversions: true
                    property bool currency: true // exchange rates from open.er-api.com (only the rates are downloaded)
                }
'''),
])
EVERYTHING_SWITCH = '''            ConfigSwitch {{
                buttonIcon: "{icon}"
                text: Translation.tr("{text}")
                checked: Config.options.search.everything.{key}
                onCheckedChanged: Config.options.search.everything.{key} = checked
            }}
'''
edit(path('modules', 'settings', 'ServicesConfig.qml'), [
    (r'''        ContentSubsection {
            title: Translation.tr("Prefixes")''', r'''        ContentSubsection { // ii-windows (plan 2026-10-31, E1)
            title: Translation.tr("Search everything")
            tooltip: Translation.tr("Besides apps, the search finds these. Try: bloquear, bluetooth, 5 km a millas, 100 usd a cop, hora en tokio")
''' + ''.join(EVERYTHING_SWITCH.format(icon=i, text=t, key=k) for i, t, k in [
        ('select_window', 'Open windows', 'windows'),
        ('settings', "ii's settings", 'settings'),
        ('settings_applications', "Windows' settings", 'windowsSettings'),
        ('terminal', 'Commands (lock, sleep, dark theme, do not disturb...)', 'commands'),
        ('calculate', 'Conversions (units, percentages, time in other cities)', 'conversions'),
        ('currency_exchange', 'Currency conversion (downloads the exchange rates once a day)', 'currency'),
    ]) + r'''        }

        ContentSubsection {
            title: Translation.tr("Prefixes")'''),
])
add_translations('es_MX', {
    # launcher rows
    "Conversion": "Conversión",
    "%1 % of %2": "%1 % de %2",
    "Percentage": "Porcentaje",
    "Getting exchange rates…": "Obteniendo las tasas de cambio…",
    "No exchange rates (no connection?)": "Sin tasas de cambio (¿sin conexión?)",
    "Currency": "Moneda",
    "Currency · rate of %1": "Moneda · tasa del %1",
    "(tomorrow)": "(mañana)",
    "(yesterday)": "(ayer)",
    "same time as here": "la misma hora que aquí",
    "%1 h from here": "%1 h respecto a aquí",
    "Time": "Hora",
    "Turn off do not disturb": "Desactivar No molestar",
    "Turn on do not disturb": "Activar No molestar",
    "Turn off light mode": "Desactivar el modo ligero",
    "Turn on light mode": "Activar el modo ligero",
    "Quick action": "Acción rápida",
    "Switch to": "Ir",
    "Open window": "Ventana abierta",
    "Close": "Cerrar",
    "Windows settings": "Configuración de Windows",
    "ii setting": "Ajuste de ii",
    # Configuración > Servicios > Buscar
    "Search everything": "Buscar todo",
    "Besides apps, the search finds these. Try: bloquear, bluetooth, 5 km a millas, 100 usd a cop, hora en tokio":
        "Además de apps, la búsqueda encuentra esto. Prueba: bloquear, bluetooth, 5 km a millas, 100 usd a cop, hora en tokio",
    "Open windows": "Ventanas abiertas",
    "ii's settings": "Ajustes de ii",
    "Windows' settings": "Ajustes de Windows",
    "Commands (lock, sleep, dark theme, do not disturb...)": "Comandos (bloquear, suspender, tema oscuro, no molestar...)",
    "Conversions (units, percentages, time in other cities)": "Conversiones (unidades, porcentajes, hora en otras ciudades)",
    "Currency conversion (downloads the exchange rates once a day)": "Conversión de monedas (descarga las tasas de cambio una vez al día)",
})

# --- E2: modes (overlay services/Modes.qml, settings ModesConfig.qml, sidebarRight ModesRow.qml) -----------------------
edit(path('modules', 'common', 'Config.qml'), [
    (r'''            property JsonObject search: JsonObject {
''', r'''            property JsonObject modes: JsonObject { // ii-windows (plan 2026-10-31, E2): Configuración > Modos
                property bool enable: true
                property bool notify: true // a notice when a mode starts or ends by itself
                property list<var> list: [
                    { "id": "clase", "name": "", "icon": "school",
                      "apply": { "dnd": true, "theme": "keep", "light": false, "nightLight": false, "keepAwake": true, "volume": -1 },
                      "schedule": { "enable": false, "days": [1, 2, 3, 4, 5], "from": "18:00", "to": "22:00" },
                      "apps": [], "fullscreen": false },
                    { "id": "juego", "name": "", "icon": "sports_esports",
                      "apply": { "dnd": true, "theme": "keep", "light": true, "nightLight": false, "keepAwake": false, "volume": -1 },
                      "schedule": { "enable": false, "days": [0, 1, 2, 3, 4, 5, 6], "from": "20:00", "to": "23:00" },
                      "apps": ["osu!.exe", "VALORANT-Win64-Shipping.exe", "League of Legends.exe", "cs2.exe", "dota2.exe",
                               "RobloxPlayerBeta.exe", "Minecraft.Windows.exe", "FortniteClient-Win64-Shipping.exe",
                               "GenshinImpact.exe", "StarRail.exe", "ZenlessZoneZero.exe", "r5apex.exe", "Overwatch.exe",
                               "RocketLeague.exe", "GTA5.exe", "eldenring.exe", "Cyberpunk2077.exe"],
                      "fullscreen": false },
                    { "id": "presentacion", "name": "", "icon": "co_present",
                      "apply": { "dnd": true, "theme": "keep", "light": false, "nightLight": false, "keepAwake": true, "volume": -1 },
                      "schedule": { "enable": false, "days": [1, 2, 3, 4, 5], "from": "08:00", "to": "10:00" },
                      "apps": [], "fullscreen": false },
                    { "id": "noche", "name": "", "icon": "bedtime",
                      "apply": { "dnd": false, "theme": "dark", "light": false, "nightLight": true, "keepAwake": false, "volume": -1 },
                      "schedule": { "enable": false, "days": [0, 1, 2, 3, 4, 5, 6], "from": "22:00", "to": "06:00" },
                      "apps": [], "fullscreen": false }
                ]
            }
            property JsonObject search: JsonObject {
'''),
])
edit(path('settings.qml'), [
    (r'''            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Performance"),''', r'''            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Modes"), // ii-windows (plan 2026-10-31, E2)
            icon: "auto_mode",
            component: "modules/settings/ModesConfig.qml"
        },
        {
            name: Translation.tr("Performance"),'''),
])
edit(path('shell.qml'), [
    ('''        LockKeys.load() // ii-windows: Caps/Num/Scroll Lock indicator
''', '''        LockKeys.load() // ii-windows: Caps/Num/Scroll Lock indicator
        Modes.load() // ii-windows (plan 2026-10-31, E2): modes start by their hours and apps from the start
'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'SidebarRightContent.qml'), [
    (r'''            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter''', r'''            ModesRow { // ii-windows (plan 2026-10-31, E2): Clase, Juego, Presentación, Noche
                Layout.fillWidth: true
            }

            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter'''),
])
add_translations('es_MX', {
    "Modes": "Modos",
    "Class / Work": "Clase / Trabajo",
    "Game": "Juego",
    "Presentation": "Presentación",
    "Night": "Noche",
    "%1 mode is on": "Modo %1 activado",
    "Because %1 is open. It ends when it closes.": "Porque %1 está abierto. Termina cuando se cierre.",
    "By its hours (%1). Turn it off in the right panel.": "Por su horario (%1). Apágalo en el panel derecho.",
    "%1 mode ended": "Terminó el modo %1",
    "What it changed is back as it was.": "Lo que cambió volvió a como estaba.",
    "A mode changes several things at once and puts them back as they were when it ends. Turn one on in the right panel or from the search (\"modo juego\"), or let it start by itself at its hours or while one of its apps is open.":
        "Un modo cambia varias cosas a la vez y las deja como estaban cuando termina. Actívalo en el panel derecho o desde la búsqueda (\"modo juego\"), o deja que empiece solo a su hora o mientras una de sus apps esté abierta.",
    "Use modes": "Usar los modos",
    "Tell me when a mode starts or ends by itself": "Avisarme cuando un modo empiece o termine solo",
    "Now: %1": "Ahora: %1",
    "Name (empty: %1)": "Nombre (vacío: %1)",
    "What it changes": "Qué cambia",
    "Do not disturb": "No molestar",
    "Light mode (fewer animations and effects)": "Modo ligero (menos animaciones y efectos)",
    "Night light": "Luz nocturna",
    "Keep the screen on": "Mantener la pantalla encendida",
    "Theme as it is": "Tema como esté",
    "Dark": "Oscuro",
    "Light": "Claro",
    "Set the volume": "Fijar el volumen",
    "Volume": "Volumen",
    "At its hours": "A su hora",
    "Start by itself at these hours": "Empezar solo en este horario",
    "Mon": "Lun", "Tue": "Mar", "Wed": "Mié", "Thu": "Jue", "Fri": "Vie", "Sat": "Sáb", "Sun": "Dom",
    "From": "De",
    "to": "a",
    "(it may end the next day: 22:00 to 06:00)": "(puede terminar al día siguiente: 22:00 a 06:00)",
    "While these apps are open": "Mientras estas apps estén abiertas",
    "The program's file name, as Task Manager shows it in Details (osu!.exe). One per line.":
        "El nombre del archivo del programa, como lo muestra el Administrador de tareas en Detalles (osu!.exe). Uno por línea.",
    "For example: osu!.exe": "Por ejemplo: osu!.exe",
    "Also with any app in full screen (not browsers)": "También con cualquier app en pantalla completa (no navegadores)",
    "%1 mode: tap to turn it off": "Modo %1: tócalo para apagarlo",
    "Turn on %1 mode": "Activar el modo %1",
    "On because %1 is open": "Activado porque %1 está abierto",
    "On by its hours (%1)": "Activado por su horario (%1)",
    "Mode %1": "Modo %1",
    "Turn off the %1 mode": "Apagar el modo %1",
    "Mode": "Modo",
    "Turn off": "Apagar",
    "Turn on": "Activar",
})

# --- E3: the "Hoy" tab of the left panel and the class timetable (overlay services/Timetable.qml, sidebarLeft
# Today.qml, settings TimetableSection.qml) -----------------------------------------------------------------------------
edit(path('modules', 'common', 'Config.qml'), [
    (r'''            property JsonObject modes: JsonObject { // ii-windows (plan 2026-10-31, E2): Configuración > Modos
''', r'''            property JsonObject timetable: JsonObject { // ii-windows (plan 2026-10-31, E3): Configuración > Servicios > Horario de clases
                property bool enable: true // reminders before each class
                property int remindMinutes: 10
                property list<var> classes: [] // { id, subject, day (Sunday 0), from, to, room, link }
            }
            property JsonObject modes: JsonObject { // ii-windows (plan 2026-10-31, E2): Configuración > Modos
'''),
])
edit(path('modules', 'settings', 'ServicesConfig.qml'), [
    (r'''    ContentSection {
        icon: "search"''', r'''    TimetableSection {} // ii-windows (plan 2026-10-31, E3)

    ContentSection {
        icon: "search"'''),
])
edit(path('modules', 'ii', 'sidebarLeft', 'SidebarLeftContent.qml'), [
    (r'''    property var tabButtonList: [
''', r'''    property var tabButtonList: [
        {"icon": "today", "name": Translation.tr("Today")}, // ii-windows (plan 2026-10-31, E3)
'''),
    (r'''                contentChildren: [
''', r'''                contentChildren: [
                    today.createObject(), // ii-windows (E3): always there, so no "empty sidebar" placeholder
'''),
    (r'''                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
''', ''),
    (r'''        Component {
            id: aiChat''', r'''        Component {
            id: today
            Today {}
        }
        Component {
            id: aiChat'''),
])
edit(path('shell.qml'), [
    ('''        Modes.load() // ii-windows (plan 2026-10-31, E2): modes start by their hours and apps from the start
''', '''        Modes.load() // ii-windows (plan 2026-10-31, E2): modes start by their hours and apps from the start
        Timetable.load() // ii-windows (plan 2026-10-31, E3): class reminders without opening the panel
'''),
])
add_translations('es_MX', {
    "Today": "Hoy",
    "Good morning": "Buenos días",
    "Good afternoon": "Buenas tardes",
    "Good evening": "Buenas noches",
    "Classes today": "Clases de hoy",
    "Add your classes in Configuración > Servicios > Horario de clases.": "Agrega tus clases en Configuración > Servicios > Horario de clases.",
    "No classes today.": "Hoy no hay clases.",
    "now": "ahora",
    "in %1 min": "en %1 min",
    "Join": "Unirme",
    "To do": "Pendientes",
    "Nothing pending.": "Nada pendiente.",
    "Done": "Hecho",
    "and %1 more": "y %1 más",
    "Add a task and press Enter": "Agrega una tarea y presiona Enter",
    "%1 in %2 min": "%1 en %2 min",
    "%1 starts now": "%1 empieza ahora",
    "Timetable": "Horario",
    "Class timetable": "Horario de clases",
    "Remind me before each class": "Avisarme antes de cada clase",
    "Minutes before": "Minutos antes",
    "Monday": "Lunes", "Tuesday": "Martes", "Wednesday": "Miércoles", "Thursday": "Jueves", "Friday": "Viernes",
    "Saturday": "Sábado", "Sunday": "Domingo",
    "Remove": "Quitar",
    "No classes yet. Add them below: they show in the left panel (Hoy) and you get a notice before each one.":
        "Aún no hay clases. Agrégalas abajo: salen en el panel izquierdo (Hoy) y recibes un aviso antes de cada una.",
    "Add a class": "Agregar una clase",
    "Subject": "Materia",
    "Room or teacher (optional)": "Aula o profesor (opcional)",
    "Meet / Teams / Zoom link (optional)": "Enlace de Meet / Teams / Zoom (opcional)",
    "Add": "Agregar",
    "It needs a subject and a start before its end (24 h, like 18:00).": "Necesita una materia y un inicio antes del final (24 h, como 18:00).",
    "The link has to start with https://": "El enlace tiene que empezar por https://",
})

# --- E5: Bluetooth headphones' battery (fork reads it; overlay services/BluetoothBatteryWatch.qml warns) and the
# system-wide microphone mute (Win+Shift+A, ii-host @micMute) --------------------------------------------------------
edit(path('shell.qml'), [
    ('''        Timetable.load() // ii-windows (plan 2026-10-31, E3): class reminders without opening the panel
''', '''        Timetable.load() // ii-windows (plan 2026-10-31, E3): class reminders without opening the panel
        BluetoothBatteryWatch.load() // ii-windows (plan 2026-10-31, E5): low battery of Bluetooth headphones
'''),
])
add_translations('es_MX', {
    "%1 is running low": "%1 se está quedando sin batería",
    "%1 % battery left": "Le queda %1 % de batería",
    "Mute or unmute the microphone (the whole system)": "Silenciar o activar el micrófono (en todo el sistema)",
})

# --- E6: the dock's Recycle Bin tile (overlay services/RecycleBin.qml) and notification counts on app icons ----------
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property bool showStore: true // ii-windows: the app store as a tile next to the overview button
''', '''                property bool showStore: true // ii-windows: the app store as a tile next to the overview button
                property bool showTrash: true // ii-windows (plan 2026-10-31, E6): the Recycle Bin as a tile
                property bool notificationBadges: true // ii-windows (E6): how many notifications each app has waiting
'''),
])
edit(path('modules', 'settings', 'DockConfig.qml'), [
    ('''            checked: Config.options.dock.showStore
            onCheckedChanged: {
                Config.options.dock.showStore = checked;
            }
        }
''', '''            checked: Config.options.dock.showStore
            onCheckedChanged: {
                Config.options.dock.showStore = checked;
            }
        }
        ConfigSwitch { // ii-windows (plan 2026-10-31, E6)
            buttonIcon: "delete"
            text: Translation.tr("Show the Recycle Bin in the dock (click: open, right click: empty)")
            checked: Config.options.dock.showTrash
            onCheckedChanged: Config.options.dock.showTrash = checked
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Count each app's notifications on its icon")
            checked: Config.options.dock.notificationBadges
            onCheckedChanged: Config.options.dock.notificationBadges = checked
        }
'''),
])
add_translations('es_MX', {
    "Show the Recycle Bin in the dock (click: open, right click: empty)": "Mostrar la papelera en el dock (clic: abrir; clic derecho: vaciar)",
    "Count each app's notifications on its icon": "Contar en cada icono las notificaciones de su app",
})

# --- E9: Configuración > Avanzado > Compatibilidad (overlay CompatSection.qml + compat.json; ii-shim compat) ---------
edit(path('modules', 'settings', 'AdvancedConfig.qml'), [
    ('''    DiagnosticsSection {} // ii-windows: safe mode, error reports (plan 2026-10-31)
''', '''    DiagnosticsSection {} // ii-windows: safe mode, error reports (plan 2026-10-31)

    CompatSection {} // ii-windows (plan 2026-10-31, E9): other customization apps on this PC
'''),
])
add_translations('es_MX', {
    "Compatibility": "Compatibilidad",
    "Looking for other customization apps...": "Buscando otras apps de personalización...",
    "None of the customization apps ii knows is on this PC (StartAllBack, ExplorerPatcher, Windhawk, PowerToys, Rainmeter, Wallpaper Engine...).":
        "No hay en esta PC ninguna de las apps de personalización que ii conoce (StartAllBack, ExplorerPatcher, Windhawk, PowerToys, Rainmeter, Wallpaper Engine...).",
    "These apps also change Windows. ii works with them; this is what to expect.": "Estas apps también cambian Windows. ii funciona con ellas; esto es lo que puedes esperar.",
    "Look again": "Buscar de nuevo",
})

# --- E7: pin a capture on screen (overlay services/PinnedCaptures.qml; ii-shim crop ... pin <file>) -----------------
# The middle click in the region selector pins (left copies, right edits in Paint); also the shortcut regionPin and the
# search's quick action "Fijar una captura".
edit(path('modules', 'ii', 'regionSelector', 'RegionSelection.qml'), [
    ('''    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound } ''',
     '''    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound, Pin } // ii-windows (E7): Pin'''),
    ('''            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;''',
     '''            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit
                : root.mouseButton === Qt.MiddleButton ? RegionSelection.SnipAction.Pin : RegionSelection.SnipAction.Copy; // ii-windows (E7)'''),
    ('''        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //''',
     '''        if (root.action === RegionSelection.SnipAction.Pin) { // ii-windows (plan 2026-10-31, E7): stays on screen
            PinnedCaptures.pinRegion(root.screenshotPath, root.regionX * root.monitorScale, root.regionY * root.monitorScale,
                root.regionWidth * root.monitorScale, root.regionHeight * root.monitorScale, root.screen,
                { x: root.regionX, y: root.regionY, width: root.regionWidth, height: root.regionHeight });
            root.dismiss();
            return;
        }
        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //'''),
    ('''        acceptedButtons: Qt.LeftButton | Qt.RightButton
''', '''        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton // ii-windows (E7): middle pins
'''),
])
edit(path('modules', 'ii', 'regionSelector', 'RegionSelector.qml'), [
    ('''    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition''', '''    function pin() { // ii-windows (plan 2026-10-31, E7)
        root.action = RegionSelection.SnipAction.Pin
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition'''),
    ('''    GlobalShortcut {
        name: "regionOcr"''', '''    GlobalShortcut { // ii-windows (plan 2026-10-31, E7)
        name: "regionPin"
        description: "Pins the selected region on screen"
        onPressed: root.pin()
    }

    GlobalShortcut {
        name: "regionOcr"'''),
])
add_translations('es_MX', {
    "Pin a capture on screen": "Fijar una captura en pantalla",
})

# --- E7: colors in the search (a typed #hex / rgb() in its formats; the color picker's history under "colores") -----
add_translations('es_MX', {
    "Color": "Color",
    "Picked color": "Color elegido",
})

# --- E8: the clipboard with memory: snippets (search.snippets; overlay SnippetsSection.qml; SearchPlus snippetRows),
# "Guardar como fragmento" and "Pegar sin formato" on clipboard entries (ii-shim cliphist paste-text / paste-plain) ------
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property JsonObject everything: JsonObject { // ii-windows (plan 2026-10-31, E1): what the launcher finds besides apps
''', '''                property list<var> snippets: [] // ii-windows (plan 2026-10-31, E8): { name, text }, pasted from the search
                property JsonObject everything: JsonObject { // ii-windows (plan 2026-10-31, E1): what the launcher finds besides apps
'''),
])
edit(path('services', 'LauncherSearch.qml'), [
    ('''                                Cliphist.deleteEntry(entry);
                            }
                        })],
''', '''                                Cliphist.deleteEntry(entry);
                            }
                        }), resultComp.createObject(null, { // ii-windows (plan 2026-10-31, E8)
                            name: Translation.tr("Paste as plain text"),
                            iconName: "format_clear",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Quickshell.execDetached(["ii-shim", "cliphist", "paste-plain", entry]);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Save as snippet"),
                            iconName: "bookmark_add",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                if (!Cliphist.entryIsImage(entry)) SearchPlus.saveSnippet(StringUtils.cleanCliphistEntry(entry));
                            }
                        }), ...(Cliphist.entryIsImage(entry) ? [resultComp.createObject(null, {
                            name: Translation.tr("Copy the text in it (OCR)"),
                            iconName: "document_scanner",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.ocrEntry(entry);
                            }
                        })] : [])],
'''),
])
edit(path('modules', 'settings', 'ServicesConfig.qml'), [
    ('''    TimetableSection {} // ii-windows (plan 2026-10-31, E3)
''', '''    TimetableSection {} // ii-windows (plan 2026-10-31, E3)

    SnippetsSection {} // ii-windows (plan 2026-10-31, E8)
'''),
])
add_translations('es_MX', {
    "Snippet": "Fragmento",
    "Snippets": "Fragmentos",
    "Paste": "Pegar",
    "Paste as plain text": "Pegar como texto sin formato",
    "Save as snippet": "Guardar como fragmento",
    "Copy the text in it (OCR)": "Copiar el texto que tiene (OCR)",
    "Text copied": "Texto copiado",
    "No text found in the image": "No se encontró texto en la imagen",
    "Texts you paste often. Type their name in the search and press Enter: it is pasted into the app you were using.":
        "Textos que pegas seguido. Escribe su nombre en la búsqueda y presiona Enter: se pega en la app que estabas usando.",
    "Add a snippet": "Agregar un fragmento",
    "Name (what you type in the search, e.g. correo)": "Nombre (lo que escribes en la búsqueda, p. ej. correo)",
    "Text": "Texto",
})

# --- E11: digital wellbeing (overlay services/Wellbeing.qml, settings WellbeingSection.qml) ---------------------------
edit(path('modules', 'common', 'Config.qml'), [
    ('''            property JsonObject timetable: JsonObject { // ii-windows (plan 2026-10-31, E3): Configuración > Servicios > Horario de clases
''', '''            property JsonObject wellbeing: JsonObject { // ii-windows (plan 2026-10-31, E11): Configuración > Sistema > Bienestar
                property list<var> goals: [] // { exe, minutes }: a notice once a day when an app passes its time
                property bool eyeBreaks: false // 20-20-20
                property int eyeEvery: 20 // minutes of use between eye breaks
                property bool weekly: true // a summary of the week on Sunday evening
            }
            property JsonObject timetable: JsonObject { // ii-windows (plan 2026-10-31, E3): Configuración > Servicios > Horario de clases
'''),
])
edit(path('modules', 'settings', 'GeneralConfig.qml'), [
    ('''    WindowsNoticesSection {} // ii-windows (plan 2026-10-31, F2/F14)
''', '''    WindowsNoticesSection {} // ii-windows (plan 2026-10-31, F2/F14)

    WellbeingSection {} // ii-windows (plan 2026-10-31, E11)
'''),
])
edit(path('shell.qml'), [
    ('''        BluetoothBatteryWatch.load() // ii-windows (plan 2026-10-31, E5): low battery of Bluetooth headphones
''', '''        BluetoothBatteryWatch.load() // ii-windows (plan 2026-10-31, E5): low battery of Bluetooth headphones
        Wellbeing.load() // ii-windows (plan 2026-10-31, E11): daily limits, eye breaks, the weekly summary
'''),
])
add_translations('es_MX', {
    "Wellbeing": "Bienestar",
    "%1 today on %2": "Llevas %1 hoy en %2",
    "Your daily limit for it is %1. Maybe time for a break?": "Tu límite diario es %1. ¿Una pausa?",
    "Rest your eyes": "Descansa la vista",
    "Look at something about 6 meters away for 20 seconds.": "Mira algo a unos 6 metros durante 20 segundos.",
    "Your week: %1 in front of the screen": "Tu semana: %1 frente a la pantalla",
    "%1 a day on average. Most: %2.": "%1 al día en promedio. Lo que más: %2.",
    "Kind reminders from your screen time (the right panel's Usage tab). Everything stays on this PC.":
        "Recordatorios amables a partir de tu tiempo de pantalla (la pestaña Uso del panel derecho). Todo se queda en esta PC.",
    "Remind me to rest my eyes (20-20-20)": "Recordarme descansar la vista (20-20-20)",
    "Every 20 minutes of use: look at something 6 meters away for 20 seconds.": "Cada 20 minutos de uso: mira algo a 6 metros durante 20 segundos.",
    "A summary of my week on Sunday evening": "Un resumen de mi semana el domingo por la noche",
    "Daily limits": "Límites diarios",
    "A notice once a day when an app passes its time.": "Un aviso al día cuando una app pasa su tiempo.",
    "minutes": "minutos",
    "Add a limit to one of today's apps:": "Agregar un límite a una de las apps de hoy:",
    "No screen time today yet: once ii has counted a while, today's apps show here to choose from.":
        "Aún no hay tiempo de pantalla de hoy: cuando ii lleve un rato contando, aquí salen las apps de hoy para elegir.",
})
