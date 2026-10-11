# Inventario de rutas Linux vivas en el QML de ii (B00 / C12)

Generado con `python tools/dev/scan-linux-routes.py <ii preparado> --markdown` sobre el árbol que produce
`tools/dev/stage-ii.ps1` (upstream sin tocar + overlay + parches), a fecha de 10 de octubre de 2026. Es un
inventario estático de **puntos de llamada** (`command: ["x", ...]`, `Quickshell.execDetached(["x", ...])`): no
prueba que lo que hay detrás funcione. `tools/sandbox/tests/test-linux-routes.ps1` falla si aparece un comando
nuevo sin proveedor, así que esta tabla no puede quedarse atrás sin que nadie lo note.

Clases: **shim** = `ii-shim` responde a ese nombre (`tools/dev/deploy.ps1` lo copia con esos nombres);
**windows** = programa de Windows; **optional** = herramienta de terceros que solo importa si está instalada;
**unbacked** = nada responde en un Windows de serie: lo que depende de él no hace nada.

Consumidores sin proveedor que quedan, y por qué siguen ahí:

- `file` y `identify`: adjuntos del chat de IA y el icono de carpetas (C08 / P08). Pendientes.
- `hyprctl`: el interruptor «modo juego» de ajustes rápidos (U05) cambia animaciones de Hyprland; en Windows no significa nada y debe pasar a activar el perfil de ii.

Retirados en C12: `find` (lista de idiomas, ahora `FolderListModel`), `hyprctl` del pin del panel izquierdo,
y `bash -c "rm -rf …; mkdir -p …"` de las carpetas de caché (ahora `ii-shim reset-dir`, porque el `bash` del shim
no es un intérprete). `mkdir`, `rm` y `which` los responde ahora `ii-shim` (`host/src/fsutil.cpp`), solo
sobre carpetas del propio usuario.

Nota: `bash` (60 llamadas) lo responde el shim **solo** para abrir un URI o un programa suelto y unas pocas
órdenes de ii; cualquier tubería u otro uso recibe 127 a propósito. Cada una de esas 60 llamadas es una función que
puede estar inerte en Windows y está pendiente de revisar tarea a tarea.
| Comando | Clase | Llamadas | Ejemplo |
| --- | --- | ---: | --- |
| `file` | unbacked | 3 | `modules/common/widgets/DirectoryIcon.qml:33` |
| `hyprctl` | unbacked | 1 | `modules/ii/sidebarRight/quickToggles/classicStyle/GameMode.qml:17` |
| `identify` | unbacked | 2 | `modules/ii/sidebarLeft/aiChat/AttachedFileIndicator.qml:39` |
| `warp-cli` | optional | 8 | `modules/common/models/quickToggles/CloudflareWarpToggle.qml:19` |
| `cmd` | windows | 1 | `services/FirstRunExperience.qml:22` |
| `explorer.exe` | windows | 1 | `modules/common/functions/Session.qml:21` |
| `shutdown.exe` | windows | 5 | `modules/common/functions/Session.qml:38` |
| `taskmgr.exe` | windows | 1 | `modules/common/functions/Session.qml:42` |
| `whoami` | windows | 1 | `services/SystemInfo.qml:22` |
| `bash` | shim | 56 | `modules/common/models/quickToggles/CloudflareWarpToggle.qml:60` |
| `cava` | shim | 2 | `modules/ii/background/widgets/media/MediaWidget.qml:42` |
| `hyprpicker` | shim | 2 | `modules/common/models/quickToggles/ColorPickerToggle.qml:24` |
| `ii-shim` | shim | 22 | `modules/common/Directories.qml:59` |
| `killall` | shim | 4 | `killDialog.qml:104` |
| `ls` | shim | 3 | `services/Ai.qml:394` |
| `magick` | shim | 1 | `modules/ii/background/Background.qml:111` |
| `mkdir` | shim | 4 | `modules/common/Directories.qml:56` |
| `notify-send` | shim | 19 | `modules/common/models/quickToggles/CloudflareWarpToggle.qml:31` |
| `pidof` | shim | 2 | `killDialog.qml:64` |
| `qs` | shim | 16 | `modules/ii/background/widgets/desktop/DesktopMenu.qml:114` |
| `rm` | shim | 2 | `modules/common/Directories.qml:65` |
| `secret-tool` | shim | 1 | `services/KeyringStorage.qml:79` |
| `test` | shim | 1 | `services/Wallpapers.qml:55` |
| `trans` | shim | 1 | `modules/ii/sidebarLeft/Translator.qml:84` |
| `which` | shim | 1 | `services/Updates.qml:42` |
| `wpctl` | shim | 1 | `modules/ii/bar/UtilButtons.qml:92` |
| `xdg-open` | shim | 20 | `modules/common/models/quickToggles/BluetoothToggle.qml:22` |
| `ydotool` | shim | 4 | `services/Ydotool.qml:15` |

