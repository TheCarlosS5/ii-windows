"""The app store (store.qml, modules/ii/store, services/Winget.qml, all overlay files): where it is opened from
(Overview, the desktop menu, the search "action" list) and its Spanish texts."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.normpath(os.path.join(ROOT, *parts))


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


# Search: the action `>store` opens the store.
edit(path('services', 'LauncherSearch.qml'), [
    ('''        {
            action: "superpaste",''',
     '''        {
            action: "store",
            execute: () => {
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("store.qml")]); // ii-windows: the app store
            }
        },
        {
            action: "superpaste",'''),
])

ES = {
    # window and navigation
    "App store": "Tienda de apps", "Featured": "Destacadas", "Development": "Desarrollo", "Browsers": "Navegadores",
    "Media and design": "Multimedia y diseño", "Games and chat": "Juegos y chat", "Tools": "Herramientas",
    "Installed": "Instaladas", "Updates": "Actualizaciones",
    "Search apps (winget)": "Buscar apps (winget)", "Search results": "Resultados de la búsqueda",
    "Searching...": "Buscando...", "Nothing found": "No se encontró nada",
    "Install": "Instalar", "Installing": "Instalando", "Installed ✓": "Instalada ✓", "Update": "Actualizar",
    "Updating": "Actualizando", "Uninstall": "Desinstalar", "Uninstalling": "Desinstalando", "Queued": "En cola",
    "Done": "Listo", "Failed": "Falló", "Try again": "Reintentar", "Open": "Abrir",
    "Update all": "Actualizar todo", "Everything is up to date": "Todo está al día", "Checking...": "Comprobando...",
    "%1 updates": "%1 actualizaciones", "Not installed from winget": "No instalada con winget",
    "winget is not available on this PC": "winget no está disponible en este PC",
    "winget comes with Windows 11 as \"App Installer\". Install or update it from the Microsoft Store and open this window again.": "winget viene con Windows 11 como \"Instalador de aplicación\". Instálalo o actualízalo desde la Microsoft Store y vuelve a abrir esta ventana.",
    "Apps come from the winget catalogue (the same as `winget install`). Some ask for administrator permission.": "Las apps vienen del catálogo de winget (el mismo de `winget install`). Algunas piden permiso de administrador.",
    "Installed apps on this PC": "Apps instaladas en este PC", "Filter installed apps": "Filtrar apps instaladas",
    "Open the app store": "Abrir la tienda de apps",
    # featured descriptions
    "The editor most developers use, with thousands of extensions.": "El editor que usa la mayoría de desarrolladores, con miles de extensiones.",
    "Version control, with Git Bash.": "Control de versiones, con Git Bash.",
    "GitHub from the terminal: pull requests, issues, releases.": "GitHub desde la terminal: pull requests, issues, releases.",
    "Git without the command line.": "Git sin línea de comandos.",
    "JavaScript outside the browser, with npm.": "JavaScript fuera del navegador, con npm.",
    "The Python language and pip.": "El lenguaje Python y pip.",
    "The Rust toolchain installer.": "El instalador de herramientas de Rust.",
    "The Go language.": "El lenguaje Go.",
    "Build C#, F# and ASP.NET apps.": "Crea apps en C#, F# y ASP.NET.",
    "Containers on your PC.": "Contenedores en tu PC.",
    "IntelliJ, PyCharm, WebStorm, Rider and the rest.": "IntelliJ, PyCharm, WebStorm, Rider y los demás.",
    "Android app development.": "Desarrollo de apps para Android.",
    "Try and document APIs.": "Prueba y documenta APIs.",
    "One client for every database.": "Un cliente para todas las bases de datos.",
    "Tabs and panes for PowerShell, CMD and WSL.": "Pestañas y paneles para PowerShell, CMD y WSL.",
    "Microsoft's utilities: FancyZones, Run, colour picker...": "Utilidades de Microsoft: FancyZones, Run, selector de color...",
    "The modern Vim.": "El Vim moderno.",
    "Light text editor.": "Editor de texto ligero.",
    "SFTP and SCP file transfer.": "Transferencia de archivos por SFTP y SCP.",
    "A code editor built around AI.": "Un editor de código hecho alrededor de la IA.",
    "Fast, private and open.": "Rápido, privado y abierto.",
    "Google's browser.": "El navegador de Google.",
    "Blocks ads and trackers by default.": "Bloquea anuncios y rastreadores por defecto.",
    "A browser you can customise to the last detail.": "Un navegador que puedes personalizar hasta el último detalle.",
    "Plays almost any video or audio file.": "Reproduce casi cualquier video o audio.",
    "Record and stream the screen.": "Graba y transmite la pantalla.",
    "Music and podcasts.": "Música y podcasts.",
    "Record and edit audio.": "Graba y edita audio.",
    "Convert videos between formats.": "Convierte videos entre formatos.",
    "3D, animation and video editing.": "3D, animación y edición de video.",
    "Edit images, free.": "Edita imágenes, gratis.",
    "Vector graphics.": "Gráficos vectoriales.",
    "Digital painting.": "Pintura digital.",
    "Interface design.": "Diseño de interfaces.",
    "Screenshots and screen recordings with sharing.": "Capturas y grabaciones de pantalla con opciones para compartir.",
    "The biggest PC game store.": "La tienda de juegos de PC más grande.",
    "Epic's store and free games.": "La tienda de Epic y juegos gratis.",
    "All your game libraries in one place.": "Todas tus bibliotecas de juegos en un solo lugar.",
    "Voice, video and text with friends.": "Voz, video y texto con amigos.",
    "Fast messaging.": "Mensajería rápida.",
    "Video calls.": "Videollamadas.",
    "Open and create .7z, .zip, .rar and more.": "Abre y crea .7z, .zip, .rar y más.",
    "Instant file search.": "Búsqueda instantánea de archivos.",
    "Notes in Markdown, linked.": "Notas en Markdown, enlazadas.",
    "Password manager.": "Gestor de contraseñas.",
    "Torrent client without ads.": "Cliente torrent sin anuncios.",
    "Send files to nearby devices.": "Envía archivos a dispositivos cercanos.",
    "Temperatures and voltages.": "Temperaturas y voltajes.",
    "Make bootable USB drives.": "Crea memorias USB de arranque.",
    "Flash images to USB and SD cards.": "Graba imágenes en USB y tarjetas SD.",
    "Light PDF reader.": "Lector de PDF ligero.",
    "Automate keys and clicks with scripts.": "Automatiza teclas y clics con scripts.",
    "See what is using your disk.": "Mira qué ocupa tu disco.",
    "A Task Manager with the details.": "Un Administrador de tareas con todos los detalles.",
}
add_translations('es_MX', ES)
