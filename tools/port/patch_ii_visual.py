"""Visual polish round of 2026-10-16: texts that still showed in English or Linux terms, a label cut by its
slider, the separator of the wallpaper places, minimized windows in the overview, the cheatsheet keys.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


def add_translations(code, strings, override=False):
    file = path('translations', code + '.json')
    with open(file, encoding='utf-8') as f:
        data = json.load(f)
    for key, value in strings.items():
        if override:
            data[key] = value
        else:
            data.setdefault(key, value)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


ES = {
    # Notifications: relative times.
    "Now": "Ahora",
    "Yesterday": "Ayer",
    # Calendar: the weekday header (Monday first).
    "Mo": "Lu", "Tu": "Ma", "We": "Mi", "Th": "Ju", "Fr": "Vi", "Sa": "Sá", "Su": "Do",
    # Media controls with nothing playing (the Linux text spoke of MPRIS).
    "Play music or a video in any app\nand its controls show up here": "Pon música o un vídeo en cualquier app\ny sus controles aparecerán aquí",
    # Wallpaper selector: the places on the left.
    "Documents": "Documentos",
    "Downloads": "Descargas",
    "Pictures": "Imágenes",
    "Videos": "Vídeos",
    "Wallpapers": "Fondos",
    # Overview: a minimized window has no picture, only its icon.
    "Minimized": "Minimizada",
    # Cheatsheet: categories and descriptions (shared/actions.json is English).
    "Shell": "Entorno",
    "Screenshot": "Capturas",
    "Safety": "Seguridad",
    "Uncategorized": "Sin categoría",
    "Search apps, files and math (tap the key)": "Buscar apps, archivos y hacer cuentas (toca la tecla)",
    "Search": "Buscar",
    "Overview of open windows": "Vista de las ventanas abiertas",
    "Navigate open windows (the overview)": "Recorrer las ventanas abiertas (la vista general)",
    "Left sidebar": "Panel izquierdo",
    "Right sidebar (calendar)": "Panel derecho (calendario)",
    "Right sidebar (quick settings, notifications)": "Panel derecho (ajustes rápidos y notificaciones)",
    "Clipboard history": "Historial del portapapeles",
    "Emoji picker": "Selector de emojis",
    "Media controls": "Controles multimedia",
    "Show or hide the bar": "Mostrar u ocultar la barra",
    "On-screen keyboard": "Teclado en pantalla",
    "This cheatsheet": "Esta hoja de atajos",
    "Show desktop (again to restore)": "Mostrar el escritorio (otra vez para volver)",
    "Restart ii": "Reiniciar ii",
    "Color picker (copies #RRGGBB)": "Selector de color (copia #RRGGBB)",
    "Wallpaper selector": "Selector de fondos",
    "Random wallpaper": "Fondo aleatorio",
    "Toggle light/dark": "Cambiar entre claro y oscuro",
    "ii settings": "Configuración de ii",
    "Run: programs and links (opens ii's search)": "Ejecutar: programas y enlaces (abre la búsqueda de ii)",
    "Session menu (power, sign out, lock)": "Menú de sesión (apagar, cerrar sesión, bloquear)",
    "Close the window in front (like Alt+F4)": "Cerrar la ventana de delante (como Alt+F4)",
    "Go to desktop 1-10 (creates one if it doesn't exist)": "Ir al escritorio 1-10 (lo crea si no existe)",
    "Move the window in front to desktop 1-10": "Mover la ventana de delante al escritorio 1-10",
    "Previous / next desktop (Windows)": "Escritorio anterior / siguiente (Windows)",
    "New desktop (Windows)": "Nuevo escritorio (Windows)",
    "Close this desktop (Windows)": "Cerrar este escritorio (Windows)",
    "Region screenshot": "Capturar una región",
    "Region screenshot (Print Screen)": "Capturar una región (Impr Pant)",
    "Translate a region": "Traducir una región",
    "Record a region": "Grabar una región",
    "Session menu, on the desktop": "Menú de sesión, sobre el escritorio",
    "Lock (Windows)": "Bloquear (Windows)",
    "Security options (Windows)": "Opciones de seguridad (Windows)",
    "Task Manager (Windows)": "Administrador de tareas (Windows)",
    "File Explorer": "Explorador de archivos",
    "Display modes (Windows)": "Modos de pantalla (Windows)",
    "Switch windows": "Cambiar de ventana",
    "Maximize / snap": "Maximizar / acoplar",
    "Panic: restore Windows' taskbar and desktop, stop ii": "Pánico: detiene ii y devuelve la barra de Windows",
    # Date formats (Qt format strings: the Spanish order is "viernes, 16 de octubre").
    "dddd, MMMM dd": "dddd, d 'de' MMMM",
}
add_translations('es_MX', ES)

# --- Notifications: "Now" / "Yesterday" were never translated, older dates read "October 14" ----------------
edit(path('modules', 'common', 'widgets', 'NotificationGroup.qml'), [
    ('text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)',
     'text: Translation.tr(NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time))'),
])
edit(path('modules', 'common', 'functions', 'NotificationUtils.qml'), [
    ('return Qt.formatDateTime(messageTime, "MMMM dd");',
     'return Qt.locale().toString(messageTime, "d MMM"); // ii-windows: in the system language'),
])

# --- Bar: the clock's popup said "viernes, octubre 16, 2026" (the English order in Spanish words) ----------
edit(path('modules', 'ii', 'bar', 'ClockWidgetPopup.qml'), [
    ('property string formattedDate: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM dd, yyyy")',
     'property string formattedDate: Qt.locale().toString(DateTime.clock.date, Qt.locale().dateFormat(Locale.LongFormat))'),
])
edit(path('services', 'DateTime.qml'), [
    ('property string collapsedCalendarFormat: Qt.locale().toString(clock.date, "dddd, MMMM dd")',
     'property string collapsedCalendarFormat: Qt.locale().toString(clock.date, Translation.tr("dddd, MMMM dd"))'),
])

# --- Media controls with nothing playing: Windows words, and the text no longer runs out of its card -------
edit(path('modules', 'ii', 'mediaControls', 'MediaControls.qml'), [
    ('text: Translation.tr("Make sure your player has MPRIS support\\nor try turning off duplicate player filtering")',
     'text: Translation.tr("Play music or a video in any app\\nand its controls show up here")'),
])

# --- Settings: a slider's label was cut by the slider ("Volumen de la inte|") --------------------------------
edit(path('modules', 'common', 'widgets', 'ConfigSlider.qml'), [
    ('''            id: labelWidget
            Layout.preferredWidth: root.textWidth''',
     '''            id: labelWidget
            Layout.preferredWidth: Math.max(root.textWidth, implicitWidth) // ii-windows: long (Spanish) labels''')
])

# --- Wallpaper selector: the places in the user's language, and a line instead of a "---" button ----------
edit(path('modules', 'ii', 'wallpaperSelector', 'WallpaperSelectorContent.qml'), [
    ('''                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    text: quickDirButton.modelData.name
                                }''',
     '''                                StyledText {
                                    Layout.fillWidth: true
                                    visible: quickDirButton.modelData.name !== "---"
                                    horizontalAlignment: Text.AlignLeft
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    text: Translation.tr(quickDirButton.modelData.name)
                                }
                                Rectangle {
                                    // ii-windows: the separator is a line, not the text "---"
                                    visible: quickDirButton.modelData.name === "---"
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Appearance.colors.colOutlineVariant
                                }'''),
])

# --- Overview: a minimized window is only an icon in an empty box; say what it is --------------------------
edit(path('modules', 'ii', 'overview', 'OverviewWindow.qml'), [
    ('''        StyledImage {
            id: windowIcon''',
     '''        StyledText {
            // ii-windows: Windows gives no picture of a minimized window
            visible: (root.windowData?.hidden ?? false) && root.centerIcons
            anchors {
                top: windowIcon.bottom
                topMargin: 8
                horizontalCenter: parent.horizontalCenter
            }
            width: Math.min(implicitWidth, parent.width - 16)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Minimized")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledImage {
            id: windowIcon'''),
])

# --- Cheatsheet: Spanish descriptions, readable keys for ranges, F-keys no longer hidden -------------------
# As wide as its columns (up to 90 % of the screen) instead of a fixed 70 %: in Spanish at 125 % the last
# column ran out of the panel, behind a scroll nobody finds.
edit(path('modules', 'ii', 'cheatsheet', 'CheatsheetKeybinds.qml'), [
    ('implicitWidth: QsWindow?.window?.screen.width * 0.7 ?? 0',
     'implicitWidth: Math.min((QsWindow?.window?.screen.width ?? 0) * 0.9, Math.max((QsWindow?.window?.screen.width ?? 0) * 0.5, flow.implicitWidth + Appearance.rounding.small * 2 + 2))'),
])
CS = path('modules', 'ii', 'cheatsheet', 'CheatsheetKeybindsCategory.qml')
edit(CS, [
    ('''        "Slash": "/",
''', '''        "Slash": "/",
        "Period": ".", // ii-windows: Win + . (the emoji picker) read "Period"
'''),
    ('text: root.isCategorized ? root.categoryName : "Uncategorized"',
     'text: Translation.tr(root.isCategorized ? root.categoryName : "Uncategorized")'),
    # "F4" counted as "a key with a number other than 1", the way 2..0 of a 1..0 range are hidden.
    ('''        if (key.includes("mouse") || key.includes("page")) return false;
        // Contains non-1 number''',
     '''        if (key.includes("mouse") || key.includes("page")) return false;
        if (/^F\\d+$/.test(key) || key.includes("-") || key.includes("/")) return false; // ii-windows: F4, 1-0, Left/Right
        // Contains non-1 number'''),
    ('''    function transformKey(key) {
        const replaced = root.keySubstitutions[key] || key;''',
     '''    function transformKey(key) {
        // ii-windows: our list writes ranges as one key
        if (key === "1-0") return "1 … 0";
        if (key === "Left/Right") return "← / →";
        const replaced = root.keySubstitutions[key] || key;'''),
    ('''        const decategorized = description.replace(regex, "");
        if (!containsFirstRepetitive(bind)) return decategorized;''',
     '''        const decategorized = description.replace(regex, "");
        if (!containsFirstRepetitive(bind) || bind.key.includes("-") || bind.key.includes("/")) return Translation.tr(decategorized);'''),
    ('''        const dedirectioned = denumbered.replace(/ \\b(left|right|up|down)\\b/i, " <Direction>");
        return dedirectioned;''',
     '''        const dedirectioned = denumbered.replace(/ \\b(left|right|up|down)\\b/i, " <Direction>");
        return Translation.tr(dedirectioned);'''),
])
# --- Frosted glass behind the panels (modules/common/widgets/WallpaperBlur.qml) -----------------------------
# Hyprland blurs what is behind ii's translucent panels; Windows does not, so with transparency on the
# wallpaper and the desktop widgets showed sharp through the sidebars and hurt reading.
GLASS = '{indent}WallpaperBlur {{ anchors.fill: {t}; radius: {t}.radius; tint: {t}.color; inset: {t}.border.width }} // ii-windows: frosted glass\n'


def glass(file, anchor, indent, target='parent'):
    # `target` by id where the Rectangle's children are re-parented (`parent` is null while they bind)
    edit(file, [(anchor, anchor + GLASS.format(indent=indent, t=target))])


edit(path('modules', 'common', 'Config.qml'), [
    ('''                property JsonObject transparency: JsonObject {
                    property bool enable: true''',
     '''                property JsonObject transparency: JsonObject {
                    property bool blurBehind: true // ii-windows: the blurred wallpaper behind translucent panels
                    property bool enable: true'''),
])
glass(path('modules', 'ii', 'sidebarRight', 'SidebarRightContent.qml'), '''        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
''', '        ')
# The left sidebar's background gets its children replaced (contentParent.children = [...]): the glass goes
# under it as a sibling, sliding with it, and the background's own translucent colour is the tint.
edit(path('modules', 'ii', 'sidebarLeft', 'SidebarLeft.qml'), [
    ('''            Rectangle {
                id: sidebarLeftBackground
                transform: Translate { x: -panelWindow.slide * panelWindow.width }
''',
     '''            WallpaperBlur { // ii-windows: frosted glass
                anchors.fill: sidebarLeftBackground
                transform: Translate { x: -panelWindow.slide * panelWindow.width }
                radius: sidebarLeftBackground.radius
                inset: sidebarLeftBackground.border.width
                tint: "transparent"
                minTintAlpha: 0.17 // with the background's colour on top: at least half opaque, as elsewhere
            }
            Rectangle {
                id: sidebarLeftBackground
                transform: Translate { x: -panelWindow.slide * panelWindow.width }
'''),
])
edit(path('modules', 'common', 'widgets', 'NotificationGroup.qml'), [
    ('''        color: popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
''',
     '''        color: popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        Loader { // ii-windows: frosted glass under a popup (the sidebar's list sits on its own glass)
            active: root.popup
            anchors.fill: parent
            sourceComponent: WallpaperBlur { radius: background.radius; tint: background.color }
        }
'''),
])
glass(path('modules', 'ii', 'mediaControls', 'MediaControls.qml'), '''                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
''', '                        ')
glass(path('modules', 'ii', 'cheatsheet', 'Cheatsheet.qml'), '''                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.windowRounding
''', '                ')
glass(path('modules', 'ii', 'wallpaperSelector', 'WallpaperSelectorContent.qml'), '''        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
''', '        ')
glass(path('modules', 'ii', 'onScreenKeyboard', 'OnScreenKeyboard.qml'), '''                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
''', '                ')

edit(path('modules', 'settings', 'AppearanceConfig.qml'), [
    ('''            StyledToolTip {
                text: Translation.tr("Follows the wallpaper: busier pictures get more transparent panels")
            }
        }
''',
     '''            StyledToolTip {
                text: Translation.tr("Follows the wallpaper: busier pictures get more transparent panels")
            }
        }
        ConfigSwitch {
            buttonIcon: "blur_medium"
            text: Translation.tr("Blur the wallpaper behind panels")
            enabled: Config.options.appearance.transparency.enable
            checked: Config.options.appearance.transparency.blurBehind
            onCheckedChanged: Config.options.appearance.transparency.blurBehind = checked
            StyledToolTip {
                text: Translation.tr("Windows does not blur what is behind a translucent window: ii draws the wallpaper blurred behind its panels so their text stays easy to read.")
            }
        }
'''),
])
add_translations('es_MX', {
    "Blur the wallpaper behind panels": "Desenfocar el fondo detrás de los paneles",
    "Windows does not blur what is behind a translucent window: ii draws the wallpaper blurred behind its panels so their text stays easy to read.":
        "Windows no desenfoca lo que hay detrás de una ventana translúcida: ii dibuja el fondo de pantalla desenfocado detrás de sus paneles para que el texto se lea bien.",
})
print('patch_ii_visual: ok')
