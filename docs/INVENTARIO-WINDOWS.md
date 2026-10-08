# Inventario de Illogical Impulse en Windows 11

Revisión de código: **8 de octubre de 2026, corte a las 18:52 (Colombia, UTC−5)**. Proyecto: C:\Users\Calos\Desktop\ii-windows.

Se compara cada punto de C:\Users\Calos\Downloads\Inventario_dots-hyprland_Linux.md con el port local. Se mantienen las 25 secciones y el orden de sus puntos; se revisan también defaults y atajos. Un punto compuesto recibe una clasificación; su explicación distingue las partes.

**Auditoría de código, no una nueva prueba de funcionamiento.** No se arrancaron ii, ii-host ni probes; no se compiló, consultó la red, modificó el registro ni operó Git. Las pruebas citadas son archivos existentes y resultados anteriores consignados en PROGRESS/DECISIONS; no se ejecutaron ahora. Sólo se escribe este documento.

La referencia Linux declara el commit c4f0582cbf4ad29607dbf3c20337815de8690b34; README/FEASIBILITY documentan una base del port 33f31a08caddd41422a2d97670adeeb52b4f1e7c. No se verificaron esos identificadores con Git. Se evaluó el árbol local y **build/ii**, el resultado parcheado preparado para ejecutar. Un paquete ya instalado puede tener menos novedades. Durante la revisión aparecieron implementaciones de cliphist, ydotool, secret-tool y empaquetado de emojis, así como correcciones de bienvenida, suspensión crítica, Konachan y recarga; se incorporó su estado en la lectura final, sin compilarlas ni ejecutarlas.

Leyenda:

- **✅ Funciona:** implementación completa para la función indicada, o lógica/dibujo QML sin dependencia Linux. No acredita prueba visual de cada opción ni soporte de cualquier hardware.
- **🟡 Parcial:** una parte funciona y otra falta, se delega a Windows o tiene un límite importante.
- **🔧 Falta pero es factible:** sin ruta operativa completa; se propone implementación concreta y esfuerzo.
- **⛔ No aplica o queda fuera del port:** función del compositor/entorno Linux, API no pública para lo requerido o incompatible con el alcance de una interfaz sobre Windows.
- **❓ Sin verificar:** el código leído no basta para acreditar la función; no significa fallo probado.

**S/M/L**: S = cambio localizado; M = servicio/integración acotada; L = subsistema/integración amplia. No son plazos. Varias filas dependen de una misma mejora y no deben sumarse como proyectos independientes.

## Evidencia y lectura de las rutas

Rutas relativas al proyecto. Claves de evidencia empleadas en las tablas:

| Clave | Archivos |
| --- | --- |
| Q | build/ii/: QML efectivo. Cada sección identifica sus módulos/servicios. “Q puro” = QtQuick/JavaScript, modelos y/o FileView, sin ejecutar programas Linux para esa parte. |
| C | build/ii/modules/common/{Config,Persistent,Directories}.qml; quickshell/src/io/fileview.cpp y núcleo de Quickshell: preferencias, estado, archivos y vigilancia. |
| K | host/src/keyboard.cpp: SHORTCUTS y tecla Win. overlay/ii/services/HyprlandKeybinds.qml alimenta la chuleta; listar un atajo no implementa su acción. |
| H | quickshell/src/win32/compat/hyprland.cpp, toplevels.cpp; overlay/ii/services/HyprlandData.qml: ventanas, monitores, foco/cierre y algunos dispatchers. El resto se ignora. |
| V | quickshell/src/win32/virtualdesktops.cpp; overlay/ii/modules/ii/overview/DesktopStrip.qml; tools/port/patch_ii.py. IVirtualDesktopManager atribuye ventanas, lectura del registro de Explorer lista/nombra escritorios y SendInput de atajos Windows cambia/crea/cierra. Sin COM interno para mover ventanas ajenas. |
| P | quickshell/src/win32/{native,panel_window}.cpp, compat/wayland.cpp: capas, AppBar, entrada, miniaturas DWM, inhibición y bloqueo Windows. |
| A | quickshell/src/core/{winapps,desktopentry}.cpp: índice Menú Inicio/AppsFolder y apertura. |
| M | quickshell/src/win32/services/mpris.cpp: GSMTC. services/pipewire.cpp: Core Audio, dispositivos y sesiones. |
| N | quickshell/src/win32/services/notifications.cpp; host/src/banners.cpp; Q services/Notifications.qml. Avisos Windows/ii y persistencia. |
| T | quickshell/src/win32/services/tray.cpp; overlay/ii/modules/ii/bar/SysTrayItem.qml; Q services/TrayService.qml. Iconos, menús y overflow. |
| R | quickshell/src/core/virtualfiles.cpp; Q services/ResourceUsage.qml: CPU/RAM, aproximación de memoria comprometida como swap y uptime. |
| S | host/src/shim.cpp (despacho), tools/dev/deploy.ps1 (alias); host/src/{switchwall,capture,http,weather,randomwall,cava,sidebar,cliphist,ydotool,secrettool}.cpp; tools/port/patch_ii_tools.py. |
| HW | quickshell/src/win32/services/{battery,bluetooth}.cpp; host/src/brightness.cpp; tools/port/patch_ii_brightness.py. [HARDWARE-SERVICES.md](HARDWARE-SERVICES.md). |
| NET | overlay/ii/services/Network.qml; quickshell/src/win32/services/network.cpp: Native Wi-Fi/Network List Manager sustituyen nmcli. |
| PR | [PROGRESS.md](../PROGRESS.md), [DECISIONS.md](DECISIONS.md), pruebas existentes tools/sandbox/tests/ y tools/dev/test-*.ps1. Resultados anteriores, no repetidos aquí. |

También se leyeron [README.md](../README.md), [FEASIBILITY.md](FEASIBILITY.md) y [SIDEBAR-WINDOWS.md](SIDEBAR-WINDOWS.md). **FEASIBILITY es un plan**, no una lista de funciones terminadas. HW y el código posterior actualizan los antiguos placeholders Bluetooth/batería/brillo. Un parseo QML o una prueba sin hardware no acreditan una conexión real, gamma ni acciones de energía.

## Comandos Linux: emulación y huecos

El alias **bash es limitado**: abre un programa simple o ciertas URI, algunas opciones simples de switchwall y dos nombres de scripts de fondos aleatorios. Rechaza pipelines, variables y scripts generales con código 127. Tener curl u otras herramientas en el PC no arregla el QML que las llama mediante ese “bash”.

| Comando/origen Linux | Ruta actual Windows |
| --- | --- |
| qalc | Parser propio: aritmética, potencias, constantes y funciones básicas. Sin Qalculate completo, unidades ni conversión de monedas. |
| xdg-open, qs, notify-send | ShellExecute, ejecutable Quickshell y avisos al servicio de ii. |
| playerctl | Teclas multimedia globales; play/pause se convierten ambos en toggle. Widgets usan GSMTC dirigido a la sesión. |
| wpctl | Sólo set-mute del dispositivo por defecto; volumen/mezclador usan Core Audio directamente. |
| pidof, pkill, killall, loginctl | Lista/cierre por nombre y lock-session; no toda la semántica Linux. Suspender: ii-shim suspend, no loginctl suspend. |
| switchwall.sh, matugen | switchwall nativo y Material Color Utilities. No requiere matugen instalado. |
| magick, test | Subconjunto: dimensiones/reescalado WIC y existencia de archivos/carpetas. |
| curl/jq para clima/imágenes | patch_ii_net.py: ii-shim weather/fetch para clima, imágenes, portadas y favicons. **fetch es GET; no sustituye POST/streaming del chat ni subida Lens.** |
| nmcli | NET nativo, sin alias nmcli. |
| grim, wl-copy, swappy/satty, tesseract en recortes | Overlays TempScreenshotProcess/ScreenshotAction: GDI/WIC, portapapeles, Paint/asociación de edición y Windows.Media.Ocr. Sin alias de esas herramientas. |
| brightnessctl, ddcutil, cava | Alias nativos distribuidos: WMI, DDC/CI y WASAPI loopback/FFT. |
| hyprsunset | Q parcheado a ii-shim nightlight; gamma SDR con guardián/restauración y fallback a ajustes Windows. |
| cliphist, wl-paste, ydotool | cliphist nativo: historial Windows WinRT, copy/delete/wipe/decode-to y superpaste. wl-paste no se emula: servicio Q Windows sustituye su uso. ydotool key/type usa SendInput; no toda la tabla de códigos ni escritorio seguro. |
| hyprpicker | Sin cuentagotas de pantalla. ChooseColor de switchwall es un diálogo de selección, no lectura de píxeles. |
| wf-recorder, ffmpeg de grabación | Sin grabador; crop ... record informa ausencia; record.sh sigue Linux. |
| trans, songrec | Sin emulación; traductor lateral y reconocimiento musical no operativos. |
| secret-tool, keyring | store/lookup/clear nativos con DPAPI y archivos por usuario/PC. KeyringStorage getter directo y StdioCollector en build. No Administrador de credenciales ni PAM; sí almacén de claves API. |
| checkupdates, which, wc, pacman | Sin contador Windows; abrir actualización sí se cambió a ms-settings:windowsupdate. |
| hyprlock, fuzzel, wlogout, hyprshot | No distribuidos para Windows. Alternativas: bloqueo, Inicio/Win+V/Win+., Recortes y sesión Windows; diferencias de atajos abajo. |
| hyprctl, PAM, Polkit | No compositor real; H sólo cubre ciertas llamadas. PAM/Polkit son placeholders; bloqueo/UAC de Windows. |
| ls/find/rm/mkdir, Python/venv, MicroTeX | Sin equivalentes generales en deploy. Afectan bienvenida, idiomas/prompts/chats y análisis de imágenes. FileView/fetch crean sus propias carpetas nativamente, pero no ejecutan esos scripts. |

Alias de tools/dev/deploy.ps1: ii-shim, qalc, xdg-open, notify-send, playerctl, wpctl, pidof, killall, pkill, loginctl, bash, qs, switchwall, test, magick, ddcutil, brightnessctl, cava, ydotool, secret-tool, cliphist. Los demás subcomandos S se llaman con ii-shim <comando>.


## 1. Interfaces y estructura del escritorio

Evidencia: Q shell.qml, panelFamilies/{IllogicalImpulseFamily,WaffleFamily}.qml; C/H/P/K; PR ii-panels.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 1.1 | Illogical Impulse (ii) | ✅ | Q/P: interfaz Material implementada; límites de integraciones detallados más abajo. |
| 1.2 | Waffle | 🟡 | Familia Q cargable; conserva rutas Linux y no recibió todo el pulido de ii. §24. |
| 1.3 | Cambio de familia en sesión | 🟡 | Q panelFamily.cycle/configuración funcionan por IPC; Ctrl+Win+P no está en K. |
| 1.4 | Carga modular | ✅ | LazyLoader/PanelLoader Q; no programas externos para cargar módulos. |
| 1.5 | Integración Hyprland | 🟡 | H/V dan ventanas/monitores/escritorios Windows; no compositor ni XKB Hyprland. |
| 1.6 | Interfaz Quickshell/QtQuick/QML | ✅ | Fork real y P, mismo motor QML. |
| 1.7 | Persistencia preferencias/estado | ✅ | C JsonAdapter/FileView; PR D18 documenta correcciones de escritura/vigilancia. |
| 1.8 | Recarga de shell | ✅ | Quickshell.reload, CLI/IPC y botón parcheado; Ctrl+Win+R no mapeado. |

## 2. Barra principal de Illogical Impulse

Evidencia: Q modules/ii/{bar,verticalBar}/, modules/settings/BarConfig.qml, services/HyprlandXkb.qml; C/P/H/V/M/N/T/NET/R/HW. PR ii-bar, ii-appbar, ii-tray*.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 2.1 | Posición configurable | ✅ | Q Bar/VerticalBar; P anclajes/AppBar por borde. Multimonitor/DPI físico pendiente. |
| 2.2 | Estilos Hug/Float/Rect | ✅ | Dibujo/opciones Q; P conserva transparencias/esquinas. |
| 2.3 | Autoocultado | ✅ | Q hover/Super/exclusiveZone; K workspaceNumber; P reserva de espacio. |
| 2.4 | Mostrar/ocultar Super+J | ✅ | K barToggle y Q en ambas orientaciones. |
| 2.5 | Selector de espacios | ✅ | V: escritorios reales y cambio con atajos Windows; limitado ante app elevada/registro Explorer cambiante. |
| 2.6 | Iconos por espacio | ✅ | H/V/WorkspaceModel asignan ventanas a escritorios; A da iconos. |
| 2.7 | Numeración configurable | 🟡 | Q números/caracteres/retraso/Super; patch_ii fuerza cantidad a escritorios reales. |
| 2.8 | Iconos normales/teñidos/Nerd Font | ✅ | Q tintado; A/tema/ejecutable y win32/fonts.cpp. |
| 2.9 | Ventana activa | ✅ | H y parche ActiveWindow.qml dan título/nombre legible. |
| 2.10 | Distribución del teclado | 🔧 | HyprlandXkb aún cat/hyprctl devices. Servicio GetKeyboardLayout del hilo enfocado + GetLocaleInfoEx/eventos de idioma; M. |
| 2.11 | Reloj/fecha | ✅ | Q DateTime, Qt.locale y popups; sin comandos Linux. |
| 2.12 | Multimedia | ✅ | M GSMTC y tarjeta Q; app debe publicar controles Windows. |
| 2.13 | CPU/RAM/swap | 🟡 | R CPU/RAM/historial reales; swap aproxima memoria comprometida, no pagefile exacto. |
| 2.14 | Batería | ✅ | HW + Q Battery; se oculta sin batería. Portátil real pendiente. |
| 2.15 | Bandeja | ✅ | T iconos/menús/doble clic/overflow; PR D13/pruebas de bandeja. |
| 2.16 | Indicador de notificaciones | ✅ | N/Q contador/no leídas; listener necesita permiso para avisos ajenos. |
| 2.17 | Clima | ✅ | S weather/Q/parche net; PR test-fetch/ii-net-widgets. Proveedor online requerido. |
| 2.18 | Botones de utilidad | 🟡 | UtilButtons: recorte/micro/tema/energía y teclado QML/ydotool tienen ruta Windows; cuentagotas hyprpicker y record.sh siguen ausentes. Filtrado del sidebar no cubre todos estos botones. |
| 2.19 | Tooltips hover/clic | ✅ | Q StyledToolTip/opciones, entrada Qt. |
| 2.20 | Selección de monitores | ✅ | Q filtra screens; P/H enumeran pantallas. Usar nombres Windows, no DP-1. |

## 3. Overview y organización visual de ventanas

Evidencia: Q modules/ii/overview/; patch_ii.py; H/V/P/K; PR ii-overview-dock, ii-overview-perf, ii-desktops.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 3.1 | Vista general | ✅ | K Win/Win+Tab: cuadrícula actual + tira de escritorios V. |
| 3.2 | Miniaturas en vivo | 🟡 | P DwmRegisterThumbnail; minimizadas usan tarjeta/icono, sin imagen viva garantizada. |
| 3.3 | Cuadrícula 2×5 configurable | 🟡 | Parche 1×1/escala 0.55; cuadrícula de ventanas y tira Windows reemplazan diez escritorios en miniatura. |
| 3.4 | Activar ventana | ✅ | H hl.dsp.focus restaura/trae al frente; PR overview-dock. |
| 3.5 | Cerrar con clic central | ✅ | Q + H hl.dsp.window.close → WM_CLOSE. |
| 3.6 | Mover entre escritorios | ⛔ | Arrastre desactivado; mover HWND de apps ajenas sin API pública equivalente. Usar Vista de tareas Windows. |
| 3.7 | Reposicionar flotantes | ⛔ | Sin arrastre; dispatcher move ignorado. Fuera del manejo de ventanas del port. |
| 3.8 | Identificación de ventanas | 🟡 | Título/appId/tooltip Q; class es ID Windows, xwayland=false sin significado XWayland. |
| 3.9 | Indicador escritorio activo | ✅ | V + Q DesktopStrip/Workspaces, estado reactivo. |
| 3.10 | Cambio de escritorio | ✅ | V cambia/crea/cierra, esperando confirmación Windows. |
| 3.11 | Adaptación a grupos | ⛔ | Lista global Windows, sin grupos Hyprland; presenta escritorios existentes. |
| 3.12 | Búsqueda integrada | ✅ | Q LauncherSearch/campo: escribir reemplaza cuadrícula por resultados. |

## 4. Lanzador y búsqueda

Evidencia: Q services/{AppSearch,LauncherSearch}.qml, modules/common/functions/{Fuzzy,Levendist}.qml; A/S/H/C; PR ii-launcher.ps1. Clipboard/emojis: §5.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 4.1 | Buscar aplicaciones | ✅ | A Menú Inicio/AppsFolder, Win32/Store. |
| 4.2 | Búsqueda aproximada | ✅ | AppSearch/Fuzzy: JavaScript sobre A. |
| 4.3 | Levenshtein | ✅ | AppSearch/Levendist y opción sloppy, sin ejecutables. |
| 4.4 | Abrir apps/terminal | 🟡 | A ejecuta entradas Windows; ruta especial bash -c wt -e ... rechazada por S. Apps de consola no garantizadas. |
| 4.5 | Acciones .desktop | ⛔ | A no importa ese contrato Linux; Jump Lists serían función distinta. |
| 4.6 | Calculadora | 🟡 | S parser básico/Q copia Qt; sin resto de Qalculate/unidades. |
| 4.7 | Ejecutar comandos ($) | 🟡 | Bash limitado S acepta programa simple/URI; no argumentos/pipelines/sudo. Adaptar proceso Windows explícito con argumentos; M. |
| 4.8 | Web (?) | ✅ | Q URL y apertura Qt/S en navegador predeterminado. |
| 4.9 | Excluir sitios | ✅ | Q añade exclusiones de texto a consulta. |
| 4.10 | Priorizar apps (>) | ✅ | Prefijo Q sobre índice A. |
| 4.11 | Historial (;) | ✅ | Cliphist Windows lista/busca historial WinRT; Q fuzzy conserva prefijo ;. Requiere historial habilitado en Ajustes > Sistema > Portapapeles; no almacén ilimitado propio (§5). |
| 4.12 | Emojis (:) | 🔧 | patch_ii_tools ya empaqueta fuzzel-emoji.sh como datos; en este árbol tiene CRLF y Emojis.updateEmojis divide sólo por \n: no encuentra marcador. Normalizar /\r?\n/ y reparar rama sloppySearch (entries/list); S. No hace falta ejecutar Fuzzel. |
| 4.13 | Priorizar matemáticas (= / número) | ✅ | Prioridad Q por prefijo/número; cálculo con límites 4.6. |
| 4.14 | Acciones internas (/) | ✅ | Q sugerencias/dispatch; cada acción se evalúa aparte. |
| 4.15 | Tema oscuro /dark | ✅ | Q → S switchwall --mode dark --noswitch. |
| 4.16 | Tema claro /light | ✅ | Q → S switchwall --mode light. |
| 4.17 | Wallpaper /wallpaper | ✅ | H global abre selector; Q Wallpapers/S. |
| 4.18 | Acento /accentcolor | ✅ | S --color/ChooseColor y paleta; no cuentagotas. |
| 4.19 | Konachan /konachanwallpaper | ✅ | patch_ii_tools y Q LauncherSearch ahora llaman ii-shim randomwall konachan directamente; backend randomwall/http/switchwall existente. Proveedor/red necesarios. |
| 4.20 | Tarea /todo | ✅ | Todo.addTask/FileView Q. |
| 4.21 | Borrar historial /wipeclipboard | ✅ | LauncherSearch → Cliphist.wipe → alias cliphist wipe → WinRT Clipboard.ClearHistory; refresca lista. Opera sobre historial de Windows. |
| 4.22 | Varias entradas /superpaste | 🟡 | Cliphist Windows/SendInput ya pegan entradas en orden; no verifican entrega a app ni restauran foco/cancelan operación. Apps elevadas y lentas requieren validación (§5). |
| 4.23 | Acciones propias | 🟡 | FolderListModel detecta archivos/.exe; .sh/.ps1 sin intérprete automático y argumentos por espacios. Adaptador por extensión; S. |
| 4.24 | Prefijos/opciones | ✅ | C/Q reactivos; no habilitan backends faltantes. |

## 5. Portapapeles y emojis

Evidencia: overlay/ii/services/Cliphist.qml y build equivalente; host/src/cliphist.cpp, shim.cpp, CMakeLists.txt/deploy; patch_ii_tools.py conecta previews y empaqueta emojis; Q services/{Emojis,LauncherSearch}.qml y common/widgets/CliphistImage.qml; K. Implementaciones nuevas leídas, no ejecutadas.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 5.1 | Historial de texto | ✅ | cliphist list usa WinRT Clipboard.GetHistoryItemsAsync; Q búsqueda/copiar sobre historial Windows. Debe estar habilitado; rigen formatos, retención y políticas de Windows, sin almacén propio ilimitado. |
| 5.2 | Historial de imágenes | ✅ | cliphist enumera Bitmap y decode-to convierte con BitmapDecoder/Encoder a PNG; CliphistImage parcheado carga previews. Sólo imágenes que Windows haya admitido en su historial. |
| 5.3 | Vista Super+V | ✅ | K overviewClipboardToggle → Q/Cliphist Windows; refresca al abrir. Historial desactivado en Windows produce lista vacía, no captura automática propia. |
| 5.4 | Recuperar entrada | ✅ | LauncherSearch/Cliphist.copy → SetHistoryItemAsContent restaura contenido original. La acción normal copia; Ctrl+V en la app pega, igual al flujo ii. |
| 5.5 | Eliminar entrada | ✅ | Cliphist.deleteEntry → cliphist delete-id/Clipboard.DeleteItemFromHistory; al terminar actualiza lista. |
| 5.6 | Vaciar historial | ✅ | Cliphist.wipe → cliphist wipe/Clipboard.ClearHistory y refresco; afecta historial compartido de Windows, no sólo ii. |
| 5.7 | Superpaste ordenado | 🟡 | Cliphist invierte últimas entradas para pegar de antigua a reciente; cliphist superpaste usa pausas y SendInput Ctrl+V. Sin restauración explícita de foco/cancelación ni comprobación del resultado SendInput; no garantía en apps elevadas/lentas. |
| 5.8 | Superpaste imágenes | 🟡 | Filtro entryIsImage y superpaste ya implementados con contenido Bitmap original; mismo límite de foco/entrega por aplicación y retención Windows de 5.7. |
| 5.9 | Selector emojis Super+. | 🔧 | K y recurso assets/emoji/fuzzel-emoji.sh ya conectados por patch_ii_tools; archivo local CRLF impide indexOf("### DATA ###") tras split("\n"). Usar split(/\r?\n/), normalizar marcador y corregir entries/list en búsqueda permisiva; S. |
| 5.10 | Actualización del historial | 🟡 | Cliphist escucha Quickshell.clipboardTextChanged y refresca al abrir overview/por IPC. No suscribe Clipboard.HistoryChanged: cambios sólo de imagen mientras panel sigue abierto pueden no actualizarse; conectar evento WinRT o señal de cambio completa, S. |
| 5.11 | Alternativas de emergencia | 🟡 | Fuzzel ausente; Win+V/Win+. nativos existen, K los captura mientras ii tiene sink. Opción para liberarlos/rescate; S. |
| 5.12 | Filtro visual contextual | 🟡 | Historial de imágenes operativo; heurística de enlaces/palabras y blur Q/NET. SSID/contexto no clasifican contenido fiablemente; no detector visual universal. |

## 6. Dock opcional

Evidencia: Q modules/ii/dock/, services/TaskbarApps.qml; overlay DockContextMenu.qml; C/A/H/P/V; PR ii-overview-dock/ii-dock-minimize.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 6.1 | Dock | ✅ | Q/P; Windows dock.enable=true por parche. |
| 6.2 | Apps fijadas | ✅ | C/TaskbarApps; defaults Explorador/Terminal, pin/unpin. |
| 6.3 | Apps abiertas/agrupadas | ✅ | H/A/TaskbarApps por appId/AUMID; correcciones Explorer/Terminal PR. |
| 6.4 | Abrir/enfocar | ✅ | A/H; parche minimiza al pulsar única ventana al frente. |
| 6.5 | Preview hover | 🟡 | Popup Q/P DWM vivo; minimizadas sin captura viva garantizada. |
| 6.6 | Elegir ventana en preview | ✅ | Toplevel.activate/H restaura y enfoca. |
| 6.7 | Cerrar en preview | ✅ | Q Toplevel.close/WM_CLOSE normal. |
| 6.8 | Ocultar/revelar | ✅ | Q hover/escritorio vacío, región inferior P. |
| 6.9 | Fijar visible | ✅ | Estado Q/C/pinnedOnStartup. |
| 6.10 | Acceso overview | ✅ | GlobalStates/overview Q/H. |
| 6.11 | Apariencia/contenido | ✅ | Q/C altura/tintado/filtros por patrón. |

## 7. Ajustes rápidos y panel derecho

Evidencia: Q sidebarRight/, common/models/quickToggles/, ii/screenCorners/; patch_ii_sidebar/brightness; K/P/NET/M/HW/S/C.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 7.1 | Panel Super+N | ✅ | K sidebarRightToggle/Q loader. |
| 7.2 | Android/clásico | ✅ | Dos componentes Q; parches para ambos. |
| 7.3 | Editar mosaicos | ✅ | Q editor/parche conserva índices al filtrar; test-sidebar documenta JS. |
| 7.4 | Columnas | ✅ | Q/C distribución. |
| 7.5 | Controles iniciales | 🟡 | Red/inhibidor/audio/micro; Bluetooth condicionado, nightlight según gamma o abre Windows. |
| 7.6 | Otros mosaicos | 🟡 | Tema/energía/avisos; juego/teclado/Recortes delegan Windows. EasyEffects/WARP/SongRec/anti-flashbang/cuentagotas ocultos. |
| 7.7 | Sliders opcionales | ✅ | M y Brightness.qml/HW; ocultos sin endpoint/lectura válida. Hardware físico pendiente. |
| 7.8 | Sistema/uptime | ✅ | S system-info/R; cabecera Windows/tiempo encendido. |
| 7.9 | Recargar Hyprland/Quickshell | 🟡 | Quickshell.reload; hyprctl retirado, no hay compositor. |
| 7.10 | Abrir ajustes | ✅ | Engranaje Q/S qs -p settings.qml abre ii. |
| 7.11 | Menú sesión | ✅ | GlobalStates.sessionOpen Q/overlay Session. |
| 7.12 | Secciones plegables | ✅ | Q calendario/tareas/timers; C guarda plegado/pestaña. |
| 7.13 | Mantener panel cargado | ✅ | Loader Q/opción; consumo de memoria esperado. |
| 7.14 | Paneles desde esquinas | ✅ | Q ScreenCorners/P hover/clic; multimonitor físico pendiente. |
| 7.15 | Scroll brillo/volumen | ✅ | Q Audio/Brightness → M/HW si soportado. |
| 7.16 | Regiones sensibles | ✅ | Dimensiones/márgenes/debug Q y entrada P. |

## 8. Redes y Bluetooth

Evidencia: NET; Q sidebarRight/{wifiNetworks,bluetoothDevices}/; HW/patch_ii_brightness; PR ii-network/test-hardware. Wi-Fi/radio reales pendientes.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 8.1 | Wi-Fi on/off | ✅ | NET WlanSetInterface/radio; adaptador/permisos requeridos. |
| 8.2 | Redes/reescaneo | ✅ | NET WlanScan/lista/UI. |
| 8.3 | SSID/señal/seguridad | ✅ | NET modelo Q activo/protegido. |
| 8.4 | Conectar desde panel | 🟡 | WlanConnect/perfiles personales o conocidos; EAP empresarial no completo, sin prueba Wi-Fi física. |
| 8.5 | Contraseña | ✅ | NET/WifiNetworkItem perfil personal; no credenciales EAP. |
| 8.6 | Portal público | 🟡 | NET abre URL de comprobación; depende red/navegador, no resuelve cualquier portal. |
| 8.7 | Ethernet/Wi-Fi | ✅ | NLM/Native Wi-Fi, fallback ajustes para cable. |
| 8.8 | Ajustes avanzados red | ✅ | Config/parches ms-settings:network-wifi/ethernet/status. |
| 8.9 | WARP | 🔧 | Oculto; detectar cliente Windows y wrapper ii-shim warp status/connect/disconnect JSON; M opcional. |
| 8.10 | Bluetooth on/off | ✅ | HW Radios RequestAccessAsync/SetStateAsync por clic; sin radio explícito. |
| 8.11 | Descubrir Bluetooth | ✅ | HW DeviceWatcher Classic/LE; para al cerrar/desactivar/30 s. |
| 8.12 | Nombre/tipo/estado | ✅ | HW DeviceInformation/paired/connected; duplicados y multiadaptador pendientes físicos. |
| 8.13 | Batería del accesorio | 🔧 | batteryAvailable=false. Servicio BLE Battery 0x180F/2A19 si accesible; Classic/propietarios no universales; M. |
| 8.14 | Emparejar/olvidar | 🟡 | HW ConfirmOnly/Unpair; PIN/otras ceremonias abren ajustes. |
| 8.15 | Conectar/desconectar | 🟡 | GattSession para LE; audio/HID/RFCOMM delegan Windows, sin API genérica pública. |
| 8.16 | Ajustes Bluetooth | ✅ | Config/botones ms-settings:bluetooth. |

## 9. Audio y micrófono

Evidencia: Q services/{Audio,Privacy,EasyEffects}.qml, sidebarRight/volumeMixer/; M/S/K/patch_ii_sidebar.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 9.1 | Volumen general | 🟡 | M sliders funcionan; K no captura teclas volumen para OSD ii, siguen Windows. |
| 9.2 | Silenciar salida | 🟡 | M/wpctl disponibles; Win+Shift+M no mapeado, Windows restaura minimizadas. |
| 9.3 | Volumen/silencio micro | 🟡 | M controles con entrada; Win+Alt+M no mapeado. |
| 9.4 | Elegir salida | 🟡 | Lista dispositivos; VolumeDialogContent abre ms-settings:sound al elegir. M tiene IPolicyConfig interno en otra ruta, sin garantía pública. |
| 9.5 | Elegir entrada | 🟡 | Mismo delegado a ajustes; Audio.setSource no acredita selección directa en este diálogo. |
| 9.6 | Mezclador por app/flujo | ✅ | M rescanSessions enumera endpoints de salida y captura; IAudioSessionManager2/ISimpleAudioVolume dan volumen/mute por sesión activa. Equivalente Windows, sin grafo PipeWire. |
| 9.7 | Mezclador externo | ✅ | Config ms-settings:apps-volume, detalles Windows. |
| 9.8 | EasyEffects | ⛔ | Linux/PipeWire, tile oculto. APO/plugins Windows serían otro subsistema. |
| 9.9 | EasyEffects nativo/Flatpak | ⛔ | Detección easyeffects/flatpak no aplica al runtime Windows. |
| 9.10 | Protección de volumen | ✅ | Audio.qml escucha cambios/limita nivel e incrementos escribiendo M. |
| 9.11 | Indicadores de actividad | 🔧 | Privacy consulta linkGroups vacíos en M. Sesiones activas de captura para micro; estado propio para grabación ii, sin cobertura universal ajena; M. |
| 9.12 | Sonidos | 🟡 | S system-sound/MessageBeep para timers/batería; no todos los temas/nombres Linux. |

## 10. Multimedia y reconocimiento de canciones

Evidencia: M; Q services/{MprisController,SongRec}.qml, modules/ii/mediaControls/, scripts/musicRecognition/recognize-music.sh; S cava/K; PR ii-media/ii-net-widgets.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 10.1 | Detectar reproductores | ✅ | M GSMTC SessionManager, equivalente Windows. |
| 10.2 | Título/artista/carátula | ✅ | M metadatos y parche PlayerControl/fetch; app debe suministrar datos. |
| 10.3 | Play/pausa | 🟡 | Widgets M y teclas multimedia Windows; Win+Shift+P ausente en K. |
| 10.4 | Anterior/siguiente | 🟡 | M/teclas Windows; Win+Shift+N/B no mapeados. |
| 10.5 | Tiempo/progreso | ✅ | M timeline/posición, Q dibuja. |
| 10.6 | Buscar en pista | ✅ | M TryChangePlaybackPositionAsync cuando app permite seek. |
| 10.7 | Varios reproductores | ✅ | Modelo M/sesiones, Q MediaControls/K Win+M. |
| 10.8 | Filtrar duplicados | 🟡 | Filtro Q específico de Plasma/playerctld D-Bus, sin nueva deduplicación GSMTC equivalente. |
| 10.9 | Cava | ✅ | S WASAPI loopback/FFT, alias deploy y Q AudioVisualiser/MediaWidget; no Linux. |
| 10.10 | Reconocer canción | 🔧 | SongRec .sh/songrec/pw-record ausentes/oculto. WASAPI + proveedor de reconocimiento/credenciales/consentimiento; L. |
| 10.11 | Elegir qué escuchar | 🔧 | Core Audio selección + loopback/captura del reconocedor; M dependiente de 10.10. |
| 10.12 | Resultado en notificación | 🟡 | Q/N preparados; sin reconocedor no produce resultado real. |
| 10.13 | Abrir Shazam/YouTube | 🟡 | Q enlaces/S operativos si hay resultado; backend ausente. |
| 10.14 | Timeout/intervalo | 🟡 | C 16/4 s, sin proceso operativo que los aplique. |

## 11. Notificaciones

Evidencia: Q services/Notifications.qml, modules/ii/{notificationPopup,sidebarRight}/; N/S; PR ii-notifications, test-banners.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 11.1 | Servidor integrado | ✅ | N recibe avisos Windows con permiso y notify-send de ii; no servidor D-Bus Linux. |
| 11.2 | Popups temporales | ✅ | Q popup/temporizador; N entrega avisos, host suprime banners duplicados. |
| 11.3 | Historial persistente | ✅ | Q FileView/JSON; al cargar pierde acciones como en Linux. |
| 11.4 | Agrupación por app | ✅ | Q lista/grupos/orden temporal; sin comando externo. |
| 11.5 | Contenido enriquecido | 🟡 | Q muestra markup/enlaces; N extrae textos e icono de app de toasts Windows, no todo XML/imágenes del aviso original. |
| 11.6 | Acciones de notificación | ⛔ | UserNotificationListener no permite ejecutar botones privados de otras apps. N ofrece Open a la app, sin “Responder”/acción original. |
| 11.7 | Eliminar una/todas | ✅ | Q/N removeNotification y descarte sincronizan centro Windows. |
| 11.8 | Contador no leídas | ✅ | Q contador/estado de lectura. |
| 11.9 | Modo silencioso | 🟡 | Q inhibe popups de ii; no cambia No molestar global Windows. |
| 11.10 | Evitar popup con centro abierto | ✅ | Condición Q del panel/estado, sin API Linux. |
| 11.11 | Duración configurable | ✅ | Q timeout y S notify-send -t; límite por tipo de aviso. |
| 11.12 | Monitor específico | ✅ | Q selecciona screen; P/H soportan pantallas Windows. |
| 11.13 | Transitorias | 🟡 | Q/S admiten transient; flags/hints de Linux no se recuperan completos desde toasts Windows. |
| 11.14 | Límite de persistencia de botones | ✅ | Q onLoaded restaura actions=[]; no finge recuperar acciones de procesos muertos. |

## 12. Calendario, tareas y concentración

Evidencia: Q sidebarRight/{calendar,todo,pomodoro}/, services/{Todo,TimerService}.qml, modules/common/Persistent.qml; C/S/N; Q waffle/notificationCenter/FocusFooter.qml.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 12.1 | Calendario mensual | ✅ | Q cuadrícula/Date/navegación, sin backend Linux. |
| 12.2 | Locale calendario | ✅ | Qt.locale/C; no calendario online. |
| 12.3 | Bloque plegable | ✅ | Q vista reducida/completa. |
| 12.4 | Lista de tareas | ✅ | Todo.addTask desde panel/acción /todo. |
| 12.5 | Marcar completada | ✅ | Todo.markDone: JS/FileView. |
| 12.6 | Volver a pendiente | ✅ | Todo.markUnfinished: JS/FileView. |
| 12.7 | Eliminar tarea | ✅ | Todo.deleteItem: JS/FileView. |
| 12.8 | Contador de pendientes | ✅ | Q cuenta done=false. |
| 12.9 | Persistencia local | ✅ | JSON/FileView C; no sincronización externa. |
| 12.10 | Pomodoro | ✅ | TimerService/Q temporizador focus/break/longBreak. |
| 12.11 | Duraciones | ✅ | C/TimerService, 25/5/15 min iniciales. |
| 12.12 | Ciclos | ✅ | C/TimerService: cuatro antes del descanso largo. |
| 12.13 | Controles temporizador | ✅ | Q/TimerService toggle/reset/pausa/reanudación. |
| 12.14 | Avisos/sonido | ✅ | N notify-send y S system-sound, MessageBeep en Windows, opcional. |
| 12.15 | Cronómetro | ✅ | TimerService usa Date.now/Timer/Persistent. |
| 12.16 | Vueltas | ✅ | JS laps/diferencias en Q. |
| 12.17 | Memoria del panel | ✅ | Persistent sidebar.bottomGroup guarda pestaña/plegado. |
| 12.18 | Concentración en Waffle | ✅ | FocusFooter Q usa TimerService compartido; sin programa Linux para el contador. |

## 13. Panel izquierdo e inteligencia artificial

Evidencia: Q modules/ii/sidebarLeft/{SidebarLeft,AiChat}.qml, services/Ai.qml, services/ai/, KeyringStorage.qml, LatexRenderer.qml; C/K/S; host/src/secrettool.cpp/cliphist.cpp y patch_ii_tools.py. **Las claves tienen backend DPAPI; Ai aún genera scripts bash/curl sin transporte IA nativo.**

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 13.1 | Panel Super+A | ✅ | K sidebarLeftToggle/Q carga módulos según políticas; abrir panel no acredita chat operativo. |
| 13.2 | Ampliar/fijar/separar | 🟡 | Ampliar/detach Q/Qt; togglePin intenta hyprctl cursorpos/move y falla. Quitar workaround y cambiar pin directamente; S. |
| 13.3 | Chat IA | 🔧 | Ai baseCommand=[bash], genera script curl --no-buffer; S no lo ejecuta. POST/streaming nativo WinHTTP/QNetworkAccessManager + parser SSE por proveedor; L. |
| 13.4 | Proveedores configurados | 🟡 | Q conserva entradas/endpoints (incluidos nombres Gemini/Mistral) y claves DPAPI; falta transporte. Sin consulta online no se garantiza disponibilidad/precio. |
| 13.5 | Ollama local | 🔧 | show-installed-ollama-models.sh ausente en runtime. GET localhost:11434/api/tags y POST /api/chat streaming, sin bash; M. |
| 13.6 | Modelos personalizados | 🟡 | Config Q admite modelo/endpoint/formato y KeyringStorage guarda claves DPAPI; transporte todavía impide conversar. |
| 13.7 | Elegir modelo /model | ✅ | Ai.setModel cambia Persistent y respeta política; selección local Q, no valida proveedor. |
| 13.8 | Clave /key | ✅ | KeyringStorage store/lookup directo → alias secret-tool. secrettool.cpp usa CryptProtectData/CryptUnprotectData y archivos en %LOCALAPPDATA%\ii-windows\secrets, ligados al usuario/PC; no es Administrador de credenciales ni desbloqueo PAM. No se probó persistencia ejecutando. |
| 13.9 | System prompt /prompt | 🟡 | Texto/config y FileView disponibles; sugerencias/lista usa ls -1. FolderListModel o enumeración nativa; S. |
| 13.10 | Temperatura /temp | ✅ | Ai.setTemperature/Persistent actualizan número local; backend aún no lo envía a modelo operativo. |
| 13.11 | Herramientas /tool | 🟡 | Selección Q disponible; sin API chat no se reciben/ejecutan llamadas de proveedor. |
| 13.12 | Respuestas progresivas | 🔧 | Script curl y SplitParser preparados, sin proceso operativo. Transporte SSE/NDJSON cancelable y señales incrementales; M dentro de 13.3. |
| 13.13 | Markdown/código | 🟡 | Renderer Q presenta texto/controles; shim SyntaxHighlighter es no-op, código plano; resaltador Qt/JS factible M. |
| 13.14 | LaTeX | 🔧 | LatexRenderer invoca bash cd/ejecutable MicroTeX, no distribuido. Compilar MicroTeX Windows y llamar .exe con argumentos/rutas; M. |
| 13.15 | Bloques de pensamiento | 🟡 | Q visual/parseadores presentes; sin respuestas reales por transporte ausente. |
| 13.16 | Referencias/búsqueda | 🟡 | Q anotaciones/estrategias; requieren API/proveedor y transporte que falta. |
| 13.17 | Adjuntar archivos /attach | 🔧 | Seleccionar archivo y recuperar imagen de historial con decode-to ya tienen ruta Windows; GeminiApiStrategy aún arma curl upload. Subida HTTP binaria/resumible nativa + MIME/archivo; M tras transporte 13.3. |
| 13.18 | Regenerar/eliminar mensajes | 🟡 | Eliminar es JS operativo; regenerar vuelve al solicitante bash no operativo. |
| 13.19 | Guardar/cargar conversaciones | 🟡 | Ai.saveChat/loadChat con FileView; listado/sugerencias ls -1 ausente, y no chat real para guardar respuestas. Nombre explícito no requiere ese listado. |
| 13.20 | Limpiar /clear | ✅ | Limpieza de mensajes/mapa local en Q. |
| 13.21 | Información de uso | 🟡 | Modelo/temperatura y clave local DPAPI sí; tokens/respuestas reales dependen del transporte ausente. |
| 13.22 | Leer/modificar configuración con IA | 🟡 | Ai funciones get_shell_config/set_shell_config JS disponibles; no hay conversación que genere llamadas. No equivale a asistente operativo. |
| 13.23 | Proponer comandos con aprobación | 🟡 | Q aprobar/rechazar existe; ejecución bash -c limitada por S. Adaptar proceso Windows/argumentos y conservar aprobación; M. |
| 13.24 | Políticas desactivada/local | ✅ | C/Q ocultan o impiden modelos online según policies.ai; no preparan Ollama. |
| 13.25 | Resumen de texto seleccionado | 🔧 | Script Linux de atajo/Ollama sin hook equivalente. Capturar selección mediante copiar/clipboard, POST Ollama y abrir resumen; M tras 13.5. |

## 14. Traducción

Evidencia: Q sidebarLeft/Translator.qml, ii/screenTranslator/, common/models/gCloud/{GCloudVision,GCloudTranslate}.qml, services/GoogleCloud.qml y KeyringStorage; scripts/ai/gemini-translate.sh; S.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 14.1 | Traductor lateral | 🔧 | bash -c trans ... y trans -list-languages no emulados. ii-shim translate con proveedor HTTP configurado/clave, o servicio Q nativo; M. |
| 14.2 | Entrada/salida texto | 🟡 | Campos y render Q operativos; sin trans no llega traducción. |
| 14.3 | Idiomas/detección | 🟡 | Opciones Q, pero lista viene de trans. Catálogo local/proveedor y detección en backend; S tras 14.1. |
| 14.4 | Elegir motor | 🔧 | Nombres de motores trans no son adaptadores Windows. Implementar uno o más adaptadores API explícitos con capacidades; M. |
| 14.5 | Reutilizar/copiar resultado | 🟡 | Controles Q/clipboard Qt; sin backend no hay resultado generado. |
| 14.6 | Retardo configurable | ✅ | Timer Q al escribir/C; no depende de trans para medir retardo. |
| 14.7 | Traducción de pantalla | 🔧 | K abre panel/captura nativa, pero pipeline Cloud no opera. OAuth + Vision/Translation nativos y alimentar overlay Q; L. |
| 14.8 | OCR Cloud Vision | 🔧 | Q usa bash/base64/curl POST. Codificar imagen con QByteArray/Base64 y HTTP POST con token; M dentro de 14.7. |
| 14.9 | Cloud Translation posicionada | 🔧 | Q conserva bloques/overlay; adaptar POST y parser nativos sin curl; M dentro de 14.7. |
| 14.10 | Zoom/desplazamiento captura | ✅ | Transformaciones y MouseArea Q; imagen capturada S, independientemente de traducir. |
| 14.11 | JSON credenciales | 🔧 | Almacén secret-tool/DPAPI sí existe; GoogleCloud token-from-key-venv.sh/Python google.auth siguen Linux. Implementar firma JWT/OAuth con CNG y HTTP nativo, adaptar consumo del JSON; M. |
| 14.12 | Progreso/error | 🟡 | Estados Q existentes; pasos nativos de captura sí, autenticación/subida/traducción no operativas. |
| 14.13 | Requisitos Cloud | 🟡 | Siguen necesarios internet/APIs/cuenta/facturación y credenciales; instalador no los prepara y el port además carece de transporte. |
| 14.14 | Traducir interfaz con Gemini | 🔧 | gemini-translate.sh/curl/jq/gestión de traducciones Linux. Leer JSON, POST Gemini nativo y validar/guardar claves en FileView; M. |

## 15. Galería de ilustraciones y fondos online

Evidencia: Q services/{Booru,BooruResponseData}.qml, sidebarLeft/Anime.qml, anime/BooruImage.qml; XMLHttpRequest Qt; patch_ii_net/ImageDownloaderProcess; S randomwall/http.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 15.1 | Buscar por etiquetas | ✅ | Booru usa XMLHttpRequest, API Qt disponible; requiere proveedor accesible. |
| 15.2 | Sugerencias de etiquetas | ✅ | Booru XMLHttpRequest/parseado por adaptador, según proveedor. |
| 15.3 | Elegir proveedor /mode | ✅ | Config/estado y adaptadores Q; selección sin Linux. |
| 15.4 | Galería previews | ✅ | Q modelo/proporciones/tags; ImageDownloaderProcess parcheado a S fetch. |
| 15.5 | Paginación | ✅ | Booru/Anime JS cambia página/consulta. |
| 15.6 | Abrir original | ✅ | Q URL + apertura S/Qt. |
| 15.7 | Abrir fuente | ✅ | Mismo mecanismo con URL del proveedor. |
| 15.8 | Descargar ilustración | 🔧 | BooruImage aún mkdir/curl/notify-send bajo bash. Cambiar a ii-shim fetch --out y notificar tras éxito; S. |
| 15.9 | Limpiar resultados | ✅ | Booru/Anime vacían lista JS. |
| 15.10 | Filtro de contenido | ✅ | Q filtra metadatos/tags, allowNsfw=false inicial; cobertura depende de proveedor, no análisis universal. |
| 15.11 | Política de visibilidad | ✅ | C/Q policies.weeb y SidebarLeftContent. |
| 15.12 | Fondos Konachan/osu! | 🟡 | S randomwall y rutas desde ajustes/acción /konachanwallpaper nativas. Konachan probado antes; PR osu! respondió 403. Acceso al proveedor sigue condicionado. |
| 15.13 | Requisitos del proveedor | ❓ | Adaptadores/usuario configurables en Q; no se consultó red ni credenciales, disponibilidad actual/Zerochan no acreditada. |

## 16. Capturas, OCR, búsqueda visual y grabación

Evidencia: Upstream Q common/utils/ScreenshotAction.qml y scripts/videos/record.sh; overlays ScreenshotAction/TempScreenshotProcess; Q ii/regionSelector/; host/src/capture.cpp/S/K; PR ii-snip.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 16.1 | Monitor al portapapeles Print | 🟡 | S screenshot --copy y botón overlay funcionan; Print no llega a ii desde K (Windows conserva su conducta propia). |
| 16.2 | Portapapeles + archivo Ctrl+Print | 🔧 | K no lo mapea; S screenshot/crop save ya tienen piezas. Añadir comando capture-and-save fechado y hook/IPC al monitor activo; S. |
| 16.3 | Recortar región Super+Shift+S | ✅ | K regionScreenshot; selector Q → S GDI/WIC/crop copy; tile sidebar abre Recortes Windows por otra ruta. |
| 16.4 | Copiar/anotar según botón | ✅ | Q acciones Copy/Edit → S crop copy/edit, portapapeles y editor asociado/Paint. |
| 16.5 | Rectángulo/círculo | 🟡 | UI Q dibuja ambos; S crop recibe x/y/w/h y recorta rectangular, sin máscara circular de salida. |
| 16.6 | Guías de selección | ✅ | Líneas/contorno/padding Q, sin Linux. |
| 16.7 | Selección asistida por regiones | 🟡 | H geometrías de ventanas alimentan Q; layers vacío, análisis de contenido Python ausente. |
| 16.8 | Detección local de contenido | 🔧 | find-regions-venv.sh/Python/OpenCV no ejecutable por S. Portar algoritmo a C++/OpenCV Windows y devolver regiones JSON; M. |
| 16.9 | Anotar capturas Swappy/Satty | 🟡 | S edit usa Paint/asociación, no Swappy/Satty ni sus opciones; conserva edición externa equivalente. |
| 16.10 | OCR local Super+Shift+X | ✅ | K regionOcr/S crop ocr → Windows.Media.Ocr + portapapeles; no Tesseract. |
| 16.11 | Idiomas OCR | ✅ | S TryCreateFromUserProfileLanguages/AvailableRecognizerLanguages; requiere paquete OCR Windows instalado, no paquetes tesseract. |
| 16.12 | Google Lens Super+Shift+A | 🔧 | K abre selección Search; S crop search termina “no portado”. HTTP upload explícito + URL del motor en navegador, con permiso de subir captura; M. |
| 16.13 | Motor búsqueda visual/círculo | 🟡 | C conserva URL/modo Q; no subida/búsqueda ni máscara circular nativa. |
| 16.14 | Cuentagotas Super+Shift+C | 🔧 | hyprpicker ausente y atajo no mapeado. Overlay selección/píxel GDI/WIC/GetPixel, copiar #RRGGBB y hook; M. |
| 16.15 | Grabar región sin sonido | 🔧 | K regionRecord sí; S crop record falla. Windows.Graphics.Capture + Media Foundation encoder/estado de grabación; L. |
| 16.16 | Grabar monitor sin sonido | 🔧 | Ctrl+Alt+R no mapeado; mismo grabador Windows con selección de monitor; L compartido con 16.15. |
| 16.17 | Grabar monitor con sonido | 🔧 | Hook ausente/record.sh Linux. WASAPI loopback + mux/Media Foundation; L compartido. |
| 16.18 | Grabar región con sonido | 🔧 | Q/IPC preparado pero no grabador. WGC/loopback/encoder + recorte; L compartido. |
| 16.19 | Detener grabación | 🔧 | pidof/pkill wf-recorder no sirven sin grabador. IPC start/stop/status, cerrar encoder limpiamente; M dentro del subsistema anterior. |
| 16.20 | MP4 fechado | 🔧 | record.sh no operativo. Crear archivo fecha/hora con Media Foundation SinkWriter y carpeta configurable; M dentro del grabador. |
| 16.21 | Abrir carpeta grabaciones | ✅ | Q botón abre directorio con Qt/S; no requiere que ya existan grabaciones. Videos/Directories Windows. |
| 16.22 | Audio de grabación | 🔧 | WASAPI loopback de salida seleccionada (reutilizar experiencia cava), timestamps/mux; M, requiere grabador L. |
| 16.23 | Fallbacks Hyprshot/Grim/Slurp | ⛔ | Herramientas Wayland no aplican. Recortes Windows es alternativa, no emulación de esos scripts. |

## 17. Overlay de widgets

Evidencia: Q ii/overlay/{OverlayContext,StyledOverlayWidget}.qml y carpetas crosshair/floatingImage/recorder/resources/notes/volumeMixer; C/P/M/R/S/K; patch_ii.py; PR ii-overlay/ii-net-widgets.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 17.1 | Abrir Super+G | ✅ | K overlayToggle/Q. |
| 17.2 | Crosshair | ✅ | Q parser/dibujo del código; P superposición/clickthrough, sin integración en juego. |
| 17.3 | Limitador FPS MangoHud | ⛔ | patch_ii retira opción. MangoHud/inyección en apps Linux no aplica; no limitador global Windows en este port. |
| 17.4 | Imagen/GIF flotante | ✅ | Q AnimatedImage/escala y S fetch para URL; archivo local también. |
| 17.5 | Grabador | 🟡 | Botón captura entera y selector screenshot operativos; botones de video remiten a record.sh/record sin backend. |
| 17.6 | Recursos | 🟡 | R/Q CPU/RAM/historial; swap aproximado como en 2.13. |
| 17.7 | Notas locales | ✅ | NotesContent/FileView C guarda texto en notes.txt. |
| 17.8 | Viñetas copiables | ✅ | Q NotesContent identifica líneas “-” y usa Quickshell.clipboardText, sin wl-copy. |
| 17.9 | Mezclador flotante | ✅ | Q/M lista sesiones activas/volumen/mute; mismos dispositivos Core Audio. |
| 17.10 | Arrastrar/redimensionar | ✅ | Q MouseArea/controles y P; se mueven widgets propios, no aplicaciones ajenas. |
| 17.11 | Fijar sobre escritorio | ✅ | Q/C pinned mantiene loader visible al salir de edición. |
| 17.12 | Pasar clics/interactividad | ✅ | Q regiones/P WS_EX_TRANSPARENT; estado clickthrough configurable. |
| 17.13 | Centrar/cerrar/estado | ✅ | Q geometría/opciones, C Persistent. |
| 17.14 | Oscurecer/animar fondo | ✅ | Q Rectangle/animaciones; no shader compositor. |

## 18. Wallpapers, Material You y estética

Evidencia: Q ii/wallpaperSelector/, services/{Wallpapers,MaterialThemeLoader}.qml, common/{Config,Appearance}.qml; S switchwall/capture; host/src/theme.cpp; PR D16–D18, ii-wallpaper, test-theme.ps1.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 18.1 | Selector wallpapers Ctrl+Super+T | ✅ | K/Q/S; carpetas Windows y miniaturas WIC. |
| 18.2 | Navegar carpetas | ✅ | Q FolderListModel/Directories StandardPaths, atrás/adelante/subir. |
| 18.3 | Buscar/navegar teclado | ✅ | Q filtro y teclas, sin Linux. |
| 18.4 | Aleatorio de carpeta | ✅ | Q Wallpapers/K random/S switchwall; enumera imágenes. No confundir ruta /konachanwallpaper. |
| 18.5 | Selector sistema | ✅ | S switchwall usa GetOpenFileNameW en lugar de kdialog. |
| 18.6 | Paleta del wallpaper | ✅ | S Material Color Utilities de Google, extracción/49 colores; no matugen externo. |
| 18.7 | Modos de paleta | ✅ | switchwall makeScheme Content/Expressive/Fidelity/FruitSalad/Monochrome/Neutral/Rainbow/TonalSpot + auto. |
| 18.8 | Acento manual | ✅ | S --color/ChooseColor; paleta desde color explícito. |
| 18.9 | Claro/oscuro | ✅ | S/Q y K Ctrl+Win+Shift+D; host/theme acompaña Windows/restaura. |
| 18.10 | Temas GTK/Qt/KDE de apps | ⛔ | Integración Linux/applycolor.sh no aplica a apps Windows. El tema ii y acento Windows son sustitutos distintos, ya implementados. |
| 18.11 | Colores de terminal | 🟡 | S genera fragment Windows Terminal/terminalGenerationProps; hay que elegir esquema. No secuencias a todos los /dev/pts ni temas de toda terminal. |
| 18.12 | Terminal siempre oscuro | ✅ | S lee opción terminalGenerationProps y construye esquema oscuro independientemente de ii. |
| 18.13 | Fuzzel/bloqueo coordinados | ⛔ | Sin Fuzzel ni bloqueo Hyprlock; paleta de ii no tematiza escritorio seguro Windows. |
| 18.14 | VS Code Material Code | 🔧 | material-code-set-color.sh/rutas Linux no adaptados. Detectar User/settings.json Windows y ajustar opciones de extensión instalada con backup; S. |
| 18.15 | Transparencia | ✅ | Q niveles/auto; P/D5 wallpaper desenfocado tras superficies, no promesa de Mica. |
| 18.16 | Tintado adicional | ✅ | Q Appearance mezcla colores/fondo, sin Linux. |
| 18.17 | Bordes/esquinas/blur/sombras | 🟡 | Q/P reproducen superficies de ii; no reglas/efectos sobre ventanas de apps o compositor Windows. |
| 18.18 | Tipografías por función | ✅ | Q/C + win32/fonts.cpp fuentes cargadas sólo para shell. |
| 18.19 | Escala shell/monitores | 🟡 | QT_SCALE_FACTOR y DPI Qt operativos; resolución/escala monitores quedan en ajustes Windows, no Hyprland. |
| 18.20 | Fondos de video | 🔧 | switchwall.sh mpvpaper/ffmpeg ausentes; S trabaja imágenes. QtMultimedia VideoOutput en capa Background + fotograma WIC/paleta/restauración; M. |
| 18.21 | Wallpaper contextual | 🟡 | Q políticas/heurística red y nombres; clasificación Gemini .sh ausente. No filtro fiable universal. |

## 19. Widgets de fondo y clima

Evidencia: Q ii/background/widgets/{clock,weather}/, AbstractBackgroundWidget.qml, services/Weather.qml; C/H/V/P/S, patch_ii/net/widgets; scripts/images/least_busy_region.py y ai/gemini-categorize-wallpaper.sh.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 19.1 | Reloj en wallpaper | ✅ | Q/P background, inicial activo. |
| 19.2 | Digital/Cookie | 🟡 | Ambos Q en escritorio; reloj propio en bloqueo Windows no disponible. |
| 19.3 | Digital adaptable | ✅ | Q fecha/orientación/alineación/animaciones. |
| 19.4 | Fuente variable digital | ✅ | Qt/font Q + fuentes del port; familia/tamaño/ejes configurables. |
| 19.5 | Cookie personalizable | ✅ | Q forma/cifras/manecillas/fecha. |
| 19.6 | Cookie animación/decoración | ✅ | Q formas/rotación/seno, sin compositor. |
| 19.7 | Cookie con IA | 🔧 | gemini-categorize-wallpaper.sh no ejecutable en Windows; ya hay almacén de claves DPAPI, pero falta solicitud. POST imagen/prompts con transporte IA nativo + JSON de estilo validado; M tras §13. |
| 19.8 | Frase junto al reloj | ✅ | Q/C texto configurable. |
| 19.9 | Posición libre/automática | 🟡 | Libre/arrastre Q funciona y es default Windows; leastBusy/mostBusy invocan .sh/Python ausente. Portar algoritmo de saliencia/ocupación C++ sobre WIC; M. |
| 19.10 | Reloj sólo bloqueo | ⛔ | Opción existe, pero no hay superficie ii en escritorio seguro; oculta escritorio sin crear reloj Windows. |
| 19.11 | Parallax | ✅ | Q transformaciones ligadas a paneles/escritorio V; no zoom global del escritorio. |
| 19.12 | Ocultar en fullscreen | ✅ | H detecta fullscreen y Q visibilidad; P aparta capas. PR ii-fullscreen. |
| 19.13 | Clima barra/fondo | ✅ | Q en ambos sitios, defaults apagados; S weather. |
| 19.14 | Geolocalización/ciudad | 🟡 | Ciudad/IP de wttr nativas; Qt PositionSource sólo se crea al activar GPS. Permiso/backend de ubicación real no probado, GPS default false. |
| 19.15 | Datos meteorológicos | ✅ | S JSON current/location/astronomy + Q campos; disponibilidad depende de wttr. |
| 19.16 | Unidades/frecuencia | ✅ | Q/C métrico/Fahrenheit y 10 min iniciales. |
| 19.17 | Clima online | ✅ | S WinHTTP wttr HTTPS/parche net; PR pruebas anteriores. No se verificó disponibilidad actual del proveedor. |

## 20. Brillo, comodidad, energía y rendimiento

Evidencia: HW; Q services/{Brightness,Hyprsunset,ResourceUsage,Battery,Updates,Idle}.qml, ii/onScreenDisplay/; patch_ii_sidebar/brightness; host/src/nightlight*.cpp; R/P/S/K.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 20.1 | Brillo panel interno | 🟡 | HW WMI/WmiSetBrightness y slider; K no captura teclas de brillo. Portátil compatible aún pendiente físico. |
| 20.2 | Brillo externo | ✅ | HW dxva2/DDC VCP 0x10, slider por pantalla si lectura válida. Monitor de este PC no lo expone según HW/PR. |
| 20.3 | OSD volumen/brillo/gamma | 🟡 | Q OSD escucha servicios/cambios; ajustes físicos tienen backend. K no reemplaza OSD/teclas multimedia Windows; gamma sólo si driver acepta. |
| 20.4 | Luz nocturna | 🟡 | S nightlight/rampas GDI, guard/restauración/readback SDR; HDR omitido. En este PC no disponible, botón abre ms-settings:nightlight. |
| 20.5 | Horario nocturno | 🟡 | Q horario 19:00–06:30/5000 K y test-sidebar JS; efecto sólo con gamma admitida, no controla horario del filtro Windows. |
| 20.6 | Anti-flashbang | ⛔ | Shader/eventos Hyprland sin compositor equivalente en el port; oscuro adaptativo de toda pantalla no tiene API pública equivalente simple, tile oculto. |
| 20.7 | Zoom escritorio | 🔧 | Hyprland cursor zoom/atajos ausentes. Ruta Windows Magnification API (MagSetFullscreenTransform) o abrir Lupa; M para control integrado. |
| 20.8 | Inhibición inactividad | 🟡 | P SetThreadExecutionState mantiene pantalla/sistema despiertos; no anula bloqueo por políticas ni sustituye todo hypridle. |
| 20.9 | Perfiles energía | ✅ | S/HW PowerEnumerate/GetActiveScheme/SetActiveScheme, sólo planes existentes; no crea planes ni cambia plan personalizado al consultar. |
| 20.10 | Modo juego del escritorio | 🟡 | Tile abre ms-settings:gaming-gamemode; no desactiva/restaura efectos/gaps Hyprland ni garantiza FPS. |
| 20.11 | CPU/RAM/swap | 🟡 | R /proc virtual + Q historial; swap es aproximación de commit, frecuencia CPU lscpu Linux aún ausente. |
| 20.12 | Umbrales de advertencia | ✅ | Q/C estilos/umbrales reactivos a R. |
| 20.13 | Frecuencia/historial recursos | ✅ | C/ResourceUsage Timer 3 s/60 muestras, sin ejecutable para estadísticas principales. |
| 20.14 | Datos de batería | 🟡 | HW carga/energía/tasa/tiempo/salud si WinRT informa; desconocidos conservadores y salud=1 requiere revisión de formato Q. No pruebas con batería real. |
| 20.15 | Avisos bajo/crítico | ✅ | Q Battery umbrales 20/5 y N notify-send; sólo batería presente/con datos. |
| 20.16 | Suspender al 3 % | ✅ | patch_ii_tools/build Battery.qml llama ii-shim suspend directamente al umbral/no cargando; S implementa suspensión Windows. Se revisó código; no se suspendió el PC ni se probó batería real. |
| 20.17 | Aviso carga completa | ✅ | Q/N implementado; full=101 inhibe por defecto como Linux. |
| 20.18 | Sonidos batería | ✅ | Q Audio.playSystemSound → S MessageBeep opcional; sin tema Linux completo (§9). |
| 20.19 | Comprobar actualizaciones | 🔧 | Updates usa which/checkupdates/wc sin backend. Windows Update Agent COM búsqueda de pendientes (sin instalar) y JSON al widget; M; winget upgrades sería contador separado. |
| 20.20 | Abrir actualización | ✅ | Config.apps.update=ms-settings:windowsupdate y S abre URI; no Pacman. |

## 21. Gestión de ventanas, escritorios, monitores y gestos

Evidencia: Linux upstream/dots/.config/hypr/hyprland/{keybinds,*.lua}; H/V/K/P. Windows gestiona aplicaciones: se lee su estado, se enfoca/cierra desde widgets y se opera la lista de escritorios; no se implementa un gestor de ventanas.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 21.1 | Tiling/flotantes Dwindle | ⛔ | Layout/splits pertenecen a Hyprland. H etiqueta ventanas Windows floating=true; no tilea. |
| 21.2 | Alternar flotante/tiling | ⛔ | Win+Alt+Space ausente, no layout tiling que alternar. |
| 21.3 | Enfocar por dirección | ⛔ | No dispatcher/hook direccional. Win+flechas nativo ajusta ventanas, no enfoca vecina como Hyprland; fuera de gestor del port. |
| 21.4 | Mover por dirección | ⛔ | Sin dispatcher move/hook; Win+Shift+izq/der nativo mueve monitor, distinto del layout Hyprland. |
| 21.5 | Super+ratón mover/resize | ⛔ | No hook de arrastre sobre apps ajenas; ventanas Windows conservan su marco/arrastre nativo. |
| 21.6 | Proporción del split | ⛔ | Windows/este port sin árbol de splits Dwindle. |
| 21.7 | Maximizar Super+D | 🟡 | Windows maximiza con Win+Arriba; K Win+D es mostrar escritorio/restaurar, no maximizar. |
| 21.8 | Fullscreen Super+F | ⛔ | Sin hook/dispatcher, fullscreen depende de cada app (p. ej. F11). No estado universal Hyprland equivalente. |
| 21.9 | Fullscreen spoof | ⛔ | Manipula estado cliente/compositor Hyprland inexistente; no API equivalente en esta arquitectura. |
| 21.10 | Fijar Super+P | ⛔ | Pin Hyprland/all-desktops no implementado, pinned=false; Win+P conserva Proyectar Windows, no fijación. |
| 21.11 | Cerrar Super+Q | 🟡 | H/WM_CLOSE y cierre en overview/dock funcionan; Win+Q no mapeado, Alt+F4 sigue Windows. |
| 21.12 | Forzar cierre seleccionando | 🔧 | Hook Win+Shift+Alt+Q ausente; overlay selecciona HWND/PID y acción explícita TerminateProcess con confirmación; M, procesos propios del usuario. |
| 21.13 | Elegir escritorio Super+1…0 | 🔧 | V sabe cambiar escritorio, K no mapea dígitos (Windows abre apps fijadas). Añadir eventos a V, conservar alternativa Windows/configurable; S. |
| 21.14 | Enviar ventana sin seguirla | ⛔ | Dispatcher ignorado; IVirtualDesktopManager público no mueve ventanas ajenas. Delegar a Vista de tareas. |
| 21.15 | Escritorios adyacentes | 🟡 | V/barra y Win+Ctrl+izq/der Windows funcionan; combos PageUp/Down/rueda Linux no todos mapeados. |
| 21.16 | Navegar ocupados | 🔧 | H tiene lista/escritorio de ventanas pero navegación relativa e/m no filtra ocupación Windows. Filtrar windowList, elegir anterior/siguiente no vacío y llamar V; S. |
| 21.17 | Grupos de diez | ⛔ | No grupo Hyprland; escritorios globales Windows con cantidad real. |
| 21.18 | Scratchpad | ⛔ | No espacio especial ni park/unpark de apps; Super+S abre búsqueda Windows. Fuera de gestor de ventanas. |
| 21.19 | Varios monitores | 🟡 | P/H/Q enumeran/muestran paneles por pantalla; escritorios compartidos entre monitores Windows, sin grupos/reglas Hyprland. DPI/hardware múltiple pendiente. |
| 21.20 | Configurar resolución/posición/escala | 🟡 | Qt lee datos reales; edición se delega a ms-settings:display, no aplica monitor=... de Hyprland. |
| 21.21 | Gestos touchpad | ⛔ | Gestos Hyprland no registrados; Windows Precision Touchpad conserva sus propios gestos y ajustes, no los del inventario. |
| 21.22 | Scroll natural/entrada | ⛔ | Configuración libinput/Hyprland no aplica a Windows; se configura en Windows/controlador. |
| 21.23 | Snapping Hyprland | ⛔ | Reglas snapping compositor no portadas; Snap de Windows queda disponible con comportamiento propio. |
| 21.24 | Animaciones de ventanas/escritorios | 🟡 | Animaciones Q de paneles/widgets sí; apps, desktops y zoom global los anima Windows, sin curvas Hyprland. |
| 21.25 | Reglas por aplicación | ⛔ | Archivos Hyprland no los consume Windows; H sólo compatibilidad de lectura y operaciones concretas. |
| 21.26 | Modo VM Super+Alt+F1 | 🔧 | Submap Linux ausente. Flag de pausa del hook K con toggle, estado visible y pánico independiente; S. No promete interceptar atajos protegidos Windows. |

## 22. Bloqueo, sesión y autenticación

Evidencia: Q common/panels/lock/{LockScreen,LockContext}.qml, ii/lock/, ii/sessionScreen/, services/{SessionWarnings,KeyringStorage}.qml; overlay common/functions/Session.qml; P/S/K; shim/qml/Quickshell/Services/{Pam,Polkit}/.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 22.1 | Pantalla Quickshell/PAM | ⛔ | P WlSessionLock usa LockWorkStation, no dibuja superficie segura propia; PAM placeholder. Autenticación Windows. |
| 22.2 | Hyprlock fallback | ⛔ | Wayland/Hyprland inexistentes; useHyprlock no es opción operativa Windows. |
| 22.3 | Fondo/reloj de bloqueo | ⛔ | Q de lock no sustituye escritorio seguro Windows; no se acredita tematización del bloqueo Windows por el fondo de ii. |
| 22.4 | Contraseña visual Material | ⛔ | Control Q no autentica Windows ni aparece como lock real; credenciales Windows quedan en su interfaz. |
| 22.5 | Desbloquear keyring al autenticar | ⛔ | PAM/secret service Linux no aplican. Credenciales Windows se desbloquean con sesión, no recogiendo contraseña en ii. |
| 22.6 | Bloquear al iniciar | 🔧 | LockScreen depende de Persistent.isNewHyprlandInstance; firma Hyprland vacía en Windows no detecta nuevo inicio. Evento de arranque host/Q y LockWorkStation opcional; S. |
| 22.7 | Contraseña para energía desde lock | ⛔ | No formulario propio/autenticación PAM en escritorio seguro. Políticas de energía/credenciales de Windows. |
| 22.8 | Inactividad 5/10/15 min | 🔧 | hypridle no existe. Abrir ajustes bloqueo/energía o servicio GetLastInputInfo + avisos y LockWorkStation/SetSuspendState, respetando inhibidor/políticas; M. |
| 22.9 | Bloquear antes de suspender | 🔧 | Session.suspend sólo SetSuspendState, sin LockWorkStation previo. Enlazar ambos por opción y restauración adecuada; S. |
| 22.10 | Foco del bloqueo al despertar | ⛔ | Windows maneja foco del escritorio seguro; lockFocus/dispatch Hyprland no aplican. |
| 22.11 | Menú Ctrl+Alt+Delete | 🟡 | Menú Q y navegación sí; Windows protege esa secuencia. K lo mueve a Ctrl+Alt+End (conflicto posible en escritorio remoto). |
| 22.12 | Bloquear/suspender/logout/hibernar/apagar/reiniciar | ✅ | Overlay Session usa LockWorkStation/SetSuspendState/shutdown.exe. Hibernación requiere soporte. No se ejecutaron acciones durante esta auditoría. |
| 22.13 | Reiniciar a firmware | 🟡 | shutdown /r /fw implementado; requiere UEFI/permisos, puede fallar sin elevación. Sin flujo de elevación/error integrado. |
| 22.14 | Administrador de tareas | ✅ | Session.launchTaskManager → taskmgr; Ctrl+Shift+Esc nativo Windows no interceptado. |
| 22.15 | Avisos antes de salir | 🔧 | SessionWarnings bash/pidof múltiples/var/lib/pacman/grep no operativos. Heurística Windows .crdownload/.part y estado de actualizador propio, con aviso sin bloquear cierre; S. |
| 22.16 | Polkit | ⛔ | UAC reemplaza autorización de sistema; no se replica ni intercepta escritorio seguro. |
| 22.17 | Keyring secretos API | ✅ | KeyringStorage llama secret-tool store/lookup directo; secrettool.cpp cifra con DPAPI por usuario/PC y guarda bajo LocalAppData. clear también emulado; independiente de lock/PAM y sin transporte de chat (§13.8). |
| 22.18 | Multimedia durante bloqueo | 🟡 | Teclas hardware Windows pueden controlar audio según sistema; hook ii no opera en escritorio seguro, no equivalen bind flags Hyprland. |

## 23. Teclado virtual y ayudas

Evidencia: Q ii/onScreenKeyboard/{OnScreenKeyboard,OskKey,OskContent}.qml, layouts.js, services/Ydotool.qml, ii/cheatsheet/; host/src/ydotool.cpp, shim/CMake/deploy; panel_window.cpp/native.cpp mantienen panel sin foco por defecto; overlay HyprlandKeybinds/K/A; Linux launch_first_available.sh.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 23.1 | Teclado Super+K | ✅ | K oskToggle abre teclado Q; Ydotool llama alias nativo con SendInput, panel no toma foco por defecto. Escribe teclas comunes en apps normales; no escritorio seguro/apps de mayor privilegio. Tile sidebar abre accesibilidad Windows. |
| 23.2 | Teclas principales/F1–F12 | ✅ | ydotool scanOf cubre códigos 1–83 y F11/F12 (87/88), números/letras/función. Windows aplica su layout activo; etiquetas Q deben corresponder al idioma elegido. |
| 23.3 | Shift/Caps | ✅ | OskKey/Ydotool controlan Shift temporal/fijo y liberación; scanOf mapea Shift/Caps y SendInput los envía. Estado de mayúsculas visual no es sincronización automática con teclado físico. |
| 23.4 | Inyección ydotool | 🟡 | Alias ydotool key/type con SendInput Unicode/scan codes, releases y teclas comunes/extendidas. Códigos no mapeados se omiten (p. ej. Menu 139 de layouts.js); sin resultado SendInput ni elevación/UIAccess. Completar mapa/errores; S. |
| 23.5 | Fijar teclado | ✅ | Q pinned/C y exclusiveZone/AppBar reservan espacio opcional; cerrar llama releaseAllKeys. Sin dependencia de daemon ydotool Linux. |
| 23.6 | Layouts extensibles | 🟡 | layouts.js extensible y scan codes Windows operativos; dibujo Q no cambia HKL del sistema ni cubre todos los códigos Linux. Sincronizar layout/mapa antes de prometer cualquier idioma; M. |
| 23.7 | Chuleta Super+/ | ✅ | K VK_OEM_2/cheatsheetToggle, overlay HyprlandKeybinds estático Windows; no hyprctl binds. |
| 23.8 | Estilo de chuleta | ✅ | Q símbolos/fuentes/separación; teclas OEM según layout físico. |
| 23.9 | Tabla periódica | ✅ | Datos/pestaña Q pura; sin API del sistema. |
| 23.10 | Accesos rápidos apps | 🟡 | Apps por launcher A, Explorer/TaskMgr nativos; faltan hooks Linux terminal/browser/code/text/office. Lista en apéndice. |
| 23.11 | Alternativas primera instalada | 🔧 | launch_first_available.sh no funciona. Resolver ejecutables/AppUserModelIDs con SearchPath/AppsFolder y lanzar primera opción configurada; S. |

## 24. Funciones específicas de Waffle

Evidencia: Q panelFamilies/WaffleFamily.qml y modules/waffle/{bar,startMenu,taskView,actionCenter,notificationCenter}/; services/{LauncherApps,TaskbarApps}.qml; A/H/V/P/N/M/HW/T. Sin validación completa de esta familia; sus QML simples se deducen por código.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 24.1 | Barra estilo Windows | ✅ | Q WaffleBar/Looks, posición/alineación; P AppBar. |
| 24.2 | Inicio fijadas/todas | ✅ | Q StartPageApps/AllAppsGrid y A; IDs fijados Windows parcheados. |
| 24.3 | Categorías apps | 🔧 | A winapps no llena categorías .desktop; Q bloques quedan sin clasificación útil. Catálogo/heurística por AUMID configurable, fallback Todas; M. |
| 24.4 | Fijar/quitar Inicio | ✅ | LauncherApps/Q cambia Config.launcher.pinnedApps. |
| 24.5 | Reordenar fijadas | ✅ | Q StartAppButton/LauncherApps, cambios de lista C. |
| 24.6 | Buscar desde Inicio | 🟡 | Q LauncherSearch/A operativo para apps/web/matemática e historial Windows; emojis tienen fallo CRLF y ciertas acciones siguen pendientes (§4/5). |
| 24.7 | Cuenta usuario | 🟡 | manageUser a ms-settings:yourinfo y logout Windows; avatar usa rutas AccountsService/.face Linux, no foto de cuenta Windows. |
| 24.8 | Energía desde Inicio | ✅ | Q menú llama overlay Session con APIs/comandos Windows. |
| 24.9 | Contextual botón Inicio | 🟡 | Terminal/taskmgr/ajustes por S; búsqueda llama IPC overview que depende de la familia/carga. Verificar acciones de archivos y búsqueda en Waffle. |
| 24.10 | Apps fijadas en barra | ✅ | TaskbarApps/C separado de LauncherApps. |
| 24.11 | Agrupar ventanas | ✅ | TaskbarApps/H por appId, mismo índice A. |
| 24.12 | Previews de ventanas | 🟡 | Q/P DWM para no minimizadas; sin imagen viva de minimizadas, sin pruebas completas Waffle. |
| 24.13 | Cerrar ventana/grupo | ✅ | Q TaskAppButton/Toplevels.close → WM_CLOSE. |
| 24.14 | Task View/desktops/nuevo | 🟡 | Q/H/V enfocan y crean mediante focus a índice nuevo; arrastre sigue llamando move ignorado. No todos los ajustes/pulido de ii se aplican a esta vista. |
| 24.15 | Fijar en todos los escritorios | ⛔ | TaskViewWindow llama hl.dsp.window.pin ignorado; pinned=false. Sin API pública de pin equivalente adoptada. |
| 24.16 | Centro acciones | 🟡 | Q y servicios M/NET/HW; conserva controles Linux y carece del filtrado exhaustivo del sidebar ii. |
| 24.17 | Centro notificaciones | ✅ | Q/N grupos/limpieza/calendario; mismos límites de toasts §11. |
| 24.18 | Pie concentración | ✅ | FocusFooter/TimerService Q, datos comunes. |
| 24.19 | Bandeja overflow | 🟡 | Q/T listas/iconos sí; TrayButton usa QsMenuAnchor con item.menu, mientras T abre menús nativos por secondaryActivate. Adaptación exacta no acreditada en esta familia. |
| 24.20 | Estado red/volumen/batería | ✅ | Q botón combinado consume NET/M/HW; oculta/indica ausencia según hardware. |
| 24.21 | OSD/lock/Polkit/recortes propios | 🟡 | OSD Q y captura S; lock/Polkit no aplican; cuentagotas WScreenSnip aún sleep/hyprpicker. No dar paquete completo por operativo. |
| 24.22 | Fluent/acrílico | 🟡 | Q Looks dibuja colores/transparencia/sombras/iconos; P no reproduce necesariamente acrílico DWM de toda superficie. Sin comparación visual Waffle. |
| 24.23 | Fallbacks ii | 🟡 | Chuleta/overlay/wallpaper y teclado QML/ydotool cargados; traductor sin backend, emojis con fallo de carga descrito en §5. |
| 24.24 | Ausencia SidebarLeft | ⛔ | WaffleFamily no carga SidebarLeft; botón Widgets cambia estado sin cargar chat/traductor/galería de ii. No incluidos aquí. |

## 25. Ajustes, terminal, instalación y mantenimiento

Evidencia: Q settings.qml, welcome.qml, modules/settings/, services/{Translation,FirstRunExperience,ConflictKiller}.qml; tools/dev/stage-ii.ps1, tools/port/patch_ii*.py, tools/package/{install,uninstall,make-package}.ps1; host main/common; PR D18/test-install.

| ID | Punto del inventario Linux | Estado | Qué funciona, límite o implementación pendiente |
| --- | --- | --- | --- |
| 25.1 | GUI ajustes Super+I | 🟡 | Q páginas Quick/General/Bar/Background/Interface/Services/Advanced/About existen; engranaje las abre. Win+I es ajustes Windows, opciones Linux aún presentes. |
| 25.2 | Archivo configuración | ✅ | C Directories.shellConfigPath usa StandardPaths Windows; botón abre archivo con Qt/S. No asumir ~/.config Linux. |
| 25.3 | Cambios observados | ✅ | Config FileView/watchChanges y bindings Q; core FileView vigila directorios inexistentes tras corrección PR. |
| 25.4 | Opciones fuera GUI | 🟡 | JSON/QML del port sí; hypr/custom/*.lua no los ejecuta Windows. |
| 25.5 | Idioma automático/manual | 🟡 | Q Translation carga JSON y parche es_CO→es_MX; selector de idiomas usa find/basename ausentes, puede ofrecer sólo inglés. Listar recursos Qt/FolderListModel; S. |
| 25.6 | Bienvenida | ✅ | patch_ii_tools/build FirstRunExperience abre qs -p welcome.qml directo y escribe marker con FileView; welcome usa título/arrastre propios. Fondo/config Q y switchwall nativos; no se lanzó ventana. |
| 25.7 | Reabrir/reset bienvenida | 🟡 | FirstRunExperience reset/marker ahora cmd del y FileView, apertura qs directa. Win+Shift+Alt+/ aún no está en K; añadir hook opcional si se desea reapertura global, S. |
| 25.8 | Información sistema/ayuda | 🟡 | About/links Q + R/system-info Windows; datos Linux/whoami/formato y enlaces de soporte upstream pueden no describir el port. |
| 25.9 | Kitty/configs auxiliares | ⛔ | Kitty/rutas de instalación Linux no entregan terminal Windows funcional; se usa Windows Terminal, otras configs no se instalan automáticamente. |
| 25.10 | Fish | ⛔ | Configuración Linux/Fish no aplicada a PowerShell; WSL sería entorno adicional fuera de alcance. |
| 25.11 | Starship | 🔧 | No instalación/configuración Windows en paquete. Opción instalador que detecte starship y añada init powershell al perfil con backup; S. |
| 25.12 | Eza | 🔧 | No integración Windows. Detectar eza.exe/opción y alias PowerShell con backup de perfil, no reemplazar Get-ChildItem silenciosamente; S. |
| 25.13 | GTK/Qt/KDE/portales | ⛔ | Portal Wayland/ajustes GTK/KDE Linux no aplican; Qt/diálogos Shell Windows cubren las necesidades del port. |
| 25.14 | Instalación transparente | ✅ | install.cmd/ps1 por usuario con preguntas/manifest/backups; README documenta desarrollo. PR test-install 15/15 anterior. |
| 25.15 | Modo --core | ⛔ | Modo del instalador Linux para Hyprland; no contrato --core del instalador Windows. |
| 25.16 | Backups instalación | ✅ | install.ps1 exporta valores/manifest; host guarda temas/banners/cursor/gamma y rescate. No backup general del equipo. |
| 25.17 | Actualizar/reinstalar | 🟡 | Flujo stage/package/install Windows, preservación de config; no setup install/merge Linux ni actualizador Windows automático. |
| 25.18 | Desinstalar | ✅ | uninstall.ps1/manifest/entrada Apps/rescate; PR D18/test-install. |
| 25.19 | Diagnóstico dependencias | 🔧 | diagnose/dependency check Linux no portados. ii-shim doctor --json: versiones/rutas/alias/servicios/dispositivos/permisos, sin mutaciones; S. |
| 25.20 | Monitor virtual virtmon | ⛔ | Comando de compositor Linux, no monitor virtual Windows. Requeriría controlador Indirect Display Driver/proyecto separado. |
| 25.21 | IPC/shortcuts globales | 🟡 | Quickshell IPC + H sink/K disponibles; sólo subset de atajos/dispatchers Windows, no todos los Linux. |
| 25.22 | Control de conflictos | ⛔ | ConflictKiller busca daemons D-Bus/Linux; no debe matar procesos Windows equivalentes. Host maneja reversiblemente Explorer/banners/bandeja por otra ruta. |
| 25.23 | Fallbacks Fuzzel/Hyprlock/Wlogout/Hyprshot | 🟡 | Ausentes; ii-rescue/pánico/guardián recuperan Windows y sus herramientas nativas. Sin menús alternativos Linux distribuidos. |
| 25.24 | Compatibilidad versiones | 🟡 | Port/parches exactos sobre árbol fijado; sintaxis hl.dsp parcialmente soportada H, no Hyprland 0.55 ejecutándose. Cambios upstream pueden requerir adaptar parches. |

## Apéndice A. Estado inicial y dependencias

29 filas, en el mismo orden de la tabla Linux. Se contrastan con Config/Persistent y parches del staging, no con las preferencias personales ya guardadas del usuario.

| ID | Punto de la fuente | Estado | Resultado en Windows y evidencia |
| --- | --- | --- | --- |
| A1 | Familia visual | 🟡 | ii sigue por defecto; Waffle cargable con límites §24 y sin Ctrl+Win+P. C/shell.qml. |
| A2 | Barra y overview | 🟡 | Barra arriba; overview Windows 1×1, escala 0.55 + tira real de escritorios, no Linux 2×5. patch_ii/V. |
| A3 | Dock | ✅ | Windows lo activa por defecto, con Explorador/Terminal; Linux lo apagaba. patch_ii/C. |
| A4 | Reloj de fondo | ✅ | Activo, posición libre arriba derecha; C/Q background. |
| A5 | Clima barra/fondo | ✅ | Apagado; S weather requiere red/ubicación. GPS Windows apagado inicial, ciudad/IP disponible. |
| A6 | Transparencia general | ✅ | Apagada; Q/P permiten activar niveles. |
| A7 | Autoocultado barra | ✅ | Apagado, opción Q/P operativa. |
| A8 | Traductor lateral | 🔧 | Apagado; trans sin backend. ii-shim translate HTTP nativo; M (§14). |
| A9 | IA | 🟡 | Permitida en C; almacenamiento DPAPI implementado, transporte bash/curl todavía no operativo. No lista para conversar. |
| A10 | Traducción de pantalla | 🔧 | Credenciales/APIs Cloud necesarias además del port OAuth/HTTP que falta; L (§14). |
| A11 | Luz nocturna automática | 🟡 | C 19:00–06:30/5000 K; gamma SDR sólo si driver/guard admiten, fallback ajustes Windows. |
| A12 | Anti-flashbang | ⛔ | Apagado/oculto; shader compositor Hyprland, §20. |
| A13 | Protección volumen | ✅ | Apagada, Audio/M implementan límite opcional. |
| A14 | Sonidos batería/Pomodoro | ✅ | Apagados; S system-sound/MessageBeep al activarlos. |
| A15 | Bloquear al iniciar | 🔧 | Apagado; detección de instancia Hyprland no identifica inicio Windows. Evento host + LockWorkStation; S (§22). |
| A16 | Contraseña energía desde bloqueo | ⛔ | Apagado; PAM/lock propio no reemplazan escritorio seguro. |
| A17 | Suspensión por batería 3 % | ✅ | C activada; patch_ii_tools/build ya llama ii-shim suspend al umbral/no cargando. Implementado, sin prueba de suspensión/batería física. |
| A18 | Aviso batería llena | ✅ | Presente, umbral 101 impide disparo usual; Q/N. |
| A19 | Filtro laboral wallpaper/clipboard | 🟡 | Apagado; historial de imágenes Windows sí, heurística Q/NET presente; clasificación IA no operativa ni filtro universal. |
| A20 | Mosaicos iniciales | 🟡 | Red/Bluetooth/inhibidor/micro/audio/nightlight; hardware y gamma condicionan resultados. |
| A21 | WARP | 🔧 | Cliente externo no preparado; detectar cliente Windows/wrapper JSON e integrar tile; M. |
| A22 | EasyEffects | ⛔ | No Linux/PipeWire/Flatpak en runtime Windows. |
| A23 | FPS limiter | ⛔ | MangoHud no distribuido ni aplicable; retirado del overlay. |
| A24 | Fondos de video | 🔧 | mpvpaper/ffmpeg del script no operan; QtMultimedia Background + paleta/restauración; M. |
| A25 | Brillo externo | ✅ | HW DDC/CI/dxva2 nativo sustituye ddcutil; monitor compatible requerido, este PC no lo expone. |
| A26 | Teclado virtual/superpaste | 🟡 | Alias ydotool/cliphist y Q conectados; teclas comunes escriben. Superpaste tiene límites de foco/entrega; códigos especiales/layout requieren revisión (§§5/23). |
| A27 | VS Code coloreado | 🔧 | Requiere extensión Material Code y adaptar ruta/script Windows, backup settings; S. |
| A28 | Actualizaciones | 🔧 | checkupdates ausente; Windows Update Agent COM contador, sin instalar; M. Abrir Windows Update sí funciona. |
| A29 | Hibernación/firmware | 🟡 | shutdown /h y /r /fw implementados; soporte/permisos requeridos, firmware sin elevación/error integrado. |

## Apéndice B. Atajos principales

50 filas, una por fila de la tabla Linux, incluidas combinaciones agrupadas. Super = tecla Windows. Se contrasta la entrega con host/src/keyboard.cpp y, cuando sí se entrega, la acción QML/S. **K sólo intercepta mientras existe el sink de la shell y la app enfocada no está en fullscreen**; los atajos Windows restantes siguen al sistema. El pánico Ctrl+Alt+Shift+R se registra aparte en host/src/main.cpp.

Un atajo que abre una UI sin backend se marca parcial o pendiente. Los símbolos / y . se mapean por VK_OEM_2/VK_OEM_PERIOD; la equivalencia de carácter depende del teclado. También existen en K Win+B/Win+O para el panel izquierdo, Win+Alt+A para separarlo y Win+Alt+R para selección de grabación; no figuraban en la tabla principal de entrada. Win+Ctrl+D/izq/der/F4 nativos siguen disponibles para escritorios. La chuleta incluye algunos atajos con acciones incompletas y debe ajustarse junto al hook.

| ID | Punto de la fuente | Estado | Resultado en Windows y evidencia |
| --- | --- | --- | --- |
| B1 | Super | ✅ | K Win down/up → searchToggleRelease/Interrupt; abre búsqueda ii. Sin sink abre Inicio Windows. |
| B2 | Super+Tab | ✅ | K overviewWorkspacesToggle; ventanas/escritorios reales V. |
| B3 | Super+Enter | 🔧 | No en K; mapear apertura de terminal configurada (wt/alternativa); S. |
| B4 | Super+E | ✅ | No interceptado: Explorer nativo Windows, equivalente archivos. |
| B5 | Super+W | 🔧 | No en K; abrir navegador predeterminado mediante URI ShellExecute; S. |
| B6 | Super+C | 🔧 | No en K; resolver editor configurado y abrir con argumentos; S. |
| B7 | Super+X | 🔧 | No en K; Windows conserva combinación, no editor ii. Mapear editor opcional; S. |
| B8 | Super+I | 🟡 | No en K: ajustes Windows. Engranaje abre ii; añadir atajo de ii configurable o mapear; S. |
| B9 | Ctrl+Shift+Esc | ✅ | Pasa a Task Manager nativo; menú ii también lanza taskmgr. |
| B10 | Super+A | ✅ | K sidebarLeftToggle, ii abre panel; chat/traducción con límites §§13/14. |
| B11 | Super+N | ✅ | K sidebarRightToggle; centro/panel según familia. |
| B12 | Super+V | ✅ | K overviewClipboardToggle → Cliphist Windows; refresca al abrir. Requiere habilitar historial del portapapeles Windows. |
| B13 | Super+. | 🟡 | K VK_OEM_PERIOD abre modo emoji y recurso ya empaquetado; parser local CRLF impide cargar datos (5.9). |
| B14 | Super+/ | ✅ | K VK_OEM_2 → cheatsheetToggle; depende de tecla física/layout, no traducción de carácter universal. |
| B15 | Super+K | ✅ | K oskToggle → teclado Q/ydotool SendInput para teclas comunes en apps normales. Tile sidebar abre ajustes del teclado Windows; límites §23. |
| B16 | Super+M | ✅ | K mediaControlsToggle; M/GSMTC. |
| B17 | Super+G | ✅ | K overlayToggle; video recorder/FPS con límites. |
| B18 | Super+J | ✅ | K barToggle ambas barras. |
| B19 | Ctrl+Super+P | 🔧 | No en K; Q panelFamilyCycle existe. Añadir fila al hook; S (Waffle conserva límites). |
| B20 | Ctrl+Super+R | ✅ | K @restartShell → main.cpp stopShell/startShell. Recarga mediante nuevo proceso de ii; conserva archivos de preferencias, puede perder estado sólo en memoria. |
| B21 | Ctrl+Super+T | ✅ | K wallpaperSelectorToggle/Q/S. |
| B22 | Ctrl+Super+Alt+T | ✅ | K wallpaperSelectorRandom/Q/S. |
| B23 | Ctrl+Super+Shift+D | ✅ | K toggleLightDark/S switchwall. |
| B24 | Print | 🟡 | No en K; captura/Recortes según ajustes Windows. Botón de captura entera ii sí llama S; no mismo atajo ii. |
| B25 | Ctrl+Print | 🔧 | No en K; enlazar capture/copy/save fechado en S + IPC; S. |
| B26 | Super+Shift+S | ✅ | K regionScreenshot → selector propio ii/S; no necesariamente UI Recortes Windows. |
| B27 | Super+Shift+A | 🔧 | K regionSearch sí, S crop search no portado; upload HTTP + abrir Lens; M. |
| B28 | Super+Shift+X | ✅ | K regionOcr → Windows.Media.Ocr; idioma OCR instalado requerido. |
| B29 | Super+Shift+T | 🔧 | K screenTranslate sí, GoogleCloud backend Linux; OAuth/Vision/Translation nativos; L. |
| B30 | Super+Shift+C | 🔧 | No K/hyprpicker; cuentagotas GDI/WIC + clipboard + hook; M. |
| B31 | Super+Shift+R | 🔧 | K regionRecord sí, crop record sin implementación; WGC/encoder/estado; L. |
| B32 | Ctrl+Alt+R | 🔧 | No K/record.sh; grabador monitor nativo + hook; L. |
| B33 | Super+Shift+Alt+R | 🔧 | No K/record.sh; grabador + loopback audio; L. |
| B34 | Super+Shift+P | 🔧 | No K; evento dirigido M playPause/IPC mpris; S. |
| B35 | Super+Shift+N / B | 🔧 | Ninguno en K; mpris next/previous dirigidos; S. Una fila como en fuente. |
| B36 | Super+Shift+M | 🔧 | No K; Windows conserva combinación. Evento Audio mute/wpctl o Core Audio; S configurable. |
| B37 | Super+Alt+M | 🔧 | No K; evento mute de entrada/Core Audio; S. |
| B38 | Super+Q | 🔧 | No K; enviar WM_CLOSE a ventana activa por evento host, no TerminateProcess; S. |
| B39 | Super+D / F | 🟡 | D → @showDesktop (minimiza/restaura), distinto de maximizar; F sin hook/fullscreen universal. Win+Arriba/app fullscreen Windows. |
| B40 | Super+Alt+Space | ⛔ | Sin tiling que alternar; no en K. |
| B41 | Super+P | ⛔ | Proyectar Windows se conserva; pin/all-desktops de Hyprland sin implementación pública adoptada. |
| B42 | Super+flechas | ⛔ | No foco direccional ii; Snap Windows sigue disponible con función distinta. |
| B43 | Super+Shift+flechas | ⛔ | Sin mover en layout Hyprland; izquierda/derecha de Windows cambian monitor, no equivalen. |
| B44 | Super+1…0 | 🔧 | No K: apps fijadas Windows. Conectar V a dígitos opcional/configurable; S; sin grupos de diez. |
| B45 | Super+Alt+1…0 | ⛔ | Sin API pública adoptada para mover ventanas ajenas de escritorio. |
| B46 | Super+S | ⛔ | Sin scratchpad; búsqueda Windows conserva la combinación. |
| B47 | Super+Alt+S | ⛔ | Sin escritorio especial ni despacho de envío. |
| B48 | Ctrl+Alt+Delete | ⛔ | Secuencia segura no llega al hook. Menú ii: Ctrl+Alt+End; en escritorio remoto puede tener conflicto. |
| B49 | Super+Alt+F1 | 🔧 | No K; pausa del hook con toggle/indicador/pánico independiente; S. |
| B50 | Super+- / = | 🔧 | No K/zoom Hyprland; Magnification API/Lupa Windows; M. |

## Apéndice C. Funciones que no deben darse por incluidas

Se revisan las 11 advertencias funcionales finales de la fuente. Aquí ✅ significa que el port respeta o permite confirmar el límite descrito, no que añada esa función. Las otras marcas indican diferencia, ausencia o dato no verificado. Se contabilizan separadamente para no confundir advertencias con prestaciones.

| ID | Punto de la fuente | Estado | Resultado en Windows y evidencia |
| --- | --- | --- | --- |
| C1 | Variantes AGS/EWW/forks | ⛔ | No son el ii Quickshell portado. No se incorporan como funciones Windows de este árbol. |
| C2 | Aplicación citada ≠ instalada | ✅ | A enumera apps reales; instalador no instala todo navegador/editor del inventario. Defaults pueden mostrar fallback si faltan. |
| C3 | Calendario/tareas locales | ✅ | Q calendario/Todo sólo local/FileView; sin Google Calendar/Todoist nativos. |
| C4 | Media no es reproductor/letras | ✅ | M controla sesiones GSMTC; no reproduce archivos por sí mismo ni acredita letras sincronizadas. |
| C5 | Modo juego no garantiza FPS | ✅ | Tile Windows abre ajustes; no cambia kernel/driver ni mide aumento de FPS. |
| C6 | FPS no es límite global | ⛔ | MangoHud queda fuera y no hay limitador global de juegos Windows implementado. |
| C7 | Traducción captura ≠ video continuo | 🟡 | Q trabaja imagen fija/S; además Cloud no portado. No traducción continua de video. |
| C8 | OCR local y Cloud son rutas distintas | ✅ | Local Windows.Media.Ocr/S operativo; Vision/Translation Cloud siguen incompletos. No Tesseract instalado por el port. |
| C9 | Fingerprint no preparado | ✅ | ii no configura Windows Hello; PAM/Hyprlock no aplican. Autenticación de Windows conserva su configuración. |
| C10 | Instalador no prepara sistema base | ✅ | No instala controladores, WSL/zram ni prepara hibernación; instala interfaz/runtime por usuario. |
| C11 | Disponibilidad/precio proveedores | ❓ | No se consultó red ni cuentas. Endpoints en Q no prueban acceso permanente ni gratuidad. |

## Resumen por sección

Conteos por **filas del inventario**, no por implementaciones independientes. Una misma función puede aparecer en barra, panel, acción y atajo: todas sus apariciones se revisan y se cuentan, sin afirmar que sean mejoras distintas.

| Sección | ✅ | 🟡 | 🔧 | ⛔ | ❓ | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |

| 1. Interfaces y estructura del escritorio | 5 | 3 | 0 | 0 | 0 | 8 |
| 2. Barra principal de Illogical Impulse | 16 | 3 | 1 | 0 | 0 | 20 |
| 3. Overview y organización visual de ventanas | 6 | 3 | 0 | 3 | 0 | 12 |
| 4. Lanzador y búsqueda | 17 | 5 | 1 | 1 | 0 | 24 |
| 5. Portapapeles y emojis | 6 | 5 | 1 | 0 | 0 | 12 |
| 6. Dock opcional | 10 | 1 | 0 | 0 | 0 | 11 |
| 7. Ajustes rápidos y panel derecho | 13 | 3 | 0 | 0 | 0 | 16 |
| 8. Redes y Bluetooth | 10 | 4 | 2 | 0 | 0 | 16 |
| 9. Audio y micrófono | 3 | 6 | 1 | 2 | 0 | 12 |
| 10. Multimedia y reconocimiento de canciones | 6 | 6 | 2 | 0 | 0 | 14 |
| 11. Notificaciones | 10 | 3 | 0 | 1 | 0 | 14 |
| 12. Calendario, tareas y concentración | 18 | 0 | 0 | 0 | 0 | 18 |
| 13. Panel izquierdo e inteligencia artificial | 6 | 13 | 6 | 0 | 0 | 25 |
| 14. Traducción | 2 | 5 | 7 | 0 | 0 | 14 |
| 15. Galería de ilustraciones y fondos online | 10 | 1 | 1 | 0 | 1 | 13 |
| 16. Capturas, OCR, búsqueda visual y grabación | 6 | 5 | 11 | 1 | 0 | 23 |
| 17. Overlay de widgets | 11 | 2 | 0 | 1 | 0 | 14 |
| 18. Wallpapers, Material You y estética | 13 | 4 | 2 | 2 | 0 | 21 |
| 19. Widgets de fondo y clima | 12 | 3 | 1 | 1 | 0 | 17 |
| 20. Brillo, comodidad, energía y rendimiento | 9 | 8 | 2 | 1 | 0 | 20 |
| 21. Gestión de ventanas, escritorios, monitores y gestos | 0 | 6 | 4 | 16 | 0 | 26 |
| 22. Bloqueo, sesión y autenticación | 3 | 3 | 4 | 8 | 0 | 18 |
| 23. Teclado virtual y ayudas | 7 | 3 | 1 | 0 | 0 | 11 |
| 24. Funciones específicas de Waffle | 11 | 10 | 1 | 2 | 0 | 24 |
| 25. Ajustes, terminal, instalación y mantenimiento | 6 | 9 | 3 | 6 | 0 | 24 |
| **Subtotal 25 secciones** | **216** | **114** | **51** | **45** | **1** | **427** |
| A. Defaults/dependencias | 10 | 8 | 7 | 4 | 0 | 29 |
| B. Atajos | 18 | 4 | 20 | 8 | 0 | 50 |
| C. Advertencias funcionales | 7 | 1 | 0 | 2 | 1 | 11 |
| **Total de filas auditadas** | **251** | **127** | **78** | **59** | **2** | **517** |

No se cuentan otra vez las filas de evidencia, comandos, prioridades o resumen. Los conteos no son una medida de calidad ni de cobertura de pruebas físicas.

## Para la versión 1.0

Prioridad propuesta por utilidad cotidiana y esfuerzo S/M. Son mejoras 🔧 presentes en las tablas; se agrupan dependencias para evitar una lista repetida. Las mejoras de atajos proceden del apéndice B aunque su función por clic ya esté implementada.

1. **Corregir carga de emojis — S.** Normalizar CRLF en Emojis.qml y reparar entries/list en búsqueda permisiva; recurso ya empaquetado, sin ejecutar Fuzzel (4.12/5.9).
2. **Completar atajos de ii — S.** Enganchar settings de ii, cambio de familia, apps y media/mutes; alternativas configurables para combinaciones Windows. Recarga ya implementada (apéndice B).
3. **Cuentagotas de pantalla — M.** Leer píxel GDI/WIC, mostrar muestra y copiar #RRGGBB; integrar acción y hook (16.14/apéndice B).
4. **Traductor de texto nativo — M.** Proveedor HTTP configurable y catálogo de idiomas; retirar dependencia trans (14.1).
5. **Accesos de aplicaciones con alternativas — S.** Resolver terminal/editor/navegador instalados con SearchPath/AppsFolder y abrir primera opción (23.11/atajos).
6. **Diagnóstico de sólo lectura — S.** ii-shim doctor --json para rutas/alias/servicios/hardware/permisos, sin modificar sistema (25.19).
7. **Descarga de ilustraciones — S.** BooruImage → ii-shim fetch --out y aviso tras éxito, sin mkdir/curl bajo bash (15.8).
8. **Indicador de micrófono activo — M.** Conectar sesiones Core Audio de captura activas a Privacy; indicar grabación propia, sin prometer detección universal de terceros (9.11).
9. **Indicador de distribución del teclado — M.** GetKeyboardLayout del hilo enfocado + nombre/idioma Windows, sin hyprctl/xkb Linux (2.10).
10. **Contador de actualizaciones Windows — M.** Windows Update Agent COM consulta de pendientes y JSON para widget; sin instalar automáticamente (20.19).
11. **Ollama local sin scripts Linux — M.** Enumerar /api/tags y pedir /api/chat con HTTP/NDJSON nativo; el chat requiere resolver también transporte 13.3, de modo que M es integración del proveedor, no el subsistema entero (13.5).
12. **Fondos de video — M.** QtMultimedia VideoOutput en capa Background y paleta a partir de fotograma; sustituir mpvpaper/ffmpeg del script (18.20).

La grabación completa, IA online y traducción Cloud de pantalla requieren subsistemas L; no se incluyen como mejoras pequeñas de la 1.0. Ollama es M como integración concreta, con dependencia del transporte L indicada. También deben validarse hardware e integraciones recién implementadas antes de anunciarlas como probadas; esa validación no es una función 🔧 nueva.

## Fuera de alcance

Estos grupos reúnen los ⛔ de las tablas; “fuera del port” no significa que ningún programa Windows pueda ofrecer algo parecido.

- **Compositor/gestión de aplicaciones:** Dwindle, alternar tiling, splits, foco/movimiento direccional Hyprland, Super+arrastre, fullscreen/spoof genérico, reglas por app, snapping Hyprland y scratchpad. Windows conserva Snap, Alt+Tab y mecanismos de cada app. §§3, 21 y atajos.
- **Escritorios especiales o control privado:** grupos Hyprland, mover HWND ajenos entre escritorios y fijarlos en todos; este port usa lista/cambio/creación/cierre Windows, sin adoptar interfaces COM privadas para mover/pin. §§3, 21, 24.
- **Entrada y efectos del compositor:** gestos/libinput Linux, shader anti-flashbang y MangoHud/FPS global. Zoom se considera factible mediante Magnification API, no incluido en este grupo. §§17, 20, 21.
- **Escritorio seguro/autorización:** sustituir bloqueo Windows, Hyprlock/PAM, reloj/contraseña Material de lock, Polkit/UAC, contraseña de energía desde lock, recuperar foco seguro y capturar Ctrl+Alt+Delete. Se usa LockWorkStation y autenticación Windows. §22/apéndices.
- **Acciones privadas de avisos ajenos:** botones “Responder”/acciones originales de toasts no accesibles mediante el listener adoptado; Open a la app es el sustituto. §11.
- **Entorno/aplicaciones Linux:** contrato de acciones .desktop, EasyEffects/Flatpak, tematización GTK/KDE/Fuzzel/Hyprlock, Kitty/Fish Linux, portales Wayland, --core Linux, ConflictKiller de daemons y virtmon. Hay sustitutos Windows en otras filas; un monitor virtual Windows requeriría un proyecto/controlador separado. §§4, 9, 18, 25.
- **Familias que no cargan la función:** SidebarLeft no incluido en Waffle, ni variantes AGS/EWW históricas incluidas automáticamente en el port. §24/apéndice C.

## Validación pendiente y diferencias respecto al PC instalado

La clasificación del hardware se basa en implementación, no en simular éxito. HW documenta en este PC batería ausente, radio desconectada y DDC/CI no disponible; SIDEBAR/PR documentan gamma rechazada y fallback a Windows. Falta comprobar batería, Wi-Fi, Bluetooth y brillo con hardware compatible; también varias pantallas/DPI, HDR, suspensión/reanudación y recursos de red/OneDrive. No se convierten listas vacías en pruebas positivas.

Waffle necesita revisión visual y de acciones completa, especialmente bandeja, centro de acciones y Task View. Las notificaciones requieren permiso del listener; ciertas apps no publican controles GSMTC. El estado de APIs/proveedores online no se verificó ahora.

La presencia de una prueba o un resultado antiguo en PR se cita con su alcance. No se acredita que todo el build, todos los módulos ni un instalador generado hoy hayan pasado esas pruebas. Para funciones QML puras, el razonamiento se limita a dibujo/lógica/archivos Qt; cuando el trayecto aún incluye scripts bash/curl, se señala el bloqueo. secret-tool directo sí tiene backend DPAPI. Historial/teclado/claves recién añadidos necesitan comprobarse en un paquete actualizado; superpaste exige validación de foco/entrega. En los datos de emoji locales se confirmó CRLF por lectura de bytes y se dedujo el fallo del parser; no se abrió el selector.

Las referencias/URLs de la fuente Linux se conservaron como contexto de entrada; no se abrieron. Las 25 secciones, defaults, atajos y advertencias funcionales sí se contabilizan en el resumen. La metodología y la lista bibliográfica no son funciones.
