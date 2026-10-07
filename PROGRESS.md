# PROGRESS

Port de la interfaz de [Illogical Impulse](https://github.com/end-4/dots-hyprland) (end-4) a Windows 11.
Documentos: [Viabilidad](docs/FEASIBILITY.md) · [Decisiones](docs/DECISIONS.md)

## Estado (2026-10-07, 19:00)
- ✅ **Hito 1, viabilidad:** prototipos hechos y ruta elegida.
- ✅ **Hito 2, cimientos:** `ii-host`, rescate y atajo de pánico. Probado en Windows Sandbox con 28/28 comprobaciones.
- 🟡 **Hito 3, ii funcionando:** el QML original de ii corre en Windows (en Sandbox) con datos reales:
  - la barra con CPU/RAM, reloj, media y notificaciones
  - el fondo con su reloj, por encima del escritorio de Windows y debajo de las apps
  - el overview con búsqueda de apps, calculadora y miniaturas en vivo de las ventanas
  - las dos sidebars: toggles, volumen, calendario y lista de notificaciones
  - los controles de media (Spotify, navegadores, cualquier app que use los controles de Windows)
  - las notificaciones de Windows (Discord, WhatsApp, etc.) como popups de ii
  - la bandeja del sistema (Discord, Steam…) dentro de la barra de ii, con el menú propio de cada app
  - el estado de la red (cable o Wi-Fi) y su nombre
  - las tipografías, iconos y colores Material

  Faltan Bluetooth, batería y brillo, y las prioridades: dock, overlays y widgets.

Todo lo de esta etapa se ha probado **solo dentro de Windows Sandbox**. En tu sesión real no se ha instalado ni cambiado nada, salvo las herramientas de desarrollo del Hito 1.

## Hecho

### Hito 1: viabilidad
- [x] Inventario del dotfile, licencias (GPL-3 para ii, LGPL-3 para Quickshell) y comparación de rutas.
- [x] Quickshell compilado para Windows (fork en `quickshell/`, rama `windows`).

### Hito 2: cimientos (`host/`, `tools/rescue/`)
- [x] `ii-host.exe` (C++, sin dependencias):
  - oculta la barra de tareas en todas las pantallas y la vuelve a ocultar si Explorer se reinicia
  - oculta los iconos del escritorio sin cambiar nada persistente
  - tecla Windows → búsqueda de ii, y atajos Super+… de ii
  - Win+L, Win+R y los atajos que no son de ii siguen siendo de Windows
  - Win+D propio: minimiza las apps y deja visible el fondo de ii; la segunda vez las restaura
  - apaga los banners de notificación de Windows mientras ii corre (ver Notificaciones)
- [x] Si la shell no corre, la tecla Windows abre el Inicio normal.
- [x] Proceso guardián: si `ii-host` muere, restaura todo solo.
- [x] Atajo de pánico **Ctrl+Alt+Shift+R**: restaura barra de tareas, iconos, autohide, área de trabajo y banners, y sale.
- [x] `tools/rescue/ii-rescue.cmd` / `.ps1`: recuperación sin depender de ningún binario.
- [x] Laboratorio de pruebas en Windows Sandbox (`tools/sandbox/`), controlado por carpeta compartida.

### Hito 3: ii en Windows
- [x] Backend `src/win32`:
  - paneles con anclajes y márgenes
  - zonas exclusivas reales (AppBar)
  - capas: fondo encima del escritorio de Windows y debajo de las apps, Top/Overlay por encima
  - clic-a-través por regiones, sin romper el teclado
  - foco de teclado exclusivo (se puede escribir en la búsqueda)
  - los juegos a pantalla completa apartan la barra; los paneles propios no
- [x] Módulos de compatibilidad (misma API QML que en Linux):
  - `Quickshell.Wayland`: capas, lista real de ventanas, miniaturas DWM en vivo, bloqueo → bloqueo de Windows, evitar suspensión
  - `Quickshell.Hyprland`: atajos globales, cerrar al hacer clic fuera, monitores, `dispatch` (abrir apps, enfocar y cerrar ventanas)
  - `Quickshell.Services.Pipewire` → Core Audio: dispositivos, volumen, apps, dispositivo por defecto
  - `Quickshell.Services.Mpris` → controles multimedia de Windows (GSMTC): título, artista, portada, progreso, play/pausa/siguiente
  - `Quickshell.Services.Notifications` → notificaciones de Windows + `notify-send`
  - `Quickshell.Services.SystemTray` → iconos de la bandeja de Windows (ver Bandeja)
  - `Quickshell.Windows` (nuevo): red con la API Wi-Fi nativa y el Network List Manager
- [x] Sustitutos QML provisionales, con la API correcta y vacíos: Bluetooth, UPower, Polkit, PAM, Kirigami.Icon y resaltado de código.
- [x] `/proc` virtual: CPU, RAM, swap, uptime y nombre del sistema reales.
- [x] Índice de apps del Menú Inicio y de la Store, con iconos del tema Breeze Plus y respaldo al icono real del `.exe`.
- [x] `ii-shim.exe`: equivalentes de los comandos Linux que ii llama (`qalc`, `xdg-open`, `notify-send`, `playerctl`, `wpctl`, `pidof`, `pkill`, `loginctl`…).
- [x] Overlay de ii (`overlay/ii/`): `HyprlandData` desde la lista de ventanas de Windows; menú de sesión con los comandos de Windows.
- [x] Tipografías del dotfile, cargadas solo para la shell, sin instalarse en el sistema.
- [x] Colores Material 3 desde el wallpaper (`tools/colors/gen_colors.py`, mismo algoritmo que ii).

### Notificaciones (cómo funciona)
- La shell lee las notificaciones de Windows con la API oficial `UserNotificationListener`, sin permisos de administrador.
- Si cierras una en ii, también desaparece del centro de notificaciones de Windows.
- Para que no salgan dos popups (el de Windows y el de ii), `ii-host` apaga el interruptor "Mostrar banners de notificación" de cada app (en `HKCU`, por usuario) mientras ii está corriendo.
  - Antes de tocar nada guarda el valor original en `%LOCALAPPDATA%\ii-windows\banners.txt`.
  - Al salir, con el atajo de pánico, si `ii-host` muere (guardián) o con `ii-rescue`, deja cada app como estaba. Las apps donde tú ya los tenías apagados siguen apagadas.
  - Comprobado en Sandbox: 14/14 (`tests\test-banners.ps1`).
  - Si prefieres ver también los banners de Windows: `ii-host --keep-banners`.

### Bandeja del sistema (cómo funciona)
- Las apps registran sus iconos buscando la ventana de bandeja de Windows. La shell crea una propia que va primero y **le reenvía todo a Explorer**, así que Explorer siempre conserva todos los iconos. Si ii se cierra, no se pierde nada.
- Clic izquierdo = clic normal en el icono. Clic derecho = el menú propio de la app (el mismo que en Windows). Clic central = doble clic.
- Si Explorer se reinicia, la bandeja de ii se aparta unos segundos para no interferir y luego vuelve (probado: si no se apartaba, la barra de Windows quedaba en blanco).

### Arreglo de seguridad: autoocultar de la barra de tareas
- Se encontró en el Sandbox: Windows guarda tarde el estado de la barra, y un reinicio de Explorer podía dejarla en "ocultar automáticamente" aunque ya se hubiera restaurado. Ahora se guarda también en el registro al restaurar y antes de cerrar sesión. Probado con autoocultar apagado y encendido (tu caso): 14/14.

## Pendiente (en este orden)
1. Servicios que faltan (no se pueden probar ahora: tu adaptador Bluetooth no está conectado y tu PC no tiene batería ni Wi-Fi):
   - Bluetooth
   - batería y modos de energía
   - brillo: DDC/CI
   - El Wi-Fi está programado (lista, conectar, contraseña, encender/apagar), pero solo se ha probado la parte de cable.
2. Menú de sesión (no apareció en la prueba) y cheatsheet con los atajos de Windows.
3. Tus prioridades: dock, overlays y widgets de escritorio con accesos directos y carpetas reales.
4. Generador de colores en C++ (sin Python), selector de wallpaper (`Imágenes\Wallpapers`), cursor Bibata, colores en Windows y Terminal.
5. Instalador y desinstalador, multimonitor/DPI, reinicio de Explorer y sleep/resume.
6. Optimizar la RAM.

## Cómo probar

### Compilar
```powershell
. C:\Users\Calos\Desktop\ii-windows\tools\dev\vsenv.ps1
cmake --build C:\Users\Calos\Desktop\ii-windows\quickshell\build
cmake --build C:\Users\Calos\Desktop\ii-windows\host\build
pwsh -File C:\Users\Calos\Desktop\ii-windows\tools\dev\deploy.ps1      # quickshell + Qt + fuentes → dist\
pwsh -File C:\Users\Calos\Desktop\ii-windows\tools\dev\stage-ii.ps1    # ii original + overlay → build\ii
```

### En Windows Sandbox (recomendado, no toca tu sesión)
```powershell
cd C:\Users\Calos\Desktop\ii-windows\tools\sandbox
pwsh -File sbx.ps1 start                                    # abre el Sandbox con el agente
pwsh -File sbx.ps1 run tests\test-host.ps1                  # Hito 2: 28 comprobaciones PASS/FAIL
pwsh -File sbx.ps1 run tests\test-banners.ps1               # banners de Windows: 14 comprobaciones
pwsh -File qs.ps1 -Seed -Seconds 10                         # pone colores y wallpaper de prueba
pwsh -File sbx.ps1 run tests\ii-scene.ps1                   # ii + ii-host + app + Win+D → capturas
pwsh -File sbx.ps1 run tests\ii-panels.ps1                  # abre cada panel por su atajo → capturas
pwsh -File sbx.ps1 run tests\ii-launcher.ps1                # búsqueda de apps y calculadora
pwsh -File sbx.ps1 run tests\ii-media.ps1                   # controles multimedia
pwsh -File sbx.ps1 run tests\ii-notifications.ps1           # notify-send + notificación real de Windows
pwsh -File sbx.ps1 run tests\ii-network.ps1                 # red en la barra y los ajustes rápidos
pwsh -File sbx.ps1 run tests\ii-tray.ps1                    # bandeja: iconos, clics y menú nativo
pwsh -File sbx.ps1 run tests\ii-tray-explorer.ps1           # bandeja + reinicio de Explorer
pwsh -File sbx.ps1 run tests\persist-both.ps1               # autoocultar se restaura bien (2 configuraciones)
```
Las capturas quedan en `C:\Users\Calos\sbx-xchg\outbox\`.

### Si algo sale mal (en cualquier equipo)
- **Ctrl+Alt+Shift+R** mientras corre `ii-host`.
- O doble clic en `tools\rescue\ii-rescue.cmd`.
- O Ctrl+Shift+Esc → Archivo → Ejecutar nueva tarea → `powershell -ExecutionPolicy Bypass -File "C:\Users\Calos\Desktop\ii-windows\tools\rescue\ii-rescue.ps1" -RestartExplorer`.

## Problemas conocidos
- **RAM:** ~500–600 MB en el Sandbox (wallpaper 3840×2400, ~15 ventanas Qt y fuentes de 15 MB). Pendiente de optimizar: reducir el wallpaper al tamaño de la pantalla y cargar en diferido los paneles cerrados.
- **Notificaciones:** los botones propios de cada notificación de Windows (p. ej. "Responder") no se pueden pulsar desde fuera; ii muestra un botón "Open" que abre la app. La primera notificación de una app nueva puede salir también como banner de Windows (una sola vez).
- **Sustitutos vacíos:** Bluetooth y batería aún no muestran datos.
- **Bandeja:** el menú de ii para fijar/desfijar iconos se cambió por el menú nativo de cada app. Los iconos propios de Explorer (volumen, quitar USB) también aparecen.
- **Sin `ii-host`:** tras reiniciar Explorer, el fondo de ii puede quedar por encima de la barra de Windows. Con `ii-host` (el uso normal) la barra está oculta y no se nota.
- **Python temporal:** los colores se generan con Python (`materialyoucolor`) hasta portarlo a C++.
