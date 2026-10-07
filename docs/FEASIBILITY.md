# Viabilidad: Illogical Impulse en Windows 11

Fecha: 2026-10-07 · Máquina de referencia: Windows 11 Pro 25H2 (build 26200.6584), 1 monitor 1920×1080 al 100 %, GPU AMD integrada.

## 1. Conclusión en una línea

Es viable con **alta fidelidad**: compilamos **Quickshell real** para Windows y ejecutamos el **QML original de ii** casi sin cambios. Lo que depende de Hyprland se sustituye por equivalentes de Windows y no se toca el manejo de ventanas. Ya funciona de punta a punta una barra con transparencia, esquinas redondeadas, clics que atraviesan las zonas vacías y reserva de espacio.

## 2. Qué encontré en el repositorio original

- `end-4/dots-hyprland`, commit `33f31a0` (3 oct 2026). Licencia **GPL-3.0**. La configuración de Hyprland ahora es **Lua** (`hypr/hyprland/*.lua`).
- La shell es `dots/.config/quickshell/ii`: **~57 000 líneas de QML** y 586 archivos, con dos "familias" de paneles: `ii` (Material 3, la que queremos) y `waffle` (imita Windows 11).
- Usa Quickshell fijado en el commit `41651d7` (licencia **LGPL-3.0**) y **Qt ≥ 6.10** (usa `Qt.labs.synchronizer`).
- Viene traducida, **incluido `es_MX`**.
- Ya existe un intento de Quickshell en Windows: [`rdepa29/wqs`](https://github.com/rdepa29/wqs) (GPL-3, de una semana de antigüedad). Es una reimplementación desde cero, inmadura y orientada a usarse con el gestor de ventanas komorebi. Solo la uso como referencia.

## 3. Rutas evaluadas (con evidencia)

| Ruta | Qué probé | Resultado |
|---|---|---|
| **A. Quickshell real compilado para Windows + backend Win32** (elegida) | Compilé Quickshell `41651d7` con clang-cl y Qt 6.12. Solo hubo que portar ~10 archivos con código POSIX (bloqueos de archivo, enlaces, logs, `fork`). Escribí un backend `src/win32` con `PanelWindow`, capas, AppBar y regiones de entrada. | ✅ Carga configuraciones QML con `qs.*`, singletons, `Variants`, `Process` y `FileView`. La barra prototipo reserva 40 px (el área de trabajo pasa a `0,40→1920,1080` y vuelve sola al cerrar), las esquinas transparentes dejan pasar el clic y el desenfoque "xray" del fondo funciona. **131 MB de RAM** (incluye un fondo de 3072×1920 desenfocado) y **~2 % de CPU** con animaciones. |
| B. Interfaz web (Electron/Tauri) | Barra con acrílico y AppBar mediante FFI (`prototypes/web-bar`). | ⚠️ El AppBar funciona desde cualquier tecnología, pero la barra vacía usa **308 MB** y habría que **reescribir las 57 000 líneas** a HTML. Además, seguir las actualizaciones de end-4 sería imposible. Descartada. |
| C. Host propio que imita Quickshell (estilo wqs) | Revisé el código de wqs. | ⚠️ Cada detalle de Quickshell (recarga, `qs.*`, singletons, `Variants`, `LazyLoader`…) habría que reimplementarlo a mano y nunca quedaría exacto. La ruta A da esas semánticas gratis porque **es** Quickshell. Descartada. |
| D. Reescritura nativa (WinUI 3 / WPF / Flutter) | Evaluada sobre papel. | ❌ Supone reescribir todo, sin componentes Material 3 Expressive equivalentes ni camino para seguir las actualizaciones. Descartada. |

**Por qué gana A:** máxima fidelidad (es el mismo QML), menor trabajo, y cada actualización del dotfile se puede incorporar con `git merge`.

## 4. Arquitectura

```
┌───────────────────────── ii (QML original de end-4) ─────────────────────────┐
│ barra, sidebars, overview, dock, notificaciones, OSD, sesión, cheatsheet...  │
│ + parches pequeños solo donde llama a comandos de Linux (bash, nmcli, ...)   │
└───────────────▲──────────────────────────────────────────────▲───────────────┘
                │ mismas APIs QML                               │
┌───────────────┴─────────── quickshell (fork) ─────────────────┴──────────────┐
│ núcleo de Quickshell sin cambios de comportamiento (Linux sigue compilando)  │
│ src/win32: PanelWindow, capas, AppBar, clic-a-través, fondo de escritorio    │
│ servicios Windows con la API de los de Linux:                                │
│   Pipewire→Core Audio · Mpris→GSMTC · UPower→batería/energía                 │
│   Bluetooth→WinRT · Network→WlanAPI · SystemTray→bandeja propia              │
│   Notifications→UserNotificationListener · Hyprland→shim (atajos, monitores) │
└──────────────────────────────────────▲───────────────────────────────────────┘
┌──────────────────────────────────────┴───────────────────────────────────────┐
│ ii-windows host: lanzador + vigilante, ocultar barra de tareas e iconos,     │
│ hook de teclado (tecla Windows → launcher), modo recuperación, instalador    │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 5. Inventario de módulos y veredicto

✅ viable · 🟡 parcial (explico el límite) · ❌ no se puede o no tiene sentido en Windows

| Módulo ii | Veredicto | Equivalente en Windows / límite |
|---|---|---|
| Barra (y barra vertical) | ✅ | `PanelWindow` + AppBar. Los "workspaces" se muestran como escritorios virtuales (API interna, opcional y aislada) o se ocultan. |
| Overview / launcher | ✅ | Búsqueda de apps (accesos del Menú Inicio + `shell:AppsFolder` para UWP), calculadora y comandos. Ventanas abiertas con **miniaturas DWM**: clic para activarlas. 🟡 No se arrastran ventanas entre workspaces (sería gestionar ventanas). |
| Sidebar derecha (ajustes rápidos, notificaciones, calendario, todo, pomodoro, Bluetooth, Wi-Fi, mezclador) | ✅/🟡 | Wi-Fi con WlanAPI, Bluetooth con WinRT, volumen por app con Core Audio, energía, no molestar, café (evitar suspensión). 🟡 Luz nocturna: la de Windows no tiene API pública, así que se haría con rampa gamma o se abre Configuración. |
| Notificaciones | 🟡 | Las propias de la shell funcionan al 100 %. Para **leer las de otras apps**, Windows exige que la app tenga identidad de paquete (MSIX "sparse") y tu permiso. Firmarlo con un certificado propio requiere **un paso de administrador**, que te pediré antes. Límite: se pueden mostrar y descartar, pero no pulsar los botones de acción de otras apps (sí abrirlas). Los avisos de Windows se silencian con "No molestar". |
| Bandeja del sistema | 🟡 | Técnica de Cairo/ManagedShell: una ventana propia `Shell_TrayWnd` por delante de la de Explorer recibe los iconos y **reenvía todo a Explorer**. Sin inyección. Los menús serán los nativos de cada app. Algunos iconos raros pueden fallar. |
| Media (MPRIS) | ✅ | GSMTC: título, carátula, posición y controles de Spotify, navegadores, etc. |
| OSD (volumen/brillo) | ✅ | Capturamos las teclas de volumen y aplicamos el cambio nosotros, así no sale el OSD de Windows. Brillo por DDC/CI (monitores externos) o WMI (portátiles). |
| Fondo y widgets de escritorio (reloj, clima) | ✅ | Ventana propia en la capa del fondo. Fondos de vídeo con QtMultimedia. |
| Escritorio con accesos directos y widgets de carpetas | ✅ (nuevo) | ii no tiene iconos de escritorio. Los añado al estilo ii, leyendo carpetas y archivos reales. Los iconos de Windows se ocultan (ajuste de usuario reversible). |
| Dock | ✅ | Apps fijadas + ventanas abiertas (agrupadas por AppUserModelID), iconos del paquete con respaldo al icono real del `.exe`. |
| Menú de sesión | ✅ | Bloquear, cerrar sesión, suspender, hibernar, reiniciar y apagar con APIs estándar. |
| Cheatsheet | ✅ | Generada desde nuestra tabla de atajos para Windows, no desde la de Hyprland. |
| Selector de wallpaper + colores Material 3 | ✅ | Mismo algoritmo (material-color-utilities). También aplica modo oscuro/claro, color de acento, barras de título y Windows Terminal. |
| Overlays (mezclador, notas, crosshair, recursos, imagen flotante, grabador) | ✅/🟡 | Grabador con ffmpeg (`ddagrab`). 🟡 El limitador de FPS depende de Hyprland y queda fuera. |
| Selector de región (captura, OCR, Lens) y traductor de pantalla | ✅ | Captura de pantalla + OCR de Windows (`Windows.Media.Ocr`). |
| Sidebar izquierda (IA, traductor, booru) | ✅ | Solo HTTP. Las claves se guardan en el Administrador de credenciales de Windows. Baja prioridad (pedido tuyo). |
| Teclado en pantalla | 🟡 | Posible con SendInput, baja prioridad. Windows ya trae el suyo. |
| Pantalla de bloqueo | ❌ | Windows no permite reemplazarla de forma segura (Win+L es protegido). Se usa la de Windows con el wallpaper de ii. |
| Polkit | ❌ | En Windows es el UAC, que no se toca. |
| EasyEffects, ydotool, hyprsunset, reconocimiento de música (songrec) | ❌/🟡 | No existen en Windows. Se ocultan o se sustituyen cuando haya algo equivalente. |

## 6. La interfaz nativa de Windows (sin parchear Explorer)

Hipótesis confirmada en lo probado: **no hace falta reemplazar `explorer.exe`, ni inyectar DLLs, ni tocar `Winlogon\Shell`.**

- **Barra de tareas:** se oculta con `ShowWindow` sobre `Shell_TrayWnd` / `Shell_SecondaryTrayWnd`, con un vigilante que la vuelve a ocultar si Explorer se reinicia (mensaje `TaskbarCreated`). No se modifica nada persistente: si la shell muere, basta con reiniciar Explorer. *Pendiente de probar en Sandbox.*
- **Iconos del escritorio:** se ocultan con el ajuste de usuario `HideIcons` (HKCU) o escondiendo `SHELLDLL_DefView`. Nuestro escritorio va en la capa del fondo. En 24H2/25H2 cambió la estructura `Progman/WorkerW`, así que lo verificaré en Sandbox antes de tocar tu sesión.
- **Tecla Windows y Menú Inicio:** hook de teclado de bajo nivel. Se traga la pulsación *sola* de Win (y Ctrl+Esc) y abre nuestro launcher. Win+L y Ctrl+Alt+Supr **no se pueden interceptar ni se intentará**: siempre funcionan. Win+D y el resto se dejan pasar salvo los que mapeemos.
- **Juegos a pantalla completa:** la barra se aparta sola (`ABN_FULLSCREENAPP`), para que no tape el juego ni le quite rendimiento. Habrá también una opción para pausar los atajos mientras juegas.

## 7. Seguridad y reversibilidad

- Todo se instala **por usuario** (HKCU, `%LOCALAPPDATA%`), sin admin, salvo el certificado opcional de notificaciones, que te pediré aparte.
- Antes de tocar nada: punto de restauración (ya creado uno el 2026-10-07) y exportación a `.reg` de cada clave que modifiquemos.
- **Atajo de pánico** global y `ii-windows-rescue` (script independiente que funciona aunque la shell esté colgada). Restaura barra de tareas, iconos del escritorio, Menú Inicio, área de trabajo y reinicia Explorer.
- Lo arriesgado se prueba en **Windows Sandbox** (ya activado; falta reiniciar el PC).
- Sin telemetría. Todo se descarga de fuentes oficiales con verificación SHA (Qt, Microsoft) y queda listado en el desinstalador.

## 8. Riesgos conocidos

- **API interna de escritorios virtuales:** cambia entre builds. Va aislada y es opcional; si falla, la barra oculta los workspaces.
- **Notificaciones de otras apps:** dependen de la identidad de paquete (ver arriba).
- **Bandeja:** iconos de apps poco comunes pueden comportarse raro. Siempre hay reenvío a Explorer.
- **Anti-cheat (Valorant/Vanguard):** no inyectamos nada en otros procesos. Los hooks de teclado son los mismos que usan AutoHotkey o PowerToys, y aun así se podrán pausar en juegos.
- **Seguir a upstream:** el QML de ii cambia rápido. Mantengo los cambios para Windows pequeños y separados para poder fusionar.

## 9. Hitos

1. ✅ **Viabilidad** (este documento, prototipos, Quickshell compilando en Windows).
2. **Cimientos:** ocultar barra e iconos con camino de vuelta, rescate y atajo de pánico, capa de fondo, hook de teclado. Probado en Sandbox.
3. **ii arrancando:** cargar el QML original de ii con shims de Hyprland/Wayland. Primero barra, launcher/overview y ajustes rápidos.
4. **Servicios:** audio, media, red, Bluetooth, energía, brillo, bandeja, notificaciones.
5. **Dock, overlays y widgets de escritorio** (tus prioridades).
6. **Temas:** Material 3 desde el wallpaper, tipografías, iconos, cursor Bibata, colores de Windows y Terminal.
7. **Instalador/desinstalador, multimonitor/DPI, reinicio de Explorer, sleep/resume.**
8. **Documentación final.**
