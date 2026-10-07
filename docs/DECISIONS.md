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
