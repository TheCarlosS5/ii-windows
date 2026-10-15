"""Settings, reorganised (feedback 2026-10-15: "poorly organised, only options that work, About empty").

New pages: Home (Quick) / Appearance / Bar / Dock / Desktop (Background) / Panels (Interface) / General /
Services / Advanced / About. The sections are moved by title from the pages upstream has (Interface was a
bag of 14), what does nothing on Windows is dropped, and the About page is rewritten. Runs after
patch_ii_settings.py (which hides what is Linux-only) on the staged tree."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')
TEMPLATES = os.path.join(os.path.dirname(__file__), 'templates')


def path(*parts):
    return os.path.normpath(os.path.join(ROOT, *parts))


def read(p):
    return open(p, encoding='utf-8', newline='').read().replace('\r\n', '\n')


def write(p, text):
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    print('wrote', p)


def split_page(text):
    lines = text.split('\n')
    starts = [i for i, l in enumerate(lines) if l.startswith('    ContentSection {')]
    end = max(i for i, l in enumerate(lines) if l == '}')
    header = '\n'.join(lines[:starts[0]]).rstrip('\n')
    sections = []
    for k, i in enumerate(starts):
        j = starts[k + 1] if k + 1 < len(starts) else end
        sections.append('\n'.join(lines[i:j]).rstrip('\n'))
    return header, sections


def title_of(section):
    m = re.search(r'title: Translation\.tr\("([^"]+)"\)', section)
    return m.group(1) if m else ''


def page_text(header, sections):
    return header + '\n\n' + '\n\n'.join(sections) + '\n}\n'


S = path('modules', 'settings')
PLAIN_HEADER = '''import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true'''

pages = {}
for name in ('AdvancedConfig', 'BackgroundConfig', 'BarConfig', 'GeneralConfig', 'InterfaceConfig', 'ServicesConfig'):
    pages[name] = split_page(read(os.path.join(S, name + '.qml')))


def take(name, *titles):
    """Pull the sections with these titles out of a page and return them."""
    header, sections = pages[name]
    taken = [s for s in sections if title_of(s) in titles]
    missing = [t for t in titles if t not in [title_of(s) for s in taken]]
    if missing:
        sys.exit(f'{name}: no section titled {missing}')
    pages[name] = (header, [s for s in sections if title_of(s) not in titles])
    return taken


def drop(name, *titles):
    take(name, *titles)


# Dropped: Overlay widgets are gone, Lens / music recognition do not work, work-safety is a decoration here.
drop('InterfaceConfig', 'Overlay: General', 'Overlay: Crosshair', 'Overlay: Floating Image',
     'Region selector (screen snipping/Google Lens)')
drop('GeneralConfig', 'Work safety')

dock = take('InterfaceConfig', 'Dock')
appearance_moved = take('AdvancedConfig', 'Color generation') + take('InterfaceConfig', 'Wallpaper selector', 'Fonts') \
    + take('BackgroundConfig', 'Parallax')
try:
    drop('ServicesConfig', 'Music Recognition')
except SystemExit:
    pass

# --- Appearance: transparency and motion first -------------------------------------------------------------
TRANSPARENCY = '''    ContentSection {
        icon: "opacity"
        title: Translation.tr("Transparency and motion")

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: Config.options.appearance.transparency.enable = checked
        }
        ConfigSwitch {
            buttonIcon: "auto_awesome"
            text: Translation.tr("Choose the amount automatically")
            enabled: Config.options.appearance.transparency.enable
            checked: Config.options.appearance.transparency.automatic
            onCheckedChanged: Config.options.appearance.transparency.automatic = checked
            StyledToolTip {
                text: Translation.tr("Follows the wallpaper: busier pictures get more transparent panels")
            }
        }
        ConfigSlider {
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            text: Translation.tr("Panels")
            buttonIcon: "gradient"
            value: Config.options.appearance.transparency.backgroundTransparency
            usePercentTooltip: false
            from: 0
            to: 0.6
            onValueChanged: Config.options.appearance.transparency.backgroundTransparency = Math.round(value * 100) / 100
        }
        ConfigSlider {
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            text: Translation.tr("Content")
            buttonIcon: "layers"
            value: Config.options.appearance.transparency.contentTransparency
            usePercentTooltip: false
            from: 0.2
            to: 1
            onValueChanged: Config.options.appearance.transparency.contentTransparency = Math.round(value * 100) / 100
        }

        ContentSubsection {
            title: Translation.tr("Performance")
            tooltip: Translation.tr("Fewer animations and no transparency: less CPU and memory, better on older laptops")
            ConfigSelectionArray {
                currentValue: (Config.options.appearance.reduceMotion && !Config.options.appearance.transparency.enable) ? "fast" : "normal"
                onSelected: newValue => {
                    const fast = newValue === "fast";
                    Config.options.appearance.reduceMotion = fast;
                    Config.options.appearance.transparency.enable = !fast;
                    Config.options.dock.magnification = fast ? 1 : 1.7;
                }
                options: [
                    { displayName: Translation.tr("Full effects"), icon: "auto_awesome", value: "normal" },
                    { displayName: Translation.tr("Light"), icon: "speed", value: "fast" }
                ]
            }
        }
        ConfigSwitch {
            buttonIcon: "motion_photos_off"
            text: Translation.tr("Reduce animations")
            checked: Config.options.appearance.reduceMotion
            onCheckedChanged: Config.options.appearance.reduceMotion = checked
            StyledToolTip {
                text: Translation.tr("Panels and menus appear without moving; animated widgets stay still")
            }
        }
    }'''

# --- Advanced: what to do when something is wrong, and the Windows integration ---------------------------------------
ADVANCED_SECTIONS = ['''    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Windows integration")

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Keep Windows' wallpaper and ii's the same")
            checked: Config.options.background.syncWindowsWallpaper
            onCheckedChanged: Config.options.background.syncWindowsWallpaper = checked
            StyledToolTip {
                text: Translation.tr("ii takes the wallpaper Windows has, and a wallpaper chosen in ii becomes Windows' too")
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "history"
                mainText: Translation.tr("Put Windows' own wallpaper back")
                onClicked: Quickshell.execDetached(["switchwall", "--restore-windows"])
            }
        }
        ConfigSwitch {
            buttonIcon: "tour"
            text: Translation.tr("Show the tour the first time ii starts")
            checked: Config.options.tour.showOnFirstStart
            onCheckedChanged: Config.options.tour.showOnFirstStart = checked
        }
    }''', '''    ContentSection {
        icon: "backup"
        title: Translation.tr("Back up and restore")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("The backup is the file ii-config.json on your Desktop, without passwords or keys. To use it on another PC, copy it there and import.")
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "upload"
                mainText: Translation.tr("Save my settings")
                onClicked: Quickshell.execDetached(["ii-shim", "config", "export", Quickshell.env("USERPROFILE") + "\\\\Desktop\\\\ii-config.json", "--force"])
            }
            RippleButtonWithIcon {
                materialIcon: "download"
                mainText: Translation.tr("Load saved settings")
                onClicked: Quickshell.execDetached(["ii-shim", "config", "import", Quickshell.env("USERPROFILE") + "\\\\Desktop\\\\ii-config.json", "--apply"])
            }
            RippleButtonWithIcon {
                materialIcon: "folder_open"
                mainText: Translation.tr("Open the settings folder")
                onClicked: Quickshell.execDetached(["explorer.exe", Quickshell.env("LOCALAPPDATA") + "\\\\quickshell\\\\illogical-impulse"])
            }
        }
    }''', '''    ContentSection {
        icon: "health_and_safety"
        title: Translation.tr("If something goes wrong")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("Ctrl+Alt+Shift+R brings Windows' taskbar and desktop back and stops ii. \\"Rescue ii\\" in the Start menu does the same. ii starts again from \\"Start ii\\".")
        }
    }''']

# --- write the new pages ----------------------------------------------------------------------------------------------
write(os.path.join(S, 'AppearanceConfig.qml'), page_text(PLAIN_HEADER, [TRANSPARENCY] + appearance_moved))
write(os.path.join(S, 'DockConfig.qml'), page_text(PLAIN_HEADER, dock))
for name in ('BackgroundConfig', 'BarConfig', 'GeneralConfig', 'InterfaceConfig', 'ServicesConfig'):
    header, sections = pages[name]
    write(os.path.join(S, name + '.qml'), page_text(header, sections))
write(os.path.join(S, 'AdvancedConfig.qml'), page_text(PLAIN_HEADER, ADVANCED_SECTIONS))
write(os.path.join(S, 'About.qml'), open(os.path.join(TEMPLATES, 'About.qml'), encoding='utf-8').read())

# The pages, in the order of the navigation rail.
settings_qml = read(path('settings.qml'))
a = settings_qml.index('    property var pages: [')
b = settings_qml.index('    property int currentPage: 0')
new_pages = '''    property var pages: [
        {
            name: Translation.tr("Home"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            name: Translation.tr("Appearance"),
            icon: "palette",
            component: "modules/settings/AppearanceConfig.qml"
        },
        {
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Dock"),
            icon: "call_to_action",
            component: "modules/settings/DockConfig.qml"
        },
        {
            name: Translation.tr("Desktop"),
            icon: "desktop_windows",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Panels"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            name: Translation.tr("General"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Advanced"),
            icon: "construction",
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]
'''
write(path('settings.qml'), settings_qml[:a] + new_pages + settings_qml[b:])

# --- new options -----------------------------------------------------------------------------------------------------------
edit(path('modules', 'common', 'Config.qml'), [
    ('                property string wallpaperPath: ""\n',
     '                property string wallpaperPath: ""\n'
     '                property bool syncWindowsWallpaper: true // ii-windows: ii and Windows show the same picture\n'),
    ('            property JsonObject osd: JsonObject {\n',
     '            property JsonObject tour: JsonObject {\n'
     '                property bool showOnFirstStart: true // ii-windows: guided tour (modules/ii/tour)\n'
     '            }\n\n'
     '            property JsonObject osd: JsonObject {\n'),
])
edit(path('modules', 'common', 'Persistent.qml'), [
    ('''            property JsonObject ai: JsonObject {
''',
     '''            property JsonObject tour: JsonObject {
                property bool done: false // ii-windows: the guided tour was shown (or skipped)
            }

            property JsonObject ai: JsonObject {
'''),
])
edit(path('panelFamilies', 'IllogicalImpulseFamily.qml'), [
    ('import qs.modules.ii.sidebarRight\n', 'import qs.modules.ii.sidebarRight\nimport qs.modules.ii.tour\n'),
    ('    PanelLoader { phase: 3; component: WallpaperSelector {} }\n',
     '    PanelLoader { phase: 3; component: WallpaperSelector {} }\n    PanelLoader { phase: 3; component: Tour {} } // ii-windows: the guided tour\n'),
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


ES = {
    # navigation
    "Home": "Inicio", "Appearance": "Apariencia", "Dock": "Dock", "Desktop": "Escritorio", "Panels": "Paneles",
    # appearance
    "Transparency and motion": "Transparencia y movimiento", "Transparency": "Transparencia",
    "Choose the amount automatically": "Elegir la cantidad automáticamente",
    "Follows the wallpaper: busier pictures get more transparent panels": "Sigue al fondo: con imágenes más cargadas los paneles son más transparentes",
    "Panels": "Paneles", "Content": "Contenido", "Performance": "Rendimiento",
    "Fewer animations and no transparency: less CPU and memory, better on older laptops": "Menos animaciones y sin transparencia: menos CPU y memoria, mejor en portátiles antiguos",
    "Full effects": "Todos los efectos", "Light": "Ligero", "Reduce animations": "Reducir animaciones",
    "Panels and menus appear without moving; animated widgets stay still": "Paneles y menús aparecen sin moverse; los widgets animados se quedan quietos",
    # advanced
    "Windows integration": "Integración con Windows",
    "Keep Windows' wallpaper and ii's the same": "Mantener el fondo de Windows y el de ii iguales",
    "ii takes the wallpaper Windows has, and a wallpaper chosen in ii becomes Windows' too": "ii toma el fondo que tiene Windows y un fondo elegido en ii pasa a ser también el de Windows",
    "Put Windows' own wallpaper back": "Devolver el fondo original de Windows",
    "Show the tour the first time ii starts": "Mostrar el recorrido la primera vez que arranca ii",
    "Back up and restore": "Copia de seguridad y restauración",
    "The backup is the file ii-config.json on your Desktop, without passwords or keys. To use it on another PC, copy it there and import.": "La copia es el archivo ii-config.json en tu Escritorio, sin contraseñas ni claves. Para usarla en otro PC, cópiala allí e impórtala.",
    "Save my settings": "Guardar mis ajustes", "Load saved settings": "Cargar ajustes guardados",
    "Open the settings folder": "Abrir la carpeta de ajustes",
    "If something goes wrong": "Si algo va mal",
    "Ctrl+Alt+Shift+R brings Windows' taskbar and desktop back and stops ii. \"Rescue ii\" in the Start menu does the same. ii starts again from \"Start ii\".": "Ctrl+Alt+Mayús+R devuelve la barra de tareas y el escritorio de Windows y detiene ii. \"Rescate de ii\" en el menú Inicio hace lo mismo. ii vuelve a arrancar desde \"Iniciar ii\".",
    # about
    "ii-windows": "ii-windows", "development build": "versión de desarrollo",
    "A desktop environment for programmers on Windows 11: the Illogical Impulse shell (Material 3 Expressive) with ideas from macOS, GNOME and Hyprland.": "Un entorno de escritorio para programadores en Windows 11: la shell Illogical Impulse (Material 3 Expressive) con ideas de macOS, GNOME y Hyprland.",
    "Version %1": "Versión %1", "Built %1": "Compilada el %1",
    "Show the tour": "Ver el recorrido", "Shortcuts": "Atajos", "Check for updates": "Buscar actualizaciones",
    "Report a problem": "Reportar un problema", "Open the logs folder": "Abrir la carpeta de registros",
    "Credits": "Créditos", "Built with": "Construido con",
    "Idea, direction, testing and everyday use. ii-windows exists because of the question \"can this be on Windows?\".": "Idea, dirección, pruebas y uso diario. ii-windows existe por la pregunta \"¿se puede tener esto en Windows?\".",
    "AI that wrote the Windows port: the Quickshell backend, the host, the dock, the installer and the fixes, working together with Carlos.": "IA que escribió el port a Windows: el backend de Quickshell, el host, el dock, el instalador y las correcciones, trabajando junto con Carlos.",
    "Creator of Illogical Impulse (dots-hyprland), the shell this is built on, and its contributors.": "Creador de Illogical Impulse (dots-hyprland), la shell sobre la que está hecho esto, y sus colaboradores.",
    "The toolkit ii is written with, by outfoxxed. The Windows backend lives in a fork of it.": "La herramienta con la que está escrito ii, de outfoxxed. El backend de Windows vive en un fork suyo.",
    "Qt 6 and QML · Material Color Utilities (Google) for the colours · Bibata cursors · fastfetch · JetBrains Mono Nerd Font · Google Sans Flex, Space Grotesk and Readex Pro · Breeze icons. ii-windows is free software under the GNU GPL 3; the Quickshell fork is LGPL. Thank you to everyone who published what this stands on.": "Qt 6 y QML · Material Color Utilities (Google) para los colores · cursores Bibata · fastfetch · JetBrains Mono Nerd Font · Google Sans Flex, Space Grotesk y Readex Pro · iconos Breeze. ii-windows es software libre bajo la GNU GPL 3; el fork de Quickshell es LGPL. Gracias a todos los que publicaron aquello sobre lo que esto se apoya.",
    # tour
    "Welcome to ii": "Te damos la bienvenida a ii",
    "ii replaces Windows' taskbar, Start menu and desktop with a different layout. Your apps, files and settings are still Windows'. This tour takes one minute and shows what is where.": "ii reemplaza la barra de tareas, el menú Inicio y el escritorio de Windows con otra distribución. Tus apps, archivos y ajustes siguen siendo los de Windows. Este recorrido dura un minuto y muestra qué hay dónde.",
    "The top bar": "La barra superior",
    "On the left, the active app and the button for the AI sidebar. In the centre, CPU and memory, the desktops and the clock. On the right, the system tray, battery and the quick settings.": "A la izquierda, la app activa y el botón del panel de IA. En el centro, CPU y memoria, los escritorios y el reloj. A la derecha, la bandeja del sistema, la batería y los ajustes rápidos.",
    "Desktops": "Escritorios",
    "Each dot is a virtual desktop with its own windows. Click a dot to go there, or scroll over them. Only the desktops that exist are shown.": "Cada punto es un escritorio virtual con sus propias ventanas. Haz clic en un punto para ir allí, o gira la rueda sobre ellos. Solo se muestran los escritorios que existen.",
    "Search and open apps": "Buscar y abrir apps",
    "Press the Windows key: type to find apps, files or do maths, then Enter. Press Win+Tab for the windows of this desktop, and the button at the bottom for all the apps.": "Pulsa la tecla Windows: escribe para encontrar apps, archivos o hacer cuentas y luego Enter. Win+Tab muestra las ventanas de este escritorio y el botón de abajo todas las apps.",
    "The dock": "El dock",
    "Your pinned and running apps. The icons grow under the cursor. Click opens, right click offers more, drag to reorder, and the pin keeps it always visible. It can sit at the bottom, left or right (Settings > Dock).": "Tus apps ancladas y abiertas. Los iconos crecen bajo el cursor. Clic abre, clic derecho ofrece más, arrastra para reordenar y el pin lo mantiene siempre visible. Puede ir abajo, a la izquierda o a la derecha (Ajustes > Dock).",
    "Quick settings and notifications": "Ajustes rápidos y notificaciones",
    "Wi-Fi, Bluetooth, volume, night light, notifications and the calendar. The switches act right there; open it from the top-right corner.": "Wi-Fi, Bluetooth, volumen, luz nocturna, notificaciones y el calendario. Los interruptores actúan ahí mismo; ábrelo desde la esquina superior derecha.",
    "AI assistant and tools": "Asistente de IA y herramientas",
    "Chat with an AI model (add your free Gemini key with /key), translate text and more. Open it from the top-left button.": "Conversa con un modelo de IA (añade tu clave gratuita de Gemini con /key), traduce texto y más. Ábrelo desde el botón de arriba a la izquierda.",
    "Your desktop": "Tu escritorio",
    "Right click on the desktop for new folders, personalising, the Windows menu and more. \"Edit desktop\" adds clocks, weather, notes and other widgets and lets you move them.": "Clic derecho en el escritorio para nuevas carpetas, personalizar, el menú de Windows y más. \"Editar escritorio\" añade relojes, clima, notas y otros widgets y permite moverlos.",
    "Win+/ shows every shortcut. Win+I opens ii's settings, where you can change almost everything, including this tour.": "Win+/ muestra todos los atajos. Win+I abre los ajustes de ii, donde puedes cambiar casi todo, incluido este recorrido.",
    "Ctrl+Alt+Shift+R brings Windows' taskbar and desktop back at once and stops ii. You can start ii again from the Start menu.": "Ctrl+Alt+Mayús+R devuelve de inmediato la barra de tareas y el escritorio de Windows y detiene ii. Puedes volver a arrancar ii desde el menú Inicio.",
    "Skip": "Saltar", "Back": "Atrás", "Next": "Siguiente", "Start using ii": "Empezar a usar ii",
}
add_translations('es_MX', ES)


# --- one-time migration of settings that were saved with the old defaults ------------------------------------------
# config.json keeps every option once it was written, so the new defaults (transparency on, colour dock icons) only
# reach new installs. Once per install the old defaults are moved to the new ones; later changes stick.
edit(path('modules', 'common', 'Persistent.qml'), [
    ('''            property JsonObject tour: JsonObject {
''',
     '''            property JsonObject migrations: JsonObject {
                property bool ux1: false // ii-windows 2026-10: transparency on, colour dock icons
            }

            property JsonObject tour: JsonObject {
'''),
])
edit(path('shell.qml'), [
    ('''    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()''',
     '''    // ii-windows: runs once, when the settings and the saved state are both loaded.
    QtObject {
        id: uxMigration
        function run() {
            if (!Config.ready || !Persistent.ready) return;
            if (Persistent.states.migrations.ux1) return;
            Persistent.states.migrations.ux1 = true;
            Config.options.appearance.transparency.enable = true;
            Config.options.dock.monochromeIcons = false;
        }
    }
    Connections {
        target: Config
        function onReadyChanged() { uxMigration.run(); }
    }
    Connections {
        target: Persistent
        function onReadyChanged() { uxMigration.run(); }
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        uxMigration.run()'''),
])

# Dock sliders: the labels were cut.
edit(path('modules', 'settings', 'DockConfig.qml'), [
    ('            text: Translation.tr("Icon size")\n', '            text: Translation.tr("Icon size")\n            textWidth: 220\n'),
    ('            text: Translation.tr("Magnification")\n', '            text: Translation.tr("Magnification")\n            textWidth: 220\n'),
    ('            text: Translation.tr("Magnification reach")\n', '            text: Translation.tr("Magnification reach")\n            textWidth: 220\n'),
])
add_translations('es_MX', {"Development build": "Versión de desarrollo"})


# "Force specific monitor" for notifications: the option does not exist in this build (the page logged errors) and the
# example is a Linux monitor name; the notifications follow the active screen.
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Force specific monitor")
            checked: Config.options.notifications.forceMonitor.enable
            onCheckedChanged: {
                Config.options.notifications.forceMonitor.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("If you have multiple monitors and want notifications to only show on one of them, enable this and enter the monitor name below (e.g., eDP-1)")
            }
        }

        ConfigRow {
            enabled: Config.options.notifications.forceMonitor.enable
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Monitor name to show notifications on (e.g., eDP-1)")
                text: Config.options.notifications.forceMonitor.name
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.notifications.forceMonitor.name = text;
                }
            }
        }
''', ''),
])
