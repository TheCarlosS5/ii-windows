"""Round of 2026-10-18: first start, tour, dock, lyrics on the desktop.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
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
        data[key] = value
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


# --- A new install keeps the wallpaper the user had in Windows ---------------------------------------------------------
# The first start used to switch to ii's own picture (the brown one) and push it to Windows too, replacing the user's.
# switchwall --first-run takes Windows' wallpaper for ii; ii's picture only when Windows has none (a plain colour), and
# Windows is not touched either way. ii's picture is still copied to Pictures\Wallpapers for the selector.
edit(path('services', 'FirstRunExperience.qml'), [
    ('''        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath])''',
     '''        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--first-run", root.defaultWallpaperPath]) // ii-windows'''),
])

# --- The tour opens what it talks about: the dock comes out even when it hides itself --------------------------------
edit(path('GlobalStates.qml'), [
    ('''    property real dockInsetBottom: 0 // ii-windows: space the dock takes, for the desktop icons''',
     '''    property real dockInsetBottom: 0 // ii-windows: space the dock takes, for the desktop icons
    property bool dockForceReveal: false // ii-windows: the tour's dock step shows a dock that hides itself
    property bool tourOpen: false // ii-windows: panels the tour opens leave it the keyboard'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'SidebarRight.qml'), [
    ('        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None',
     '        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen && !GlobalStates.tourOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None // ii-windows: the tour keeps the keyboard'),
])
edit(path('modules', 'ii', 'sidebarLeft', 'SidebarLeft.qml'), [
    ('            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand',
     '            WlrLayershell.keyboardFocus: GlobalStates.tourOpen ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand // ii-windows: the tour keeps the keyboard'),
])

# --- A dock on the left or right: desktop widgets near that edge move out from under it ---------------------------------
edit(path('modules', 'ii', 'background', 'widgets', 'AbstractBackgroundWidget.qml'), [
    ('    property real targetX: Math.max(0, Math.min(configEntry.x < 0 ? scaledScreenWidth - width * transformScale + configEntry.x : configEntry.x, scaledScreenWidth - width * transformScale))',
     '    property real targetX: Math.max(GlobalStates.dockInsetLeft, Math.min(configEntry.x < 0 ? scaledScreenWidth - width * transformScale + configEntry.x : configEntry.x, scaledScreenWidth - GlobalStates.dockInsetRight - width * transformScale)) // ii-windows: not under a side dock'),
])

# --- Lyrics on the desktop music widget (off by default: the card stays as it was) --------------------------------------
edit(path('modules', 'common', 'Config.qml'), [
    ('''                        property bool idleMotion: false // the music-note placeholder is still unless this is on
''', '''                        property bool idleMotion: false // the music-note placeholder is still unless this is on
                        property bool lyrics: false // ii-windows: synced lyrics under the card (LRCLIB), as the song plays
'''),
])
edit(path('modules', 'settings', 'BackgroundConfig.qml'), [
    ('''            checked: Config.options.background.widgets.media.spectrum
            onCheckedChanged: Config.options.background.widgets.media.spectrum = checked
        }
''', '''            checked: Config.options.background.widgets.media.spectrum
            onCheckedChanged: Config.options.background.widgets.media.spectrum = checked
        }
        ConfigSwitch {
            buttonIcon: "lyrics"
            text: Translation.tr("Show the song's lyrics under the card (looks the song up on lrclib.net)")
            checked: Config.options.background.widgets.media.lyrics
            onCheckedChanged: Config.options.background.widgets.media.lyrics = checked
        }
'''),
])
add_translations('es_MX', {
    "Show the song's lyrics under the card (looks the song up on lrclib.net)": "Mostrar la letra de la canción debajo de la tarjeta (la busca en lrclib.net)",
    "Show the lyrics": "Mostrar la letra",
    "Hide the lyrics": "Ocultar la letra",
    "Looking for the lyrics…": "Buscando la letra…",
    "This song has no synced lyrics": "Esta canción no tiene letra sincronizada",
})

# --- The app store, redone (store.qml, modules/ii/store, services/Winget.qml are overlay files) ------------------------
add_translations('es_MX', {
    "Recommended": "Recomendada",
    "See all": "Ver todo",
    "%1 apps": "%1 apps",
    "Searching…": "Buscando…",
    "Try another name, or a shorter one.": "Prueba con otro nombre, o uno más corto.",
    "Asking winget what is installed…": "Preguntando a winget qué está instalado…",
    "Refresh": "Actualizar lista",
    "Checking…": "Revisando…",
    "Updates install one after another; some ask for administrator permission.": "Las actualizaciones se instalan una tras otra; algunas piden permiso de administrador.",
    "Search any app (winget catalogue)": "Busca cualquier app (catálogo de winget)",
    "Installing %1": "Instalando %1",
    "Updating %1": "Actualizando %1",
    "Uninstalling %1": "Desinstalando %1",
    "%1 waiting": "%1 en espera",
    "winget could not finish (%1). Some apps need you to accept a permission prompt.": "winget no pudo terminar (%1). Algunas apps necesitan que aceptes un permiso de administrador.",
    "Dismiss": "Cerrar",
    "Code with superpowers: extensions for every language.": "Programa con superpoderes: extensiones para cada lenguaje.",
    "Your music and podcasts, and the lyrics on ii's desktop.": "Tu música y podcasts, con la letra en el escritorio de ii.",
    "Thousands of games, sales every week.": "Miles de juegos y ofertas cada semana.",
    "Record and stream your screen like a pro.": "Graba y transmite tu pantalla como un profesional.",
    "A second brain in plain Markdown files.": "Un segundo cerebro en archivos Markdown.",
    "Where your friends and communities hang out.": "Donde están tus amigos y comunidades.",
})

print('patch_ii_ronda18: ok')
