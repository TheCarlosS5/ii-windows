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
