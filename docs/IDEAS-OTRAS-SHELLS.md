# Ideas de otras shells para ii-windows

Investigación del 2026-10-17. Se clonaron (shallow, solo lectura, nada ejecutado ni compilado) en `C:\Users\Calos\dev\shell-refs\`:

| Repo | Carpeta local | Tecnología | Licencia | ¿Se puede copiar código? |
| --- | --- | --- | --- | --- |
| caelestia-dots/shell | `shell/` | QML + plugin C++ (Qt) | **GPL-3.0** | Solo ideas. Copiar código obligaría a que el resultado sea GPL-3.0; revisar la licencia de ii-windows/dots-hyprland antes. Reescribir desde cero. |
| noctalia-dev/noctalia-shell | `noctalia-shell/` | **C++ nativo Wayland/OpenGL ES, sin Qt ni QML** (ya no es Quickshell) | MIT | Nada de QML reutilizable; solo ideas de diseño. Si se porta lógica, conservar el aviso MIT. |
| AvengeMedia/DankMaterialShell (DMS) | `DankMaterialShell/` | QML (Quickshell) + backend Go (`core/`) | MIT (relicenciado desde GPL-3.0, ver `quickshell/LICENSE_CHANGE_12_11_2025.md`; consentimiento de los 21 autores) | Sí, conservando el aviso de copyright MIT en lo copiado. Es la fuente más aprovechable. |
| Jas-SinghFSU/HyprPanel | `HyprPanel/` | TypeScript + AGS/GTK (no QML) | MIT | Solo ideas / lógica; la UI es GTK. |

Nada de esto se ha mezclado con el repo de ii-windows. Rutas de abajo: relativas a la carpeta local de cada repo.

## 1. Qué tiene ya ii-windows (para comparar)

Barra con bandeja, red, audio, multimedia, reloj y recursos; lanzador/vista general (apps, calculadora, emojis, ventanas, tira de escritorios); dock con previsualización; paneles laterales (ajustes rápidos, notificaciones, calendario, tareas, pomodoro, mezclador, Wi-Fi, luz nocturna, planes de energía); escritorio con widgets editables; colores Material 3 desde el fondo; selector de fondos y fondo aleatorio; recortes con OCR; overlay (Super+G); cheatsheet; traductor; menú de sesión; tienda/instalador de apps (`overlay/ii/modules/ii/store`, `Winget.qml`); `AppUsage.qml`, `Cliphist.qml`, `Network.qml`, OSD de teclas de bloqueo; fastfetch; export/import de configuración (`docs/CONFIGURACION.md`); tour de bienvenida (`overlay/ii/modules/ii/tour`). No gestiona ventanas ni tiene pantalla de bloqueo propia (el bloqueo es del sistema).

## 2. Funciones de cada shell

### Caelestia (`shell/`, GPL-3.0)
- Una sola ventana a pantalla completa con regiones de máscara: `modules/drawers/{ContentWindow,Panels,Regions,Interactions,Exclusions}.qml`. Los paneles brotan del borde (launcher, dashboard, sesión, sidebar, OSD, popouts de la barra).
- Dashboard (`modules/dashboard/`): Dash (fecha, calendario, clima, usuario, recursos), Media, Performance (CPU/GPU/RAM/disco con sparkline), Weather.
- Lanzador (`modules/launcher/`, `services/{Apps,Actions,Schemes,M3Variants}.qml`): apps, calculadora (qalculator en C++), acciones, cambio de esquema/variante de color M3 y de fondo desde el propio lanzador.
- Utilities (`modules/utilities/`): grabador de pantalla (`services/Recorder.qml`, lista y borrado de grabaciones), toggles, inhibidor de reposo (`cards/IdleInhibit.qml`), toasts.
- `services/GameMode.qml`, `services/IdleInhibitor.qml`, `services/VPN.qml`, `modules/IdleMonitors.qml`, `BatteryMonitor.qml`.
- Nexus (`modules/nexus/`): app de ajustes propia con páginas (red, audio, bluetooth, apps, paneles, fondo y estilo, idioma).
- `modules/windowinfo/` (info y vista previa de la ventana), `modules/areapicker/`, lock screen con notificaciones, clima y media (`modules/lock/`).
- Barra: workspaces, ventana activa, tray, iconos de estado con popouts anclados (`modules/bar/popouts/`).
- Efectos: "Blobs" con shader (`plugin/src/Caelestia/Blobs`), visualizador cava en el fondo (`modules/background/Visualiser.qml`), reloj de escritorio.

### Noctalia (`noctalia-shell/`, MIT, C++)
- `README.md` y `src/shell/`: barra multi-monitor, dock, launcher, centro de control, notificaciones (toasts + historial), selector de fondos, OSD, lockscreen, panel de sesión, historial del portapapeles (`clipboard`), widgets de escritorio con editor (`desktop`), **hot corners** (`hot_corners`), screen corners, **switcher** tipo Alt-Tab (`switcher`), asistente de primera vez (`setup_wizard`), polkit, perfiles (`profile`).
- Lanzador con proveedores (`src/launcher/`): apps, mates, emojis, ventanas, sesión, fondos, **dmenu** por stdin/IPC, paneles y plugins; `usage_tracker` (ordena por uso).
- Configuración TOML con recarga en caliente y overrides desde GUI; plantillas de tema (`docs/user/templates`, `theming`); IPC (`docs/user/ipc`); API de plugins (`docs/plugin-api.json`); automatización (`docs/user/automation`).

### DankMaterialShell (`DankMaterialShell/`, MIT)
- Barra modular (`quickshell/Modules/DBar/`, `Modules/DankBar/Widgets/`), ~35 widgets: `CpuMonitor`, `RamMonitor`, `DiskUsage`, `CpuTemperature`, `GpuTemperature`, `NetworkMonitor`, `Battery`, `Weather`, `Vpn`, `PrivacyIndicator`, `CapsLockIndicator`, `IdleInhibitor`, `KeyboardLayoutName`, `ColorPicker`, `ClipboardButton`, `NotepadButton`, `SystemUpdate`, `AudioVisualization`, `Media` con **letra de canciones** (`MediaLyricLine.qml`, `Services/Lyrics*.qml`), `RunningApps`, `FocusedApp`. Overflow automático (`DBar/OverflowLayout.js`, `SectionOverflow.qml`).
- Dash (`Modules/DDash/`): Overview, Media, Weather, carrusel de fondos y **Wellbeing** (`Wellbeing/`, `Services/WellbeingService.qml`: tiempo de uso por app, límites diarios, gráfico semanal).
- "Dynamic Island" (`Modules/DIsland/`): píldora con actividades (media, notificaciones, sistema).
- Centro de control con detalles y plugins (`Modules/ControlCenter/`): VPN, Tailscale, CUPS, perfiles de pantalla.
- Notificaciones (`Modules/Notifications/`): deslizar para descartar (`NotificationSwipe*.qml`), **presets de No Molestar** (`DndPresets.qml`), centro agrupado, menú contextual.
- Lanzador V2 (`Modals/DLauncherV2/`): fuentes con insignias, puntuación difusa (`Scorer.js`), vista previa de portapapeles, panel de acciones por elemento, editor de apps.
- Modales útiles: lista de procesos (`Modals/ProcessListModal.qml`, `Modules/ProcessList/`), QR (`QRGeneratorModal`, `WifiQRCodeModal`), selector de color (`ColorPickerModal`), bloc de notas con pestañas (`Modules/Notepad/`), selector de navegador/app, portapapeles (`Modals/Clipboard/`), explorador de archivos, changelog.
- Fondos: ciclado automático (`Services/WallpaperCyclingService.qml`), desenfocado en vivo (`BlurredWallpaper*.qml`), tema automático por hora (`ThemeAutoService.qml`), acento desde la carátula (`MediaAccentService.qml`, `TrackArtService.qml`).
- Widgets de escritorio con editor (`DesktopWidgetEditor.qml`), OSD por tipo (`Modules/OSD/`: volumen, micro, brillo, caps lock, perfil de energía, touchpad, reproducción), `RefreshRateService.qml`, marco de pantalla (`Modules/Frame/`).
- Backend en Go (`core/`) separado del QML; sistema de plugins documentado (`quickshell/PLUGINS/`, `Services/PluginService.qml`).

### HyprPanel (`HyprPanel/`, MIT, TS/GTK)
- Módulos de barra (`src/components/bar/modules/`): batería, bluetooth, cava, reloj, CPU, cputemp, hypridle, hyprsunset, kblayout, media, netstat, RAM, storage, updates, volumen/micro, clima, **worldclock**, título de ventana, workspaces.
- Menús (`src/components/menus/`): audio, bluetooth, calendario, dashboard (perfil, atajos a carpetas `directories/`, botones de control, estadísticas), energía, red, media, notificaciones.
- Filtros de notificaciones y posición configurable; ajustes con editor visual (`src/components/settings`); temas importables (`themes/`) y matugen (`src/services/matugen`).

## 3. Funciones que faltan en ii-windows, ordenadas por valor para un usuario de Windows

Esfuerzo: S = horas, M = 1 a 3 días, L = una semana o más. "Backend Windows" = hay que escribir algo nuevo en `ii-host`/`shim` (no existen Hyprland, PipeWire ni NetworkManager que reutilizar).

| # | Función | Qué es | Dónde verla | Esfuerzo | ¿Backend Windows? |
| --- | --- | --- | --- | --- | --- |
| 1 | **Monitor de procesos y rendimiento** | Procesos con CPU/RAM/disco, terminar proceso, tarjetas con sparkline (CPU, GPU, RAM, discos) | DMS `Modals/ProcessListModal.qml`, `Modules/ProcessList/*`, `Services/DgopService.qml`; Caelestia `modules/dashboard/Performance.qml`, `plugin/src/Caelestia/Components/sparklineitem.cpp` | M | Sí: contadores PDH/WMI y `TerminateProcess` en el host; el QML no depende de Linux |
| 2 | **Widgets de barra de hardware**: temperatura CPU/GPU, velocidad de red, uso de disco | Píldoras con valor y tooltip | DMS `Modules/DankBar/Widgets/{CpuTemperature,GpuTemperature,NetworkMonitor,DiskUsage}.qml`; HyprPanel `bar/modules/{cputemp,netstat,storage}` | S-M | Sí: temperatura necesita WMI/LibreHardwareMonitor (ver `docs/HARDWARE-SERVICES.md`); red y disco por PDH |
| 3 | **Tiempo de pantalla / bienestar digital** | Uso por app, límites diarios, gráfico semanal (ya existe `AppUsage.qml`, faltan vista y límites) | DMS `Modules/DDash/Wellbeing/*`, `Services/WellbeingService.qml` | M | Parcial: falta persistencia y avisar/cerrar al llegar al límite |
| 4 | **No Molestar con presets** | "1 h", "hasta mañana", interruptor en la barra, silenciar por app | DMS `Modules/Notifications/DndPresets.qml`, `Services/NotificationService.qml` | S-M | Parcial: el Asistente de concentración de Windows no tiene API pública estable; la shell puede filtrar sus propios popups |
| 5 | **Notificaciones: deslizar para descartar, agrupar por app** | Gestos y grupos | DMS `Modules/Notifications/{NotificationSwipeGroup,NotificationSwipeRow,Center/}`; Caelestia `modules/sidebar/Notif*.qml` | M | No |
| 6 | **Inhibidor de reposo ("Cafeína") y Modo juego** | Evitar suspensión/apagado de pantalla; modo que apaga animaciones y blur de ii | Caelestia `services/{IdleInhibitor,GameMode}.qml`, `modules/utilities/cards/IdleInhibit.qml`; DMS `Widgets/IdleInhibitor.qml`, `Modules/OSD/IdleInhibitorOSD.qml` | S | Sí, pequeño: `SetThreadExecutionState` en `ii-host` |
| 7 | **Letra de canciones sincronizada** | Línea actual en barra y widget de música | DMS `Modules/DankBar/Widgets/MediaLyricLine.qml`, `Services/{LyricsService,LyricsController,LyricsSubscription}.qml` | M | No: API web (p. ej. LRCLIB) y la posición de reproducción que ya da el widget de música |
| 8 | **Acento desde la carátula del álbum** | Color del widget/tema según la canción | DMS `Services/{MediaAccentService,TrackArtService}.qml` | S-M | No |
| 9 | **Lanzador ampliado** | Modo acciones, orden por uso, puntuación difusa, vista previa, conversor de unidades, dmenu | Caelestia `modules/launcher/services/Actions.qml`, `plugin/.../qalculator.cpp`; DMS `Modals/DLauncherV2/{Scorer.js,ActionPanel.qml,ClipboardLauncherPreview.qml}`; Noctalia `src/launcher/{usage_tracker,math_provider,session_provider,window_provider}.cpp` | M | No (QML/JS; reutilizar `AppUsage.qml`) |
| 10 | **Cuentagotas de color y generador de QR** | Copiar color de pantalla; QR de texto o Wi-Fi | DMS `Modules/ColorPicker/ColorPickerContent.qml`, `Modals/{ColorPickerModal,QRGeneratorModal,WifiQRCodeModal}.qml` | S-M | Parcial: la captura que usa el OCR sirve para el cuentagotas; el QR es solo QML/JS (hay referencias a QR en overlay: comprobar alcance antes) |
| 11 | **Relojes mundiales** | Hora de varias zonas en barra o widget | HyprPanel `bar/modules/worldclock` | S | No |
| 12 | **Bloc de notas con pestañas en popout** | Notas rápidas persistentes | DMS `Modules/Notepad/*`, `Services/NotepadStorageService.qml` | S-M | No (existe widget "nota" de escritorio) |
| 13 | **Grabador de pantalla con lista de grabaciones** | Botón, estado en barra, lista y borrado | Caelestia `services/Recorder.qml`, `modules/utilities/cards/Record*.qml` | M | Sí: en Linux usa wf-recorder; en Windows ffmpeg gdigrab/ddagrab o Windows.Graphics.Capture (ejecutar en el PC, nunca en el servidor Debian) |
| 14 | **Hot corners** | Esquina activa (vista general, panel) | Noctalia `src/shell/hot_corners/hot_corners.cpp`; ii upstream ya trae `modules/ii/screenCorners` | S-M | Ligero: ventana de 1 px por esquina; ojo con gestos de Windows |
| 15 | **"Dynamic Island"** | Píldora central con media/notificación/actividad | DMS `Modules/DIsland/*`, `Modules/SurfaceWidgets/*` | L | No |
| 16 | **Overflow automático de la barra** | Oculta/agrupa widgets que no caben | DMS `Modules/DBar/{OverflowLayout.js,SectionOverflow.qml,CenterLayout.js}` | M | No |
| 17 | **Ciclado de fondos y tema por horario** | Cambia de fondo cada X min; claro/oscuro por hora o amanecer | DMS `Services/{WallpaperCyclingService,ThemeAutoService,LocationService}.qml` | S-M | Parcial: falta temporizador y cálculo de salida/puesta de sol (solo cálculo local) |
| 18 | **Alt-Tab propio** | Cambiador con vista previa | Noctalia `src/shell/switcher/` | L | Sí, y delicado (interceptar Alt+Tab choca con el sistema); baja prioridad, Win+Tab ya está cubierto |
| 19 | **Ajustes con búsqueda y asistente inicial** | Buscar dentro de ajustes; configurar al primer arranque | Noctalia `src/shell/setup_wizard`; DMS `Services/SettingsSearchService.qml`, `FirstLaunchService.qml`; Caelestia `modules/nexus/*` | M | No (ya existe `tour/`) |
| 20 | **VPN / Tailscale / impresoras en ajustes rápidos** | Interruptores y estado | DMS `Modules/ControlCenter/BuiltinPlugins/{VpnWidget,TailscaleWidget,CupsWidget}.qml`; Caelestia `services/VPN.qml` | M | Sí: `rasdial`/`Get-VpnConnection`, CLI de Tailscale, spooler de Windows |

Descartado por no encajar en Windows: lockscreen propio (`Modules/Lock`, `modules/lock`), greeter (`Greetd`), polkit, `wlr-output`, reglas de ventana de Hyprland/Niri. Los "Blobs" de Caelestia (shader propio, GPL, plugin C++) no se recomiendan.

Ideas menores: cambio de frecuencia de refresco (`RefreshRateService.qml`, en Windows con `ChangeDisplaySettingsEx`), temas importables/plantillas (HyprPanel `themes/`, Noctalia `templates`), API de plugins para widgets de usuario (DMS `PLUGINS/`, Noctalia `docs/plugin-api.json`), calendario con varios backends (`CalendarService.qml`).

## 4. Técnicas de rendimiento de arranque y ejecución

Vistas en el código; no se han medido aquí. Probar cada una con el perfil de arranque de ii-windows antes de adoptarla.

1. **LazyLoader / Loader con `active: false` para todo lo que no se ve al arrancar.** DMS crea decenas de `LazyLoader` en `quickshell/DMSShell.qml` (desde ~línea 313: menús de dock, modales, ajustes, power menu) y los activa al usarse. Caelestia: `modules/areapicker/AreaPicker.qml`, `components/filedialog/FileDialog.qml`. Además DMS tiene LazyLoader en casi todas las pestañas de ajustes (`Modules/Settings/*Tab.qml`).
2. **Descarga diferida de paneles pesados.** DMS no destruye un popout al cerrarlo: lo apunta en `_pendingUnloads` y lo libera más tarde (`quickshell/Services/PopoutService.qml`: `_scheduleUnload`, `_flushPendingUnloads`), con `rewarmTimer` de 1500 ms que recalienta de uno en uno los que conviene tener listos. Evita tirones al abrir y cerrar rápido.
3. **Cargas asíncronas.** `asynchronous: true` en Loaders e imágenes (DMS: 52 usos). Caelestia `components/AnimLoader.qml` carga contenido asíncrono con transición; `components/images/{CachingImage,FadeImage,CachingIconImage}.qml`; `FadeImage.qml` usa `retainWhileLoading: true` para no parpadear al cambiar de fuente.
4. **`sourceSize` = tamaño en pantalla por DPR.** `shell/components/images/CachingImage.qml` evita decodificar un fondo 4K para una miniatura. Aplicar a fondos, carátulas, iconos de la tienda y miniaturas de ventanas en ii-windows.
5. **Lista corta de singletons de arranque.** Caelestia fuerza explícitamente solo algunos (`modules/ServiceLoader.qml`: IdleInhibitor, GameMode, Notifs, Players, Brightness, Weather; VPN solo si está habilitado) y deja el resto a la carga perezosa de QML.
6. **Datos pesados fuera de QML.** DMS tiene un backend Go (`core/`, `DMSService`) y marca la shell como lista (`shell.ready`) cuando backend y primer `Loader` están listos (`quickshell/shell.qml`, `shellReady`). Equivale al papel de `ii-host`; mover ahí los sondeos (procesos, sensores).
7. **`Qt.callLater` y temporizadores de calentamiento.** `DMSShell.qml` (~183, ~197, ~409) difiere inicializaciones al siguiente ciclo; `Services/DgopService.qml` usa un `primeTimer` antes de pedir datos pesados.
8. **Una sola ventana con máscara por regiones.** Caelestia dibuja barra, paneles y popouts en un único `ContentWindow` y calcula la región clicable (`modules/drawers/Regions.qml`, `Exclusions.qml`). Menos HWND. Habría que comprobar que el fork de Quickshell para Windows soporte `mask`; hoy ii-windows usa varias ventanas.
9. **Vigilancia de archivos solo cuando hace falta.** DMS enlaza `Quickshell.watchFiles` a una variable de entorno y al estado de bloqueo (`quickshell/shell.qml`, `Binding`). En ii-windows: desactivar `watchFiles` fuera de desarrollo (`redev.ps1`).
10. **Listas virtualizadas.** Caelestia `plugin/src/Caelestia/Components/lazylistview.cpp`; Noctalia `VirtualListView`/`VirtualGridView` (`ARCHITECTURE.md`). En QML: `ListView`/`GridView` con `reuseItems: true` y `cacheBuffer` pequeño en vez de `Repeater` para apps, emojis, portapapeles y tienda.
11. **Fases de frame disciplinadas (Noctalia, `ARCHITECTURE.md`).** `PrepareFrame/Update/Layout/Render` con `requestUpdate/Layout/Redraw`: nunca reconstruir la escena durante el render. En QML: agrupar cambios de modelo en un `Timer` de 0 ms y no usar bindings caros que cambien estructura.
12. **Entorno de render ajustado.** DMS fija `QSG_RENDER_LOOP=threaded` y `QT_MEDIA_BACKEND=ffmpeg` con `//@ pragma Env` en `quickshell/shell.qml`. En Windows el bucle ya suele ser el de D3D; verificar antes de copiar.
13. **Efectos apagables.** Caelestia `services/GameMode.qml` y DMS `Services/BlurService.qml` / `BlurredWallpaperLive.qml`; combinar con la detección de pantalla completa que ya hace ii-windows.

### Prioridad de perf sugerida
1. Auditar qué paneles (sidebars, overview, tienda, cheatsheet, traductor) siguen cargados al arrancar y pasarlos a `LazyLoader` o `Loader` con descarga diferida (1 y 2).
2. `sourceSize` por DPR y `asynchronous` en todas las imágenes (3 y 4).
3. Lista corta de singletons de arranque y sondeos en el host (5 y 6).
4. `watchFiles` solo en desarrollo (9).
5. Evaluar la ventana única con máscara solo si el fork de Quickshell lo permite (8).

## 5. Dependencias Linux a tener en cuenta al portar

- IPC de Hyprland/Niri/Sway: workspaces, ventana activa, hot corners, reglas de ventana. ii-windows ya lo sustituye con `HyprlandData.qml` y escritorios virtuales.
- PipeWire/Pulse: volumen, micro y visualizador cava; en Windows el mezclador va por el host (WASAPI); cava necesita captura loopback.
- NetworkManager/nmcli (Caelestia `services/Nmcli.qml`, DMS `DMSNetworkService.qml`): ya sustituido por `Network.qml`.
- BlueZ, UPower, logind, polkit, greetd, CUPS, wlr-output: cada uno necesita equivalente propio (WinRT, WMI, Win32).
- Programas externos Linux (`wf-recorder`, `grim`, `khal`, `matugen`, `ddcutil`, `dgop`): reemplazar o empaquetar equivalentes para Windows.
