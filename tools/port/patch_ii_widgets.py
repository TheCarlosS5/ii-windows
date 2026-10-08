"""Desktop widgets on Windows: more of them (ii's calendar, to-do and timer panels, resources,
a note, a Japanese clock), a desktop edit mode (grid, drag from anywhere, per-widget size), the
music widget's spectrum, and their options in ii's settings. Exact-match edits of the staged
tree, like patch_ii.py (run after it)."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- Edit mode: one flag for every screen's desktop.
edit(path('GlobalStates.qml'), [
    ('    property bool wallpaperSelectorOpen: false\n',
     '    property bool wallpaperSelectorOpen: false\n'
     '    property bool desktopEditMode: false // ii-windows: desktop widgets being arranged\n'),
])

# --- Every desktop widget: a size (scale from its top-left corner, kept in its config as
# widgetScale; widgets that size themselves, like the photo, set handlesOwnScale), drops snap to
# the edit grid, and the edit frame on top while editing.
edit(path('modules', 'ii', 'background', 'widgets', 'AbstractBackgroundWidget.qml'), [
    ('    property bool visibleWhenLocked: false\n',
     r'''    property bool visibleWhenLocked: false
    // ii-windows: size and edit mode.
    property bool handlesOwnScale: false
    readonly property real sizeFactor: handlesOwnScale ? (configEntry.scale ?? 1) : (configEntry.widgetScale ?? 1)
    readonly property real widgetScale: handlesOwnScale ? 1 : Math.max(0.4, Math.min(3, configEntry.widgetScale ?? 1))
    function resizeBy(delta) {
        const key = handlesOwnScale ? "scale" : "widgetScale";
        configEntry[key] = Math.max(0.3, Math.min(3, Math.round(((configEntry[key] ?? 1) + delta) * 10) / 10));
    }
    function saveDrop() {
        if (GlobalStates.desktopEditMode) {
            const grid = 32;
            root.x = Math.max(0, Math.round(root.x / grid) * grid);
            root.y = Math.max(0, Math.round(root.y / grid) * grid);
        }
        root.targetX = root.x;
        root.targetY = root.y;
        configEntry.x = root.targetX;
        configEntry.y = root.targetY;
    }
    WidgetEditFrame {
        widget: root
    }
'''),
    ('    property real targetX: Math.max(0, Math.min(configEntry.x < 0 ? scaledScreenWidth - width + configEntry.x : configEntry.x, scaledScreenWidth - width))',
     '    property real targetX: Math.max(0, Math.min(configEntry.x < 0 ? scaledScreenWidth - width * widgetScale + configEntry.x : configEntry.x, scaledScreenWidth - width * widgetScale))'),
    ('    property real targetY: Math.max(0, Math.min(configEntry.y < 0 ? scaledScreenHeight - height + configEntry.y : configEntry.y, scaledScreenHeight - height))',
     '    property real targetY: Math.max(0, Math.min(configEntry.y < 0 ? scaledScreenHeight - height * widgetScale + configEntry.y : configEntry.y, scaledScreenHeight - height * widgetScale))'),
    ('    scale: (draggable && containsPress) ? 1.05 : 1\n',
     '    transformOrigin: Item.TopLeft\n'
     '    scale: ((draggable && containsPress) ? 1.05 : 1) * widgetScale\n'),
    ('''    onReleased: {
        root.targetX = root.x;
        root.targetY = root.y;
        configEntry.x = root.targetX;
        configEntry.y = root.targetY;
    }''',
     '''    onReleased: root.saveDrop()'''),
])

# The photo sizes its image itself (configEntry.scale): − / + change that.
edit(path('modules', 'ii', 'background', 'widgets', 'photo', 'PhotoWidget.qml'), [
    ('    configEntryName: "photo"\n',
     '    configEntryName: "photo"\n    handlesOwnScale: true\n'),
])

# --- Config entries.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                    property JsonObject media: JsonObject {
                        property bool enable: true
''',
     '''                    property JsonObject media: JsonObject {
                        property bool enable: true
                        property bool spectrum: true
'''),
    ('''                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                    }
''',
     '''                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                    }
                    // ii-windows: more desktop widgets (all draggable; x/y < 0 = from the right/bottom).
                    property JsonObject calendar: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: -330
                        property real y: 72
                    }
                    property JsonObject todo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: -720
                        property real y: 72
                    }
                    property JsonObject timer: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: -720
                        property real y: 480
                    }
                    property JsonObject resources: JsonObject {
                        property bool enable: false
                        property bool showSwap: true
                        property string placementStrategy: "free"
                        property real x: -330
                        property real y: 420
                    }
                    property JsonObject notes: JsonObject {
                        property bool enable: false
                        property string text: ""
                        property int fontSize: 16
                        property string placementStrategy: "free"
                        property real x: 640
                        property real y: 120
                    }
                    property JsonObject japaneseClock: JsonObject {
                        property bool enable: false
                        property bool vertical: true
                        property bool showDate: true
                        property bool showSeconds: false
                        property bool card: false
                        property string placementStrategy: "free"
                        property real x: 900
                        property real y: 120
                    }
'''),
])

# --- The wallpaper: new widgets, the edit grid under them, the edit bar above.
CARD = '''                FadeLoader {
                    shown: Config.options.background.widgets.%s.enable
                    sourceComponent: %s {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

'''
new_loaders = ''.join(CARD % pair for pair in [
    ('calendar', 'CalendarCard'), ('todo', 'TodoCard'), ('timer', 'TimerCard'),
    ('resources', 'ResourcesCard'), ('notes', 'NotesCard'), ('japaneseClock', 'JapaneseClock'),
])
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('import qs.modules.ii.background.widgets.weather\n',
     'import qs.modules.ii.background.widgets.weather\nimport qs.modules.ii.background.widgets.card\n'),
    ('''                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable''',
     new_loaders + '''                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable'''),
    ('            WidgetCanvas {\n                id: widgetCanvas\n',
     '            DesktopEditGrid {\n                anchors.fill: parent\n            }\n\n'
     '            WidgetCanvas {\n                id: widgetCanvas\n'),
    ('            DesktopMenu {\n',
     '            DesktopEditBar {}\n\n            DesktopMenu {\n'),
])

# --- Settings > Background: every desktop widget's options.
def enable_row(key):
    return f'''        ConfigSwitch {{
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.background.widgets.{key}.enable
            onCheckedChanged: Config.options.background.widgets.{key}.enable = checked
        }}
'''


def switch(key, prop, icon, label):
    return f'''        ConfigSwitch {{
            buttonIcon: "{icon}"
            text: Translation.tr("{label}")
            checked: Config.options.background.widgets.{key}.{prop}
            onCheckedChanged: Config.options.background.widgets.{key}.{prop} = checked
        }}
'''


def size_slider(key, prop='widgetScale'):
    return f'''        ConfigSlider {{
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Size")
            from: 0.4
            to: 3
            stopIndicatorValues: [1]
            value: Config.options.background.widgets.{key}.{prop} ?? 1
            onValueChanged: Config.options.background.widgets.{key}.{prop} = Math.round(value * 10) / 10
        }}
'''


def section(icon, title, body):
    return f'''    ContentSection {{
        icon: "{icon}"
        title: Translation.tr("{title}")

{body}    }}

'''


sections = ''.join([
    section('dashboard_customize', 'Desktop widgets', '''        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Right click the desktop > Edit desktop to move widgets on a grid and resize them with − and +. The sizes here are the same.")
        }
''' + '''        ContentSubsectionLabel { text: Translation.tr("Clock") }
''' + size_slider('clock') + '''        ContentSubsectionLabel { text: Translation.tr("Weather") }
''' + size_slider('weather')),
    section('music_note', 'Widget: Music', enable_row('media')
            + switch('media', 'spectrum', 'graphic_eq', 'Spectrum behind the cover') + size_slider('media')),
    section('image', 'Widget: Photo', enable_row('photo') + '''        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Image path or https link")
            text: Config.options.background.widgets.photo.source
            wrapMode: TextEdit.Wrap
            onTextChanged: Qt.callLater(() => { Config.options.background.widgets.photo.source = text; })
        }
''' + size_slider('photo', 'scale')),
    section('folder_open', 'Widget: Recent files', enable_row('folder') + '''        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Folder (empty: Downloads)")
            text: Config.options.background.widgets.folder.path
            wrapMode: TextEdit.Wrap
            onTextChanged: Qt.callLater(() => { Config.options.background.widgets.folder.path = text; })
        }
        ConfigSpinBox {
            icon: "format_list_numbered"
            text: Translation.tr("Files shown")
            value: Config.options.background.widgets.folder.maxItems
            from: 3
            to: 15
            stepSize: 1
            onValueChanged: Config.options.background.widgets.folder.maxItems = value
        }
''' + size_slider('folder')),
    section('apps', 'Desktop icons', enable_row('desktopIcons') + '''        ConfigSpinBox {
            icon: "photo_size_select_large"
            text: Translation.tr("Icon size")
            value: Config.options.background.widgets.desktopIcons.iconSize
            from: 24
            to: 128
            stepSize: 8
            onValueChanged: Config.options.background.widgets.desktopIcons.iconSize = value
        }
'''),
    section('calendar_month', 'Widget: Calendar', enable_row('calendar') + size_slider('calendar')),
    section('checklist', 'Widget: To Do', enable_row('todo') + size_slider('todo')),
    section('timer', 'Widget: Timer', enable_row('timer') + size_slider('timer')),
    section('monitoring', 'Widget: Resources', enable_row('resources')
            + switch('resources', 'showSwap', 'swap_horiz', 'Show swap') + size_slider('resources')),
    section('sticky_note_2', 'Widget: Note', enable_row('notes') + '''        ConfigSpinBox {
            icon: "format_size"
            text: Translation.tr("Font size")
            value: Config.options.background.widgets.notes.fontSize
            from: 10
            to: 40
            stepSize: 1
            onValueChanged: Config.options.background.widgets.notes.fontSize = value
        }
''' + size_slider('notes')),
    section('translate', 'Widget: Japanese clock', enable_row('japaneseClock')
            + switch('japaneseClock', 'vertical', 'text_rotate_vertical', 'Vertical (tategaki)')
            + switch('japaneseClock', 'showDate', 'calendar_today', 'Show date')
            + switch('japaneseClock', 'showSeconds', 'timer', 'Show seconds')
            + switch('japaneseClock', 'card', 'crop_square', 'Card background')
            + size_slider('japaneseClock')),
])
edit(path('modules', 'settings', 'BackgroundConfig.qml'), [
    ('''    ContentSection {
        icon: "weather_mix"''',
     sections + '''    ContentSection {
        icon: "weather_mix"'''),
])

# --- Spanish.
STRINGS_ES = {
    "Calendar": "Calendario",
    "To Do": "Tareas",
    "Timer": "Temporizador",
    "Resources": "Recursos",
    "Note": "Nota",
    "Japanese clock": "Reloj japonés",
    "Edit desktop": "Editar escritorio",
    "Editing the desktop: drag widgets, use − and + to resize them": "Editando el escritorio: arrastra los widgets y usa − y + para cambiar su tamaño",
    "Done": "Listo",
    "Smaller": "Más pequeño",
    "Bigger": "Más grande",
    "Hide": "Ocultar",
    "Write something…": "Escribe algo…",
    "CPU": "CPU",
    "RAM": "RAM",
    "Swap": "Swap",
    "Desktop widgets": "Widgets del escritorio",
    "Right click the desktop > Edit desktop to move widgets on a grid and resize them with − and +. The sizes here are the same.":
        "Clic derecho en el escritorio > Editar escritorio para mover los widgets sobre una cuadrícula y cambiar su tamaño con − y +. Los tamaños de aquí son los mismos.",
    "Size": "Tamaño",
    "Clock": "Reloj",
    "Weather": "Clima",
    "Widget: Music": "Widget: Música",
    "Spectrum behind the cover": "Espectro detrás de la carátula",
    "Widget: Photo": "Widget: Foto",
    "Image path or https link": "Ruta de la imagen o enlace https",
    "Widget: Recent files": "Widget: Archivos recientes",
    "Folder (empty: Downloads)": "Carpeta (vacío: Descargas)",
    "Files shown": "Archivos mostrados",
    "Desktop icons": "Iconos del escritorio",
    "Icon size": "Tamaño de los iconos",
    "Widget: Calendar": "Widget: Calendario",
    "Widget: To Do": "Widget: Tareas",
    "Widget: Timer": "Widget: Temporizador",
    "Widget: Resources": "Widget: Recursos",
    "Show swap": "Mostrar swap",
    "Widget: Note": "Widget: Nota",
    "Font size": "Tamaño de letra",
    "Widget: Japanese clock": "Widget: Reloj japonés",
    "Vertical (tategaki)": "Vertical (tategaki)",
    "Show date": "Mostrar fecha",
    "Show seconds": "Mostrar segundos",
    "Card background": "Fondo de tarjeta",
}
file = path('translations', 'es_MX.json')
with open(file, encoding='utf-8') as f:
    data = json.load(f)
for key, value in STRINGS_ES.items():
    data.setdefault(key, value)
with open(file, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('patched widgets')
