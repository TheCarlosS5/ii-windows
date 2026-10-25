# Registro de decisiones

Formato: fecha · decisión · por qué · alternativas descartadas.

## D1 · 2026-10-07 · Portar Quickshell real en vez de reescribir
- **Decisión:** fork de Quickshell (commit `41651d7`, el que fija ii) en `quickshell/`, rama `windows`. Se compila con clang-cl y Qt 6.12 MSVC, y se le añade un backend `src/win32`.
- **Por qué:** el QML de ii (~57 000 líneas) depende de semánticas exactas de Quickshell (`qs.*`, singletons, recarga, `Variants`). Compilar el original da esas semánticas gratis. Solo ~10 archivos tenían código POSIX.
- **Descartado:** reescritura web (308 MB por una barra vacía y reescribir todo), host propio tipo wqs (reimplementar Quickshell a mano) y WinUI/WPF (reescribir todo). Ver `FEASIBILITY.md` §3.

## D2 · 2026-10-07 · clang-cl + Qt oficial MSVC
- **Por qué:** Quickshell usa extensiones GNU (VLAs, `__typeof__`) que MSVC `cl` no acepta. clang-cl sí las acepta y es compatible con los binarios oficiales de Qt para MSVC. Además, el toolchain MSVC permite usar C++/WinRT (GSMTC, Bluetooth, notificaciones).
- **Descartado:** MinGW/llvm-mingw, porque el soporte de WinRT es pobre.

## D3 · 2026-10-07 · Qt 6.12.0 descargado y verificado a mano
- **Por qué:** `aqtinstall` 3.3 no entiende el nuevo formato del repositorio de Qt 6.12. `tools/dev/fetch_qt.py` descarga de `download.qt.io` y verifica el SHA1 oficial de `Updates.xml` antes de descomprimir.

## D4 · 2026-10-07 · Regiones de entrada sin `SetWindowRgn`
- **Problema:** `QWindow::setMask` en Windows es `SetWindowRgn`, que además de la entrada **recorta el dibujo** (se perderían las esquinas redondeadas de la barra).
- **Decisión:** hook `ProxyWindowBase::setInputMaskHandler`. En Windows, un temporizador de 16 ms compara el cursor con la región y activa o quita `WS_EX_TRANSPARENT` (`Qt::WindowTransparentForInput`). No se cambia mientras hay un botón pulsado, para no romper arrastres.
- **Descartado:** `WM_NCHITTEST → HTTRANSPARENT`, que solo atraviesa hacia ventanas del mismo hilo.

## D5 · 2026-10-07 · Desenfoque "xray" en Qt, no en DWM
- **Hecho:** ii en Hyprland usa `blur.xray = true` (el desenfoque muestra **solo el wallpaper**, no las ventanas de detrás) e `ignore_alpha = 0.79`. Además, `transparency.enable` está desactivado por defecto.
- **Decisión:** como nosotros pintamos el fondo de escritorio, desenfocamos el wallpaper en Qt y lo mostramos detrás de cada superficie translúcida. Es exacto al píxel y respeta las formas redondeadas.
- **Descartado:** acrílico/Mica de DWM: se aplica a toda la ventana rectangular, no a la forma, y difumina las ventanas de detrás (no es xray).

## D6 · 2026-10-07 · Reserva de espacio con AppBar, una por panel
- Cada `PanelWindow` con zona exclusiva en la capa superior registra su propia AppBar, y Windows apila las que comparten borde (`ABM_QUERYPOS`). Se elimina al destruir la ventana.
- `ABN_FULLSCREENAPP` baja los paneles de la capa Top por debajo de los juegos o vídeos a pantalla completa.

## D7 · 2026-10-07 · No lanzar con `SW_HIDE`
- Windows aplica el `wShowWindow` de `STARTUPINFO` al **primer** `ShowWindow` del proceso. Lanzar la shell con ventana oculta escondería su primera ventana. El lanzador usará `CREATE_NO_WINDOW` sin `STARTF_USESHOWWINDOW`. *Pendiente:* neutralizarlo también dentro del backend.

## D8 · 2026-10-07 · El fondo va encima de Progman, no dentro de WorkerW
- **Hecho comprobado en Sandbox (build 26100.6584):** el mensaje `0x052C` a Progman ya **no crea** un `WorkerW`. Progman solo tiene `SHELLDLL_DefView → SysListView32`.
- **Decisión:** las capas Background y Bottom son ventanas propias de nivel superior, mantenidas justo encima de Progman: debajo de cualquier app y encima del wallpaper de Windows. Se recolocan al cambiar la ventana activa (gancho WinEvent fuera de proceso).
- **Por qué no hacerlas hijas de Explorer:** una ventana hija muere con Explorer, y la shell se quedaría con un HWND inválido. Así, un reinicio de Explorer no la afecta.
- **Ojo:** insertar detrás de una ventana *topmost* la vuelve topmost. Si encima de Progman solo hay ventanas topmost, se usa `HWND_NOTOPMOST`.
- **Pendiente:** Win+D eleva el escritorio de Windows por encima. `ii-host` hará su propio "mostrar escritorio".

## D9 · 2026-10-07 · Render loop "basic" de Qt Quick
- **Problema:** con el render loop *threaded*, las animaciones de las ventanas de la shell (capas, clic-a-través) se quedaban congeladas en el primer frame hasta que llegaba input (el overview vacío hasta mover el ratón). Reproducido y comparado con capturas a lo largo del tiempo.
- **Decisión:** `QSG_RENDER_LOOP=basic` por defecto en Windows (se respeta si el usuario lo define). Con él las animaciones corren desde el hilo de la GUI.

## D10 · 2026-10-07 · ABN_FULLSCREENAPP solo para apps ajenas
- El overview de ii ocupa la pantalla entera, y Windows lo notificaba como "app a pantalla completa", lo que hacía bajar la barra. Ahora se busca qué ventana cubre el monitor y, si es de la propia shell, se ignora.

## D11 · 2026-10-07 · Cambios a ii como overlay, no como fork
- `upstream/` queda intacto. `overlay/ii/` añade o reemplaza archivos y `tools/dev/stage-ii.ps1` monta `build/ii`.
- Se prefiere arreglar en C++ cuando el fallo es genérico; ii no se toca:
  - rutas `/C:/` y `C:/`
  - fuentes
  - `/proc` virtual
- El overlay se reserva para servicios cuyo origen de datos es propio de Linux (por ejemplo `hyprctl`).

## D12 · 2026-10-07 · Notificaciones: leer las de Windows y apagar sus banners
- **Opciones:**
  - (a) solo `notify-send`: ii no vería Discord, WhatsApp, etc.
  - (b) `UserNotificationListener`: API oficial. Funciona sin paquete ni administrador; su evento de cambios sí exige identidad de paquete, así que se consulta cada segundo.
  - (c) sustituir el centro de notificaciones de Windows: requiere inyección en Explorer, descartado.
- **Decisión:** (b). Para que no salgan dos popups, `ii-host` apaga `ShowBanner` por app en `HKCU` mientras corre, con copia previa y restauración en salida, guardián y rescate. Las notificaciones siguen llegando al centro de Windows, así que si ii falla no se pierde nada.
- **Comprobado:** en Sandbox, con `ShowBanner=0` el banner no aparece y la notificación sigue llegando al listener.

## D13 · 2026-10-07 · Bandeja del sistema: un `Shell_TrayWnd` propio que reenvía a Explorer
- Con la barra de tareas oculta, los iconos de bandeja (Discord, Steam…) quedarían inaccesibles.
- **Opciones:**
  - (a) leer los iconos de Explorer: solo con inyección, descartado.
  - (b) reemplazar Explorer como shell: descartado por seguridad.
  - (c) una ventana propia de clase `Shell_TrayWnd`, por delante de la de Explorer, que recibe `Shell_NotifyIcon` y **reenvía todo** a Explorer.
- **Decisión:** (c), en un hilo propio para no depender de la interfaz.
  - Explorer conserva siempre todos sus iconos, así que si ii se cierra o falla no se pierde nada.
  - Los clics se entregan a cada app con los mismos mensajes que usa Explorer. El clic derecho abre el menú nativo de la app.
- **Cuidado comprobado:** si nuestra ventana existe mientras Explorer arranca, su barra queda en blanco. Por eso la bandeja se aparta: destruye su ventana cuando Explorer sale o anuncia una barra nueva, y la recrea cuando la de Explorer lleva unos segundos estable.
- **Probado en Sandbox:** clics, menú nativo, reinicio de Explorer con ii corriendo, e iconos intactos en Explorer al salir.

## D14 · 2026-10-07 · El autoocultar de la barra se guarda también en el registro al restaurar
- `ABM_SETSTATE` solo cambia el estado en memoria de Explorer, que lo guarda en `StuckRects3` cuando quiere. En el Sandbox quedó guardado "autoocultar" aunque el estado restaurado era "normal", y un reinicio de Explorer lo trajo de vuelta.
- **Decisión:** al restaurar, `ii-host` y `ii-rescue` también escriben ese bit en `StuckRects3`. Además, `ii-host` restaura en `WM_QUERYENDSESSION`, antes de que Explorer guarde al cerrar sesión, y vuelve a ocultar si se cancela.
- **Probado:** `tests\test-persist.ps1`, 7/7 con autoocultar apagado y 7/7 con autoocultar encendido (tu configuración).

## D15 · 2026-10-07 · Escritorio real, rutas literales e iconos de Windows
- **Decisión:** terminar `DesktopIcons.qml` iniciado por Claude. El overlay lee el Escritorio personal mediante `StandardPaths.DesktopLocation` y el compartido mediante `%PUBLIC%\Desktop`; se conecta al fondo con parches exactos, fuera del parallax.
- **Rutas:** pasar el `QUrl` de `StandardPaths` directamente a `FolderListModel`. Abrir mediante `xdg-open`/`ShellExecute` con argumentos separados y rutas literales: convertirlas sin escapar a `file:///` perdía `#` y `%` en nombres reales.
- **Mostrar en carpeta:** `ii-shim reveal` resuelve un PIDL y llama a [SHOpenFolderAndSelectItems](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shopenfolderandselectitems). En Sandbox se comprobó el archivo realmente seleccionado en Explorer, no solo que apareciera una ventana.
- **Iconos:** conservar los píxeles BGRA premultiplicados del bitmap Shell mediante `GetDIBits`, con liberación de DC y bitmap. En esta compilación, `QImage::fromHBITMAP` seguido de `reinterpretAsFormat` seguía volviendo opacas las esquinas; la captura del icono real comprueba alpha cero y la miniatura comprueba los píxeles del archivo.
- **Entrada:** el canvas vacío deja pasar clics; reloj y clima conservan sus manejadores. Solo mientras el menú está abierto se eleva el loader de iconos por encima de esos widgets. Un clic fuera cierra el menú.
- **Superficie del menú:** `colLayer1` es un overlay translúcido destinado a otra superficie; sobre el wallpaper dejaba pasar el reloj. Se usa `colLayer0`, igual que el dock, respetando la opción de transparencia de ii.
- **Pruebas:** la inspección QML se inyecta únicamente en la copia de Sandbox. La configuración de producción no incluye IPC de pruebas ni modifica las carpetas del usuario.

## D16 · 2026-10-07 · Fondo y colores sin Python: `switchwall` nativo
- ii cambia el fondo con `switchwall.sh` (bash, matugen, Python). En Windows lo reemplaza `switchwall` de ii-shim, con las mismas opciones (`--mode`, `--image`, `--noswitch`, `--color`, `--type`, `auto`).
- **Colores:** la biblioteca oficial de Google `material-color-utilities` (C++, Apache-2.0), descargada en un commit fijo por `tools/dev/fetch_mcu.ps1`. Es el algoritmo de matugen (Material 3 clásico); el script de Python anterior usaba una variante más nueva, por eso sus colores diferían un poco. Las dos piezas de Abseil que usa se sustituyen por cabeceras mínimas propias (`host/compat`); el código de Google no se modifica.
- El host se compila ahora con `clang-cl` (como Quickshell): la biblioteca usa literales compuestos que `cl` no acepta. Repetidas las 28 pruebas del host: 28/28.
- **Sustitutos de Windows:** selector de archivos de Windows en lugar de `kdialog`, selector de color de Windows en lugar de `hyprpicker`; `test`, `magick identify/-resize` y miniaturas con WIC.

## D17 · 2026-10-07 · Windows sigue la paleta de ii, con copia y restauración
- Mientras `ii-host` corre, Windows usa el modo oscuro/claro de ii y el color de origen del fondo como acento (paleta de acento, menú Inicio, bordes y barras de título clásicas). Solo valores de personalización de `HKCU`, sin administrador.
- Mismo patrón que los banners: antes de cambiar un valor se guarda su estado original en `%LOCALAPPDATA%\ii-windows\theme.txt`; la salida, el atajo de pánico, el guardián y `ii-rescue` lo restauran todo y avisan a Windows (`WM_SETTINGCHANGE`). Desactivable con `ii-host --no-theme`.
- La difusión del cambio se hace en un hilo aparte: puede esperar a ventanas lentas y el hilo principal de `ii-host` también atiende el gancho de teclado, que no debe bloquearse.
- **Probado** (`tests\test-theme.ps1`, 8/8): oscuro y acento al iniciar, cambio a claro al cambiar la paleta de ii, y los 9 valores exactamente como antes tras salida limpia, guardián y rescate.
- Límite: el Explorador de Windows 11 dibuja su barra de título con Mica y no usa el color de acento; las apps con barra clásica sí.

## D18 · 2026-10-07 · Instalador por usuario, sin administrador
- `install.cmd` / `install.ps1` instalan en `%LOCALAPPDATA%\Programs\ii-windows`, solo para el usuario: inicio automático (`HKCU\...\Run`), menú Inicio, entrada en Configuración > Aplicaciones (`HKCU\...\Uninstall`). Funciona con Windows PowerShell 5.1, que trae todo Windows 11.
- **Antes de cambiar nada:** punto de restauración opcional (el único paso que pide administrador, con un aviso de UAC que se puede rechazar) y exportación a `.reg` de cada clave HKCU que se toca. Todo lo instalado queda en `install.json`, que el desinstalador muestra antes de borrar.
- **Cursor Bibata:** se usan solo sus archivos `.cur`/`.ani` (v2.0.7, SHA-256 fijado). Su `install.inf` no se usa: copia a `C:\Windows\Cursors` y escribe en HKLM. Se aplica por usuario y se guarda el esquema anterior con sus tipos exactos.
- **Iconos:** los temas Breeze se empaquetan en un único `icons.rcc` comprimido (40 000 archivos, 204 MB → 1 archivo, 12 MB); instalar tarda segundos.
- **Fuentes:** no se instalan en el sistema; la shell las carga solo para ella (no hace falta tocar `Fonts` del sistema ni del usuario).
- **Windows Terminal:** un *fragment* añade el esquema de colores "ii-windows" (paleta de terminal de ii, con sus parámetros de `terminalGenerationProps`) sin modificar `settings.json`; se elige en la configuración de Terminal.
- **Probado** (`tests\test-install.ps1`, Sandbox limpio): 15/15. ii aparece en el primer arranque y, tras desinstalar, cursor, tema, barra, inicio automático y archivos quedan exactamente como antes.
- El primer arranque destapó dos fallos de `FileView` en Quickshell (operación olvidada al reentrar, carpetas sin vigilar si no existían): corregidos en el fork.

## D19 · 2026-10-08 · La barra reserva su espacio hablando directamente con Explorer
- Problema (en tu PC): las ventanas maximizadas quedaban debajo de la barra. La bandeja de ii es la `Shell_TrayWnd` que encuentra `FindWindow`, así que `SHAppBarMessage` de la propia shell le llega a ella; cuando quien llama y la bandeja están en el mismo proceso, shell32 pasa un puntero local en vez de memoria compartida, y Explorer ignora `ABM_QUERYPOS`/`ABM_SETPOS` sin dar error. Desde otras apps el reenvío funciona (probado).
- Solución: `AppBar` (quickshell `src/win32/native.cpp`) envía a la barra de Explorer el mensaje con el formato que shell32 usa entre procesos: `WM_COPYDATA` de 64 bytes, bloque `SHAllocShared` cuyo dueño es Explorer en el byte 48 y su PID en el 56 (capturado en Windows 11 24H2 con `tests\appbar-capture2.ps1`). `SHAllocShared`/`SHLockShared`/`SHFreeShared` están documentadas; la disposición del mensaje no.
- Riesgo y salvaguarda: si una actualización de Windows cambia ese formato, Explorer ignoraría la reserva (las ventanas volverían a pasar debajo de la barra), sin otro efecto. No hay inyección ni cambios en el sistema; si no hay barra de Explorer o falla la memoria compartida se usa `SHAppBarMessage`. `tests\ii-appbar.ps1` lo detecta.
- Además: vigilante de 3 s que re-registra la barra si se pierde la reserva (reinicios de Explorer), y la bandeja suelta a las apps antes de reenviar sus iconos y nunca espera más de 2 s (esperar 15 s colgó Explorer una vez en tu PC).

## D20 · 2026-10-08 · Escritorio como el de Explorer: teclado, arrastre y acciones del shell
- **Teclado sin subir sobre las apps:** la ventana del fondo ahora es enfocable (`focusable`), así que un clic en el escritorio le da el teclado como al de Windows. Para que no tape las apps al activarse, el backend win32 (`native.cpp`) descarta en `WM_WINDOWPOSCHANGING` la subida al frente (`HWND_TOP`) de las ventanas de capa Background/Bottom; solo nuestro reordenamiento (con una ventana explícita) las mueve. Además ningún panel se activa por aparecer (`_q_showWithoutActivating`): solo los que piden el teclado (`updateKeyboardGrab`) lo toman.
- **Acciones de archivos por el shell de Windows** (`ii-shim files`, `host/src/fileops.cpp`): Papelera, eliminar, renombrar, copiar/mover/pegar con `IFileOperation` (diálogos de conflicto y progreso de Windows); portapapeles con `CF_HDROP` + `Preferred DropEffect` como Explorer; Propiedades (`SHObjectProperties`/`SHMultiFileProperties`); "Abrir con" (`SHOpenWithDialog`); el menú completo de Explorer (`IContextMenu`, con submenús de extensiones). Los verbos que corren dentro del proceso se esperan con `SHSetInstanceExplorer` y las ventanas propias. Solo APIs documentadas.
- **Arrastre del sistema:** mover iconos es un arrastre OLE real (`Drag.startDrag`), así que los archivos también se pueden soltar en Explorer, el navegador o chats, y soltar aquí archivos de otras apps. Lo que llega de fuera se mueve/copia con `ii-shim` y se informa "copiado" al origen, para que nunca borre nada por su cuenta.
- **Posiciones:** cuadrícula; lo que mueves a mano queda guardado en `State/user/desktop-layout.json` (claves sin distinguir mayúsculas: Qt y el shell escriben `c:` y `C:`). Archivos nuevos van a la primera celda libre; si no caben, la última celda muestra "+N" y abre la carpeta.
- **Menú del escritorio en su propia ventana (capa Overlay):** vive en el fondo pero debe verse sobre las apps, como el de Explorer. No toma el teclado: el escritorio lo conserva (Esc, renombrar justo después).
- **Probado** en Sandbox: `ii-desktop2.ps1` 41/41 (selección, teclado, foco sin subir sobre una ventana, arrastre guardado tras reiniciar, soltar en carpeta, renombrar, Ctrl+C/V, Papelera, carpeta nueva donde se hizo clic, menú nativo, Propiedades, ordenar, desbordamiento con 100+ archivos), y siguen pasando `ii-desktop` 27/27, `ii-desktop-host` (Win+D), `ii-desktop-menu`, `ii-photo`, `ii-launcher`, `ii-overview-dock`.

## D21 · 2026-10-08 · Batería, Bluetooth y brillo nativos (Codex)
- Detalle en `docs/HARDWARE-SERVICES.md`. `Quickshell.Services.UPower` y `Quickshell.Bluetooth` dejan de ser sustitutos vacíos: batería con `GetSystemPowerStatus` + WinRT `Battery`; Bluetooth con WinRT `Radios`, `DeviceWatcher` y `DeviceInformationPairing` (lo que Windows no permite desde fuera abre Configuración > Bluetooth). Brillo en `ii-shim` (`ddcutil`/`brightnessctl`): DDC/CI (`dxva2`) para monitores y WMI para paneles internos, en procesos hijos con plazo para no congelar nunca la shell.
- Sin hardware todo se degrada como en un PC Linux sin él: sin batería ii oculta la batería; sin radio, "Bluetooth no disponible"; sin DDC/CI, no aparece el control de brillo.
- En tu PC: tu monitor no expone DDC/CI a Windows (`GetPhysicalMonitorsFromHMONITOR` → error 1168, comprobado a mano además de con `ii-shim`), así que no tendrás control de brillo; el adaptador Bluetooth está desconectado y no hay batería. Lo que dependa de hardware real queda sin probar.

## D22 · 2026-10-10 · Ejecución de TASKS_ii_windows.md: decisiones que ajustan el diseño anterior
(Propuestas adoptadas por el agente, no aprobadas por Carlos; el detalle y la evidencia están en la sección 15 de `TASKS_ii_windows.md` y en `docs/seguimiento/`.)
- **Recuperación del host (R02/R05):** fases registradas; `CreateProcess` fallido ⇒ 3 intentos con espera 1/2/4 s y después restauración y un aviso; una shell que no muestra su fondo en 45 s (90 s sin caché QML) devuelve Explorer mientras se reinicia; readiness por monitor; el rescate y la guardia detienen solo el proceso registrado (PID + creación + ruta + sesión). `restore` solo deshace lo que ese ii ocultó; el rescate fuerza.
- **Banners de Windows (R01):** solo se apagan mientras la shell informa por un canal versionado (instancia, remitente, caducidad 3 s) de un listener «available/granted/subscribed».
- **Bloqueo (R03):** `secure` solo es verdadero tras el evento WTS de la sesión; `LockWorkStation` se pide al instante y solo inicia el bloqueo.
- **Instalación (R04/R06/R07/R08):** el desinstalador borra una lista fija de carpetas de ii, nunca `quickshell\` entero; tarea de inicio por SID; versiones en `versions\<id>` con `current.txt` atómico, `ii-launcher.exe` como entrada estable y vuelta atrás si la versión nueva no se confirma; cada cambio externo (GPU, cursor, Run, tema, banners) guarda original/aplicado/dueño y se restaura solo si sigue siendo lo que puso ii.
- **Atajos (U01/U02/P12):** una única lista, `shared/actions.json`, de la que salen la tabla de `ii-host`, la chuleta y `docs/ATAJOS.md`. Los atajos de ii **ya no ceden con una ventana maximizada** (antes cualquier ventana que cubriera el monitor los desactivaba, y con la barra oculta eso incluía un navegador maximizado: Win volvía a abrir Inicio). Ceden con pantalla completa exclusiva/modo presentación y con ventanas sin borde a pantalla completa (salvo navegadores), y por regla en `%LOCALAPPDATA%\ii-windows\shortcuts.ini`: `[policy] fullscreen=auto|geometry|never`, `[yield] processes=juego.exe;...`, `[keep] processes=...`. Un `[yield]` explícito gana a `never`. Nuevos: Win+I (ajustes de ii), Win+R (búsqueda de ii: programas y enlaces, no ejecuta órdenes escritas hasta C05), Win+T (vista de ventanas), Win+X (menú de sesión), Impr Pant (captura de región). Win+P, Win+E, Alt+Tab, Ctrl+Mayús+Esc siguen siendo de Windows hasta U05/X02/U03/X03.
- **Rutas Linux (C12):** pin sin `hyprctl`, lista de idiomas por Qt con resolución real (es_CO→es_MX), `ii-shim` aprende `mkdir/rm/reset-dir/which` solo para carpetas del usuario; inventario en `docs/INVENTARIO-RUTAS-LINUX.md`.
- **Pruebas:** `tools/sandbox/run-tests.ps1` (cada prueba en su proceso, timeout que mata el árbol, skips que no cuentan como PASS). Los interruptores `II_DATA_DIR`, `II_NO_UI`, `II_TEST_*` y `-Sandbox` existen solo para probar sin tocar el ii real y no cambian el comportamiento normal.

## D23 · 2026-10-24 · Plan de los primeros usuarios (bloque 0)
(Propuestas del agente sobre `PLAN-ii-windows.md`; sin probar en la laptop gamer ni con juegos reales.)
- **Latido de la shell (0.1):** Quickshell (backend win32) envía `WM_APP+5` a `ii-host` cada segundo desde un `QTimer` del hilo de la interfaz. Desde el primer latido tras "lista", 5 s de silencio con el hilo **sin gastar CPU** (esperando a la GPU, a un bloqueo) = congelada: `ii-host` devuelve barra, iconos y banners, termina la shell por su handle y lanza otra. Si el hilo está en silencio pero gastando CPU (carga de QML en un PC lento) se espera hasta 30 s. **Por qué la CPU:** la primera prueba real dio un falso positivo: la carga del QML tuvo el hilo ocupado 9 s justo al quedar lista. 3 congelamientos en 5 min con un juego al frente ⇒ no se relanza hasta que el juego termina (o lleva 1 min sin estar al frente) y se avisa con una notificación de Windows; sin juego ⇒ se abandona y se restaura todo. Una shell que late pero no tiene ninguna ventana en pantalla 20 s (sin pantalla completa, sin sesión bloqueada) se trata igual. `sceneGraphError` de Qt termina la shell (código 70) para que se recreen las ventanas. Suspensión/reanudación y bloqueo dan un margen. Interruptores de prueba: `II_TEST_FREEZE=<n>` (shell), `II_TEST_HEARTBEAT_MS` (host). Pruebas: `test-host-heartbeat.ps1` (30/30, con shell falsa) y una corrida con la shell real: congelada → barra devuelta y shell nueva a los 5,7 s.
- **Luz nocturna (0.2):** `light.night.automatic` pasa a `false` por defecto; una instalación con el horario intacto de upstream (19:00–06:30, 5000 K) se apaga una vez (`nightLightMigrated`); hasta comprobarlo el horario cuenta como apagado. Si la luz nocturna de Windows está encendida (blob de `CloudStore`, byte 18 = 0x15), `ii-host` no aplica temperatura encima (solo gamma) y el panel lo dice (error 6).
- **Fondo (0.3):** `default_wallpaper.png` es propio (`tools/dev/make-default-wallpaper.py`, licencia del repo), en la misma ruta que el de upstream, así que todo respaldo existente lo usa. Un fondo cambiado desde Windows se adopta en ii (decisión de Carlos tras la revisión: "ii manda" se sentía como "no me deja cambiar el fondo"); uno elegido en ii pasa a Windows. Un fondo elegido cuyo archivo ya no existe pasa al propio (`--default`), y la copia antigua del café en `Imágenes\Wallpapers\ii-default.png` (PNG 3840×2160) se reemplaza (se reconoce por SHA-256). La caché de la portada se renueva al cambiar `config.json` y la portada exige que su copia sea del fondo actual. Límite: un solo fondo para todos los monitores (`SPI_SETDESKWALLPAPER`); Spotlight/presentación se convierten en la imagen que mostraban.
- **Lanzador (0.4):** la cuadrícula de apps se crea 8 s después de cargar la configuración y se conserva; la ventana de la vista general se muestra una vez, vacía e invisible (sin máscara de entrada ni teclado), para que su primer dibujo no ocurra al pulsar Win. Los iconos ya tenían caché en disco y el gancho ya tenía su hilo.
- **Teclado y juegos (0.5):** `[unhook] processes=` en `shortcuts.ini` más una lista incluida (Valorant, LoL, Fortnite, Apex, R6, Tarkov…): con uno al frente el hilo del gancho lo quita (`UnhookWindowsHookEx`) y lo repone al salir. Si un Win solo fue para ii pero ninguna ventana de la shell llegó al frente en 700 ms (sobre una ventana que cubre la pantalla) o la shell no late, se abre el Inicio de Windows con un Win inyectado que el gancho deja pasar.
- **GPU (0.6):** `--gpu-policy` elige la GPU que tiene la pantalla **principal** (10 ahorro, 12 alto rendimiento, 11 Windows decide). Antes solo miraba si la de ahorro tenía alguna pantalla. Metadatos de versión (descripción, autor) en `ii-host`, `ii-shim`, `ii-launcher` y `quickshell.exe`. No se tocan perfiles del driver de NVIDIA (sin NVAPI): el README explica cómo excluir ii.
- **Wallpaper Engine (0.7):** los paneles no enfocables llevan `WS_EX_NOACTIVATE` además de `Qt::WindowDoesNotAcceptFocus`; con un fondo externo activo el escritorio de ii solo es enfocable mientras se renombra (Supr, F2, Ctrl+C/V del escritorio no van por teclado en ese caso).
- **Tras la revisión del 2026-10-24:** la rama del fork salió de `ii-tasks` y le faltaban 11 commits de `main` (QS_PRECOMPILE, escaneo del menú Inicio fuera del hilo de la interfaz, LazyLoader); se fusionó `main`. Con eso la shell queda lista en 2,5 s (antes 6–12 s) y el episodio de 9 s "ocupado" ya no aparece; la detección del congelamiento sigue en 5,8 s. Además: la cuadrícula del lanzador queda viva al buscar y en Win+Tab (solo se oculta); el juego se sigue por pid si el anticheat niega el handle; un Win solo cuenta como respondido si la búsqueda de ii se ve encima aunque Windows no le dé el primer plano (`test-host-games.ps1`, 14/14); el café se reconoce por SHA-256 del archivo o de sus píxeles; `ii-host` decide la GPU antes de cada arranque (solo valores suyos, `state.ini [gpu]`) y el instalador ya no la escribe; el gancho ya se quitaba en el evento de primer plano (comprobado: 114 ms).
- **Funciones pedidas (plan 1.5, 2.1, 2.2, 2.3) y otros arreglos del 24 de octubre:** aviso del cargador en la píldora de Bloq Mayús (`osd.charger`; el de Bloq Mayús ya existía). Barra: opción "Ninguna" (`bar.enable`) y `Appearance.sizes.barReserve` para lo que dejaba sitio a la barra; "Abajo" ya existía y el dock se apila encima (comprobado con capturas). Minimizar hacia el dock: una tarjeta con el icono de la app baja al dock (DWM no muestra nada de una ventana ya minimizada) y al restaurar sale una miniatura en vivo; movido por un temporizador (una animación ligada a los fotogramas de la ventana superpuesta no avanzaba); la animación de Windows se apaga solo en memoria (`minanim.cpp`) y cualquier ruta de restauración vuelve a aplicar el valor guardado del usuario. Lo que queda de Windows: `docs/LO-QUE-QUEDA-DE-WINDOWS.md`. Ventanas normales (configuración, tienda, bienvenida) ajustadas al área útil de su monitor la primera vez que se muestran (a 150 % la de configuración salía con la barra de título fuera de la pantalla). Sonidos de la interfaz rehechos graves y suaves, sin nada por encima de 2 kHz, y volumen por defecto 0,4.
- **Tras la segunda revisión (2026-10-25):** la opción "Ninguna" se quitó: sin barra no quedaba bandeja en ningún sitio, y ii se queda con la de Windows (D13). En su lugar, **"Junto al dock"** (`bar.besideDock`, plan 2.1): `DockBar.qml`, dos pastillas en las esquinas de abajo, a la altura del dock y sin su aumento, con bandeja, indicadores, batería y reloj a la derecha y barra lateral y recursos a la izquierda; la opción también pone `bar.bottom`, así que los menús emergentes y los de la bandeja se abren hacia arriba (comprobado con captura). Las pastillas reservan la franja del dock y el dock se queda en ella con `ExclusionMode.Ignore`. Minimizar: sin vuelo al restaurar (la ventana se veía doble). "La búsqueda de ii se ve" ya no es "cualquier ventana de la shell siempre encima y a pantalla completa": Quickshell para Windows marca cada ventana de panel con su *namespace* (`SetPropW`) y `ii-host` busca solo `quickshell:overview`, que la vista general tiene solo abierta (`quickshell:overviewHidden` mientras calienta). `MinAnimate`: se guarda en `state.ini` el valor que Windows tenía al apagarlo y se restaura ese, no el del registro (Rendimiento > Aplicar con ii en marcha guardaba el 0 de ii); si el registro quedó con otro, se reescribe. El aviso del cargador lee nivel y estado 1 s después. El volumen 0,6 guardado pasa a 0,4 una vez (`uiVolumeMigrated`). `ScreencopyView` agrupa en una sola actualización de DWM los cambios de posición y tamaño.
- **Tercera revisión (2026-10-25), "Junto al dock":** las pastillas llevan todo lo de la barra: escritorios virtuales, recursos, botones de utilidades y reproductor a la izquierda; bandeja, indicadores, batería y reloj con fecha a la derecha. Nunca tocan el dock: cada una tiene el espacio entre su esquina y el dock con sus iconos aumentados (`GlobalStates.dockSpanLeft/Right`) y muestra el conjunto más completo que cabe. Sin espacio, la derecha quita la fecha y después agrupa toda la bandeja tras su botón de "más"; la izquierda quita reproductor, utilidades, recursos y escritorios, en ese orden. Se calcula con el ancho medido de cada elemento (que no cambia al ocultarlo), no probando. Comprobado con capturas a 150 % (1280 px lógicos) con 14 apps fijadas e iconos de 52 px. Solo con el dock abajo y encendido (`Appearance.barBesideDock`): con el dock a un lado se muestra la barra abajo, se conserva la elección y Configuración lo avisa. **Límite conocido de `MinAnimate`:** si el usuario quita a propósito "Animar ventanas al minimizar y maximizar" mientras ii corre, al salir ii pone el valor de antes, porque no se distingue de que Rendimiento > Aplicar haya guardado el 0 de ii.
