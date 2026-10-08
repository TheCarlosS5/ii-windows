# PROGRESS

Port de la interfaz de [Illogical Impulse](https://github.com/end-4/dots-hyprland) (end-4) a Windows 11.
Documentos: [Viabilidad](docs/FEASIBILITY.md) · [Decisiones](docs/DECISIONS.md) · [Relevo y checkpoint](docs/RELEVO-CODEX.md)

## Estado (2026-10-07, relevo a Codex)
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
  - dock con apps fijadas y ventanas abiertas, menú de sesión, cheatsheet y overlay de widgets
  - archivos, carpetas y accesos directos de los Escritorios personal y público, con iconos y miniaturas de Windows
  - un widget de carpeta en el escritorio (Descargas por defecto) con los archivos más recientes; el reloj pasa a la esquina superior derecha para no tapar los iconos

  Faltan Bluetooth, batería y brillo, completar las funciones de escritorio, tematización y empaquetado. El port completo sigue en desarrollo.

Todo lo de esta etapa se ha probado **solo dentro de Windows Sandbox**. En tu sesión real no se ha instalado ni cambiado nada, salvo las herramientas de desarrollo del Hito 1.

## Hecho

### Hito 1: viabilidad
- [x] Inventario del dotfile, licencias (GPL-3 para ii, LGPL-3 para Quickshell) y comparación de rutas.
- [x] Quickshell compilado para Windows (fork en `quickshell/`; avance actual en `codex/desktop-widgets`, checkpoint original en `windows`).

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

### Relevo e integración del escritorio (Codex)
- [x] Leída la sesión importada **Port Illogical Impulse a Windows 11** y conservado el trabajo sin commit de Claude antes de modificarlo.
- [x] Checkpoint local: proyecto `a2cae01`; Quickshell `891e288`. Ambos repositorios tienen la etiqueta `checkpoint/claude-before-codex-2026-10-07` y el desarrollo continúa en `codex/desktop-widgets`.
- [x] `DesktopIcons.qml` conectado al fondo y a `background.widgets.desktopIcons` (`enable`, `iconSize`). El reloj y el clima mantienen sus manejadores; el menú de archivos recibe clics por encima de ellos.
- [x] Escritorio personal obtenido de Windows, incluido un Escritorio redirigido; Escritorio compartido desde `%PUBLIC%\Desktop`. Carpetas primero, archivos ocultos omitidos, actualización al añadir/eliminar archivos.
- [x] Iconos y miniaturas desde Shell, con transparencia conservada. Abrir y copiar nombres con espacios, acentos, `&`, `#` y `%`; ejecutar accesos `.lnk` con sus argumentos; mostrar en carpeta selecciona el archivo real mediante `ii-shim reveal`.
- [x] Prueba `tools/sandbox/tests/ii-desktop.ps1`, con inspección inyectada solo en Sandbox, archivos reales, clics de ratón y capturas del icono/miniatura. Resultados finales abajo.
- [x] Corregida la preparación de `test-banners.ps1`: una Sandbox nueva todavía no registra PowerShell como app de notificaciones. Se prepara ese caso y se comprueba que el rescate actúe con el guardián detenido; el test devuelve error si falla.
- [x] Prueba visual del dock preparada con Explorer: Notepad no está instalado en esta Sandbox. No se cambia el código del dock por esa ausencia.

### Verificación de Codex (2026-10-07)

Fuentes de Quickshell: `a2b7875073a6634c95238b3b0f1d4c4f25a1cce5`. Todo el comportamiento se probó dentro de Windows Sandbox.

| Comprobación | Resultado | Alcance |
| --- | --- | --- |
| Compilación de host y Quickshell | Código 0 | Binarios compilados; última comprobación `ninja: no work to do` en ambos |
| `stage-ii.ps1` | Código 0 | Overlay y parches exactos reproducibles, sin editar upstream |
| `ii-desktop.ps1` | 27/27 | Archivos personales/públicos, alpha, miniatura, clics, menú, ruta literal, `.lnk`, cambios en vivo, activar/desactivar |
| `ii-desktop-host.ps1` | 32/32 | Lo anterior con host; Win+D desde arranque limpio minimiza/restaura Explorer y conserva los píxeles de la miniatura en pantalla |
| `test-host.ps1` | 28/28 | Ocultación, atajos, reinicio de Explorer, guardián, pánico y rescate |
| `test-banners.ps1` | 15/15 | Apps existentes/nuevas, salida limpia, guardián y rescate con backup todavía pendiente |
| `ii-panels.ps1`, dock y overlay | Capturas revisadas | Apertura de búsqueda, menú de sesión, cheatsheet, sidebar derecho y overlay; dock muestra Explorer abierto. No acredita todas las acciones de cada panel |

La prueba del menú detectó primero clics interceptados por el reloj y alpha de fondo 0.1. Tras corregir capas y usar la superficie `colLayer0`, los clics pasan y el alpha es 1 con transparencia desactivada. La prueba de iconos detectó antes esquinas opacas; ahora comprueba alpha 0 en la esquina del icono de carpeta y los píxeles exactos de una miniatura verde.

Evidencia local copiada en `build/verification/2026-10-07-desktop/` (logs, estados JSON y capturas; archivos generados, fuera de Git). El driver `sbx.ps1` imprime el resultado pero no propaga siempre el código de salida del test: revisar también `FAIL`, `desktop failures=0` y `fails: 0`.

### Widget de carpeta (Claude, tras el relevo)
- `FolderWidget.qml`: tarjeta ii arrastrable con los archivos más nuevos de una carpeta real (`background.widgets.folder.path`, vacío = Descargas; `maxItems`). Clic abre, clic derecho muestra en Explorer, el botón abre la carpeta. Se actualiza sola.
- Los widgets del fondo aceptan coordenadas negativas (desde el borde derecho/inferior), así los valores por defecto quedan en una esquina en cualquier pantalla. Reloj: arriba a la derecha, ubicación libre (la ubicación automática de ii necesita un script de Python que Windows no tiene). Carpeta: abajo a la derecha.
- Probado en Sandbox (`tests\ii-folder.ps1`): orden por fecha, tiempos relativos, iconos reales, nombres con acentos y `#`.

### Fondo y colores sin Python
- El selector de fondos de ii (Win+Ctrl+T) funciona: carpetas de Windows, miniaturas reales y, al elegir uno, toda la interfaz cambia a los colores Material 3 del fondo (probado en Sandbox: un fondo naranja recoloreó barra, sidebar y calendario).
- `switchwall` nativo en `ii-shim` con la biblioteca oficial de Google (ver D16): 49 colores en ~130 ms. Los botones de modo claro/oscuro de ii también funcionan.
- Python ya no es necesario para los colores (`tools/colors/gen_colors.py` queda solo como referencia).

### Windows sigue los colores de ii
- Con `ii-host` corriendo, Windows pasa a modo oscuro/claro según ii y toma como color de acento el color del fondo. Al cambiar el fondo o el modo en ii, Windows cambia a los ~2 s.
- Todo se restaura al salir (y con pánico, guardián o `ii-rescue`): probado 8/8 en Sandbox (`tests	est-theme.ps1`). Detalles en D17.

### Instalado en tu PC real (2026-10-08)
- Instalado con el paquete `db033f3` + punto de restauración ("Antes de instalar ii-windows") + copias `.reg` en `%LOCALAPPDATA%\ii-windowsackup61008-050918`.
- Rescate probado en tu PC: restauró barra (autoocultar como lo tenías), iconos, 23 banners y 7 valores de color; Windows quedó igual que antes.
- Arreglado al verlo en tu escritorio:
  - Dock: Windows Terminal salía con un icono "!" y separado de su anclaje (Terminal no marca sus ventanas con su ID de app; ahora se lee del proceso). El anclaje de Edge mostraba el icono de Git (tu PC no tiene Edge en Inicio): anclajes por defecto ahora Explorador y Terminal.
  - `ii-host` creía que Explorer se reiniciaba cada 10-20 s (era el aviso de la bandeja de ii) y volvía a aplicar todo: ahora solo cuenta una barra de Explorer nueva de verdad.

### Instalador
- Paquete: `out\ii-windows-<versión>.zip` (88 MB), creado con `tools\package\make-package.ps1`. Dentro, `install.cmd`: doble clic, pregunta antes de cada paso, solo tu usuario. Detalles en D18.
- Hace: punto de restauración opcional, copia `.reg` de lo que toca, archivos en `%LOCALAPPDATA%\Programs\ii-windows`, cursor Bibata, inicio con Windows, menú Inicio (Iniciar, Rescate, Desinstalar) y entrada en Configuración > Aplicaciones.
- Desinstalar deja Windows exactamente como estaba (probado 15/15 en Sandbox limpio).
- Windows Terminal: aparece el esquema de colores "ii-windows" con la paleta del fondo (elegirlo en la configuración de Terminal).

### Notificaciones (cómo funciona)
- La shell lee las notificaciones de Windows con la API oficial `UserNotificationListener`, sin permisos de administrador.
- Si cierras una en ii, también desaparece del centro de notificaciones de Windows.
- Para que no salgan dos popups (el de Windows y el de ii), `ii-host` apaga el interruptor "Mostrar banners de notificación" de cada app (en `HKCU`, por usuario) mientras ii está corriendo.
  - Antes de tocar nada guarda el valor original en `%LOCALAPPDATA%\ii-windows\banners.txt`.
  - Al salir, con el atajo de pánico, si `ii-host` muere (guardián) o con `ii-rescue`, deja cada app como estaba. Las apps donde tú ya los tenías apagados siguen apagadas.
  - Repetido por Codex en Sandbox: 15/15 (`tools\sandbox\tests\test-banners.ps1`), incluida la preparación efectiva del caso de rescate.
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
2. Completar tus prioridades: menú de escritorio más amplio, manejo de muchos iconos, arrastre y navegación con teclado; profundizar las acciones del dock y overlay. Menú de sesión y cheatsheet ya están implementados; no ejecutar cierre de sesión/apagado en la sesión personal durante las pruebas.
3. Validar Escritorio redirigido/OneDrive, carpetas UNC y varias pantallas con usuarios reales; la prueba de Sandbox usa carpetas locales. La clasificación nativa ya reconoce rutas absolutas UNC, pero no se ha validado un recurso de red extremo a extremo.
4. Uso diario en tu PC real: anotar lo que falle (instalado el 2026-10-08).
5. Multimonitor/DPI y sleep/resume (necesitan hardware real).
6. Optimizar la RAM.

## Cómo probar

### Compilar
```powershell
. C:\Users\Calos\Desktop\ii-windows\tools\dev\vsenv.ps1
pwsh -File C:\Users\Calos\Desktop\ii-windows\tools\dev\fetch_mcu.ps1   # una vez: biblioteca de colores de Google (commit fijo)
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
pwsh -File sbx.ps1 run tests\test-banners.ps1               # banners de Windows: 15 comprobaciones
pwsh -File sbx.ps1 run tests\ii-desktop.ps1 -Timeout 240    # archivos reales, iconos, menú y apertura
pwsh -File sbx.ps1 run tests\ii-desktop-host.ps1 -Timeout 240 # lo anterior + host y Win+D
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
- **Escritorio:** todavía no ofrece arrastrar, renombrar, borrar, navegación de teclado ni el menú completo de Explorer. Muchos iconos pueden quedar fuera del ancho disponible; falta paginación. Una miniatura de un archivo editado sin cambiar su ruta puede conservarse en la caché hasta reiniciar la shell. `%PUBLIC%\Desktop` supone la ubicación pública habitual.
- **Avisos QML heredados:** aparecen valores inicialmente indefinidos en `SystemInfo`, `NotificationPopup`, `WorkspaceModel`, `ConflictKiller`, `BarContent` y `ToolbarTabBar`; faltan traducciones `es_CO` y comandos de Linux. `Qt.btoa(string)` conserva el código heredado y emite aviso de deprecación. La shell sigue funcionando, pero no se considera libre de avisos.
- **Apps en Sandbox:** no están instaladas todas las apps fijadas por defecto (Edge/Terminal); pueden aparecer iconos de respaldo. La prueba del dock usa Explorer, disponible en ese entorno.
