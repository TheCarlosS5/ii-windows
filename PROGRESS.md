# PROGRESS

Port de la interfaz de [Illogical Impulse](https://github.com/end-4/dots-hyprland) (end-4) a Windows 11.
Documentos: [Viabilidad](docs/FEASIBILITY.md) · [Decisiones](docs/DECISIONS.md)

## Estado (2026-10-07, noche)
- ✅ **Hito 1, viabilidad:** prototipos hechos y ruta elegida.
- ✅ **Hito 2, cimientos:** `ii-host`, rescate y atajo de pánico. Probado en Windows Sandbox con 28/28 comprobaciones.
- 🟡 **Hito 3, ii arrancando:** el QML original de ii corre en Windows (en Sandbox). Se ven:
  - la barra
  - el fondo con su reloj
  - el overview con búsqueda
  - las dos sidebars con calendario
  - las esquinas de pantalla
  - las tipografías y los colores Material
  
  Faltan servicios reales, iconos de apps y miniaturas de ventanas.

Todo lo de esta etapa se ha probado **solo dentro de Windows Sandbox**. En tu sesión real no se ha instalado ni cambiado nada, salvo las herramientas de desarrollo del Hito 1.

## Hecho

### Hito 1: viabilidad
- [x] Inventario del dotfile, licencias (GPL-3 para ii, LGPL-3 para Quickshell) y comparación de rutas.
- [x] Quickshell compilado para Windows (fork en `quickshell/`, rama `windows`).

### Hito 2: cimientos (`host/`, `tools/rescue/`)
- [x] `ii-host.exe` (C++, 190 KB, sin dependencias):
  - oculta la barra de tareas en todas las pantallas y la vuelve a ocultar si Explorer se reinicia
  - oculta los iconos del escritorio sin cambiar nada persistente
  - tecla Windows → búsqueda de ii, y atajos Super+… de ii
  - Win+L, Win+R y los atajos que no son de ii siguen siendo de Windows
- [x] Si la shell no corre, la tecla Windows abre el Inicio normal.
- [x] Proceso guardián: si `ii-host` muere, restaura todo solo.
- [x] Atajo de pánico **Ctrl+Alt+Shift+R**: restaura barra de tareas, iconos, autohide y área de trabajo, y sale.
- [x] `tools/rescue/ii-rescue.cmd` / `.ps1`: recuperación sin depender de ningún binario.
- [x] Laboratorio de pruebas en Windows Sandbox (`tools/sandbox/`), controlado por carpeta compartida.

### Hito 3: ii en Windows
- [x] Backend `src/win32`:
  - paneles con anclajes y márgenes
  - zonas exclusivas reales (AppBar)
  - capas: fondo encima del escritorio de Windows y debajo de las apps, Top/Overlay por encima
  - clic-a-través por regiones
  - foco de teclado exclusivo
  - los juegos a pantalla completa apartan la barra; los paneles propios no
- [x] Módulos de compatibilidad (misma API QML que en Linux):
  - `Quickshell.Wayland`: capas, lista real de ventanas, bloqueo → bloqueo de Windows, evitar suspensión
  - `Quickshell.Hyprland`: atajos globales, cerrar al hacer clic fuera, monitores, `dispatch`
  - `Quickshell.Services.Pipewire` → Core Audio: dispositivos, volumen, apps, dispositivo por defecto
- [x] Sustitutos QML provisionales, con la API correcta y vacíos: Mpris, bandeja, notificaciones, Bluetooth, UPower, Polkit, PAM, Kirigami.Icon y resaltado de código.
- [x] Overlay de ii (`overlay/ii/`): `HyprlandData` construido desde la lista de ventanas de Windows.
- [x] Tipografías del dotfile (Google Sans Flex, Material Symbols, JetBrains Mono NF, Readex Pro, Space Grotesk, Rubik). Se cargan solo para la shell, sin instalarse en el sistema.
- [x] Colores Material 3 desde el wallpaper (`tools/colors/gen_colors.py`, mismo algoritmo que ii).

## Pendiente (en este orden)
1. Datos del sistema que ii lee de `/proc` y `/etc` (CPU, RAM, uptime, nombre del sistema), a través de un `/proc` virtual en `FileView`.
2. Iconos de apps (icono real del `.exe` + paquete de iconos) y búsqueda de apps del Menú Inicio y UWP en el launcher.
3. Miniaturas de ventanas en el overview (DWM), y activar ventanas al hacer clic.
4. Servicios reales:
   - media: GSMTC
   - red: WlanAPI
   - Bluetooth
   - brillo: DDC/CI
   - notificaciones
   - bandeja del sistema
   - batería y modos de energía
5. Win+D gestionado por `ii-host` (hoy esconde el fondo de ii).
6. Menú de sesión, cheatsheet con los atajos de Windows, dock, overlays y widgets de escritorio.
7. Generador de colores en C++ (sin Python), selector de wallpaper, cursor Bibata, colores en Windows y Terminal.
8. Instalador y desinstalador, multimonitor/DPI, sleep/resume.

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
pwsh -File qs.ps1 -Seed -Seconds 10                         # pone colores y wallpaper de prueba
pwsh -File sbx.ps1 run tests\ii-scene.ps1                   # ii + ii-host + app + Win+D → capturas
pwsh -File sbx.ps1 run tests\ii-panels.ps1                  # abre cada panel por su atajo → capturas
```
Las capturas quedan en `C:\Users\Calos\sbx-xchg\outbox\`.

### Si algo sale mal (en cualquier equipo)
- **Ctrl+Alt+Shift+R** mientras corre `ii-host`.
- O doble clic en `tools\rescue\ii-rescue.cmd`.
- O Ctrl+Shift+Esc → Archivo → Ejecutar nueva tarea → `powershell -ExecutionPolicy Bypass -File "C:\Users\Calos\Desktop\ii-windows\tools\rescue\ii-rescue.ps1" -RestartExplorer`.

## Problemas conocidos
- **Win+D:** muestra el escritorio de Windows por encima del fondo de ii. Lo resolverá `ii-host` haciendo su propio "mostrar escritorio".
- **RAM:** ~500–600 MB en el Sandbox (wallpaper 3840×2400, ~15 ventanas Qt y fuentes de 15 MB). Pendiente de optimizar: reducir el wallpaper al tamaño de la pantalla y cargar en diferido los paneles cerrados.
- **Sustitutos vacíos:** media, notificaciones, bandeja, Bluetooth y red aún no muestran datos.
- **Python temporal:** los colores se generan con Python (`materialyoucolor`) hasta portarlo a C++.
