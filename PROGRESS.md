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
- Todo se restaura al salir (y con pánico, guardián o `ii-rescue`): probado 8/8 en Sandbox (`tests\test-theme.ps1`). Detalles en D17.

### Instalado en tu PC real (2026-10-08)
- Instalado con el paquete `db033f3` + punto de restauración ("Antes de instalar ii-windows") + copias `.reg` en `%LOCALAPPDATA%\ii-windows\backup\20261008-050918`.
- Rescate probado en tu PC: restauró barra (autoocultar como lo tenías), iconos, 23 banners y 7 valores de color; Windows quedó igual que antes.
- Arreglado al verlo en tu escritorio:
  - Dock: Windows Terminal salía con un icono "!" y separado de su anclaje (Terminal no marca sus ventanas con su ID de app; ahora se lee del proceso). El anclaje de Edge mostraba el icono de Git (tu PC no tiene Edge en Inicio): anclajes por defecto ahora Explorador y Terminal.
  - `ii-host` creía que Explorer se reiniciaba cada 10-20 s (era el aviso de la bandeja de ii) y volvía a aplicar todo: ahora solo cuenta una barra de Explorer nueva de verdad.

### Ventanas maximizadas debajo de la barra (arreglado 2026-10-08)
- La barra se registraba ante Windows pero nunca reservaba su franja: Windows le entrega los datos de "reservar espacio" a la ventana de bandeja que encuentra primero, que es la de ii, y dentro del mismo proceso usa un puntero que Explorer no puede leer. Ahora la barra le habla directamente a Explorer con el mismo formato que usa cualquier otra app (capturado en `tests\appbar-capture2.ps1`), y si algo falla usa la función oficial.
- Vigilante cada 3 s: si Explorer se reinicia o pierde la reserva, la barra se vuelve a registrar.
- La bandeja de ii ya no hace esperar a las apps (las suelta antes de pasarle el icono a Explorer) y nunca espera más de 2 s a Explorer. Un intento con 15 s de espera colgó Explorer en tu PC (Windows lo reinició solo, 05:29); por eso se descartó.
- Probado en Sandbox (`tests\ii-appbar.ps1`): la barra reserva 40 px, Explorer responde siempre en ≤5 ms, la reserva vuelve tras reiniciar Explorer, otra app con su propia barra sigue funcionando y el rescate libera el espacio. En tu PC: el área útil empieza en y=40.

### Escritorio: menú de clic derecho y widgets nuevos (instalado en tu PC 2026-10-08 06:43)
- Clic derecho en el escritorio (o sobre un widget) abre el menú de ii: cambiar fondo, fondo aleatorio (de tu carpeta de fondos; si está vacía, uno de Konachan), aleatorio de Konachan, activar/desactivar widgets (reloj, música, foto, archivos recientes, clima, iconos), widgets superpuestos, configuración de ii y de pantalla. Un widget activado desde el menú aparece donde hiciste clic. Los iconos conservan su propio menú.
- Widget de música: la tarjeta del reproductor de ii en el escritorio (debajo del reloj); se oculta si no suena nada.
- Widget de foto (Codex): una imagen tuya (o https, los gif se mueven) en cualquier parte; rueda del ratón para el tamaño, clic derecho para cambiarla o quitarla.
- Fondo aleatorio de Konachan y osu! sin bash/curl (Codex): Konachan funciona; osu! responde 403 (Cloudflare) también en Linux.
- ii en español: Windows dice es_CO y ii solo trae es_MX; ahora se usa el mismo idioma aunque cambie la región. Textos nuevos del port traducidos.
- Descargas sin bash/curl/jq (Codex): `ii-shim fetch` y `ii-shim weather`. Funcionan el clima (widget y barra), la carátula del reproductor, la imagen flotante del overlay y los favicons. 46/46 pruebas con internet.
- Clima: el GPS queda apagado por defecto. En Windows el "GPS" es el servicio de ubicación, y Qt pedía permiso de ubicación en cuanto existía el componente, aunque no se usara. Sin GPS, wttr.in ubica por IP o usa la ciudad de la configuración.
- Barra: muestra el nombre de la app ("Terminal") en vez de su ID técnico.
- Pruebas en Sandbox: `ii-desktop-menu.ps1`, `ii-photo.ps1` (menú, foto, rueda, selector de archivos), `ii-net-widgets.ps1` (clima, música, overlay).

### Vista general (tecla Windows) y dock (instalado en tu PC 2026-10-08 07:38)
- El problema: ii dibuja cada ventana en su posición real dentro de 10 escritorios en miniatura. En Hyprland las ventanas no se tapan; en Windows se solapan o están maximizadas, así que la de encima ocultaba al resto. Además, arrastrar a otro escritorio no hacía nada: Windows no tiene los workspaces de Hyprland, y los escritorios virtuales de Windows solo se pueden mover con APIs no documentadas.
- Ahora: un solo panel grande (55 % de la pantalla) con todas las ventanas en cuadrícula, la más reciente primero. Clic la trae al frente, clic central la cierra. Sin arrastrar.
- ii actual usa la sintaxis nueva de Hyprland (`hl.dsp.focus(...)`) y el port solo entendía la vieja: por eso el clic en una ventana de la vista general no hacía nada. Arreglado.
- Pausa al abrir: 26 ms en tu PC; la primera apertura en Sandbox, ~100 ms (Windows crea la ventana).
- Dock: la vista previa al pasar el ratón ya se ve (título, × para cerrar y la ventana en vivo). Clic derecho abre un menú como el de la barra de Windows: la app, nueva ventana, anclar/desanclar, cerrar ventana(s). Las ventanas del Explorador se agrupan con su icono anclado.
- Pruebas en Sandbox: `ii-overview-dock.ps1`, `ii-overview-perf.ps1`.
- Pendiente: las ventanas minimizadas salen pequeñas y en negro en la vista general (DWM no da imagen de una ventana minimizada).

### Panel lateral derecho (instalado en tu PC 2026-10-08 07:58)
- Inventario completo en `docs/SIDEBAR-WINDOWS.md` (Codex). Cabecera con la edición de Windows; planes de energía con la API documentada; Bluetooth "no disponible" (sin hardware); los botones sin equivalente en Windows (EasyEffects, WARP, selector de color, reconocer música, anti-flashbang) se ocultan en vez de no hacer nada.
- Luz nocturna por gamma de pantalla, con copia de las rampas originales y restauración al salir, pánico, guardián y rescate. En tu PC el driver no deja leer ni cambiar la gamma, así que ii la marca como no disponible y el botón abre la luz nocturna de Windows, que sí funciona.

### Escritorio como el de Explorer (2026-10-08 tarde, probado en Sandbox; aún no instalado en tu PC)
- **Teclado:** un clic en el escritorio le da el teclado, sin que el fondo tape las ventanas. Flechas (con Mayús para ampliar), Inicio/Fin, escribir el principio de un nombre para saltar a él, Enter abre, F2 cambia el nombre, Supr manda a la Papelera (Mayús+Supr borra con la confirmación de Windows), Ctrl+A/C/X/V, Alt+Enter propiedades, tecla Menú o Mayús+F10 abre el menú, Esc limpia.
- **Ratón:** clic, Ctrl+clic, Mayús+clic y rectángulo de selección. Arrastrar mueve los iconos y la posición se guarda (también tras reiniciar). Soltar sobre una carpeta mete los archivos en ella. Los iconos se pueden arrastrar a Explorer, al navegador o a un chat, y se pueden soltar aquí archivos de otras apps.
- **Renombrar en el sitio**, como en Explorer (sin la extensión seleccionada; los accesos directos conservan la suya).
- **Menú de un icono:** Abrir, Abrir con…, Mostrar en la carpeta, Cortar, Copiar, Copiar ruta, Cambiar nombre, Eliminar, Propiedades y **Más opciones** (el menú completo de Explorer, con "Enviar a", compartir, etc.).
- **Menú del escritorio:** Nueva carpeta (aparece donde hiciste clic, lista para escribir su nombre), Pegar, Ordenar por nombre/fecha/tipo, Más opciones (el menú de Explorer: Nuevo ▸ documento, etc.), más lo que ya tenía. Los widgets se activan ahora con botones en dos columnas, para que el menú quepa en pantallas pequeñas. El menú se ve **por encima** de las ventanas abiertas.
- **Muchos archivos:** si no caben, la última celda muestra "+N más" y abre la carpeta del Escritorio.
- Todo lo de archivos lo hace el propio Windows (Papelera, diálogos de conflicto, progreso, propiedades). Detalles en D20.
- Pruebas: `tests\ii-desktop2.ps1` (41/41), y `ii-desktop`, `ii-desktop-host`, `ii-desktop-menu`, `ii-photo` siguen pasando.

### Batería, Bluetooth y brillo (Codex, 2026-10-08 tarde)
- Ya no son sustitutos vacíos: batería y modos de energía, Bluetooth (encender/apagar, buscar, emparejar, conectar) y brillo de pantalla con APIs de Windows. Detalles en `docs/HARDWARE-SERVICES.md` y D21.
- En tu PC: sin batería ii oculta la batería; con el adaptador Bluetooth desconectado dice "No disponible"; tu monitor no permite cambiar el brillo desde Windows (DDC/CI no expuesto, comprobado), así que no aparece ese control. Probado en Sandbox que nada falla cuando no hay hardware; con hardware real aún sin probar.

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

## Pulido tras usarlo en tu PC (2026-10-08 tarde)
Lo que reportaste, y quién lo hace:
- [x] **Al minimizar una app desaparecen la barra y el dock** hasta abrir otra app (Claude).
- [x] **La tecla Windows y Win+Tab** deben abrir la búsqueda / vista general por encima de cualquier app, como en Linux (Claude).
- [x] **Configuración de ii**: quitar los botones de Windows (minimizar, maximizar, cerrar) y dejar solo la X propia de ii, sin perder poder moverla y cambiarle el tamaño (Claude).
- [x] **Escritorios de Windows como espacios de trabajo** (Claude; revisión de código de Codex):
  - Los puntitos de la barra son tus escritorios reales; el punto se marca si ese escritorio tiene ventanas. Sin ventanas, la barra dice "Escritorio 2" (o el nombre que le pusiste en la Vista de tareas).
  - Win+Tab: la vista general muestra las ventanas del escritorio actual y, debajo, una tira con todos tus escritorios (fondo de ii + iconos de sus apps) y **Nuevo escritorio**. Clic cambia de escritorio sin cerrar la vista; la × (o clic central) cierra uno y te deja donde estabas.
  - Win+Ctrl+D / Win+Ctrl+Flechas / Win+Ctrl+F4 de Windows siguen funcionando con ii-host.
  - Cómo: qué escritorio tiene cada ventana, con la API documentada (`IVirtualDesktopManager`); la lista de escritorios, leída (solo lectura) del registro donde Explorer la guarda; cambiar/crear/cerrar, con los atajos de Windows enviados de uno en uno y esperando a que Windows confirme cada paso (si una app con permisos de administrador está delante y Windows los bloquea, ii desiste a los 1,5 s). Nada se envía mientras tienes Win/Ctrl/Alt/Mayús pulsadas.
  - Límite: mover una ventana de otra app a otro escritorio no tiene API pública, así que arrastrar ventanas entre escritorios sigue desactivado (en Windows: clic derecho en la ventana dentro de la Vista de tareas).
  - Probado en Sandbox (`tests\ii-desktops.ps1`): crear, cambiar y cerrar con teclado y con clics, cerrar otro escritorio y volver, sin teclas pegadas ni Inicio abierto; `ii-overview-dock.ps1` sigue pasando.
- [x] **Widget de música** como el de ii en Linux: sin música, el icono de nota con el aro que cambia de forma; con música, la carátula y su fondo (Claude, portando el del dotfile).
- [x] **Bandeja con iconos ocultos**: los que Windows tiene ocultos van detrás de una flechita, como en la barra de Windows (Claude).
- [x] **Dock: destello hacia la derecha** al pasar el ratón rápido por las apps abiertas (Claude).

## Segunda ronda de pulido (2026-10-08 noche)
Lo que reportaste, y qué se hizo:
- [x] **Iconos de Windows repetidos en la bandeja** (audio, red, "aplicaciones usando tu ubicación"): son iconos del propio Explorer. ii ya tiene los suyos, así que se ocultan; solo queda "Quitar hardware de forma segura".
- [x] **Iconos de la bandeja que desaparecían**: Explorer vuelve a poner su barra por encima de la de ii cada vez que cambias de app. ii la recuperaba avisando a *todas* las apps de "barra nueva" cada ~10 s, y cada aviso hacía que todas volvieran a registrar sus iconos. Ahora ii recupera su sitio en silencio, justo después de cada cambio de app, y solo avisa al arrancar.
- [x] **Doble clic en un icono de la bandeja** que abría y cerraba la app: ii mandaba dos clics simples. Ahora manda un doble clic de verdad, como Explorer.
- [x] **Elegir qué iconos van en la barra y cuáles detrás de la flecha**: clic con la rueda en un icono lo cambia de sitio (el tooltip lo dice). Por defecto sigue lo que diga Windows.
- [x] **Panel derecho**: la cabecera mostraba cuadritos blancos (tooltips siempre visibles) y escondía el tiempo encendido. Ahora dice "Encendido 3h, 5m" como ii; "Windows 11 Pro" sale al pasar el ratón.
- [x] **La barra de tareas de Windows se veía al cambiar de escritorio**: ii-host la ocultaba solo *después* de que Windows la mostraba. Ahora además le deja una región vacía: aunque Windows la muestre, no se ve ni se puede pulsar. Se guarda la región original de cada barra en `state.ini` y la restauran la salida, el guardián, el pánico, `--rescue` y `ii-rescue.ps1` (probado en Sandbox, `tests\ii-taskbar-region.ps1`).
- [x] **Dock**: clic en la app que está delante la minimiza; otro clic la devuelve (`tests\ii-dock-minimize.ps1`).
- [x] **Widgets nuevos** (clic derecho en el escritorio > Widgets): Calendario, Tareas y Temporizador (los paneles de ii, los mismos datos que la barra lateral), Recursos (CPU, RAM, swap), Nota (se guarda sola) y Reloj japonés (hora y fecha en kanji, vertical u horizontal). Todos con opciones en Configuración > Fondo.
- [x] **Modo edición del escritorio** (clic derecho > Editar escritorio): cuadrícula de puntos, los widgets se arrastran desde cualquier parte y encajan en la cuadrícula, − / + (o la rueda) cambian su tamaño, el ojo los oculta, "Listo" sale. El tamaño también está en Configuración.
- [x] **Foto gigante**: ahora su tamaño se cambia con − / + en el modo edición o en Configuración.
- [x] **Espectro del widget de música**: `cava` para Windows en `ii-shim` (Codex: captura WASAPI loopback, FFT, 60 fps, ~0,2 % de CPU). Solo corre mientras suena música y el escritorio está visible.
- Nota: el "modo edición con mosaico" y el widget de letras japonesas que recordabas no están en este dotfile de ii; se hicieron nuevos al estilo de ii.

## Pendiente (en este orden)
1. Instalar en tu PC la versión con el escritorio nuevo y usarlo a diario.
2. Probar con hardware real lo que ya está programado: Bluetooth (al conectar tu adaptador), batería (portátil), brillo (monitor con DDC/CI o portátil) y Wi-Fi (solo se ha probado la parte de cable).
3. Profundizar las acciones del dock y del overlay. Menú de sesión y cheatsheet ya están implementados; no ejecutar cierre de sesión/apagado en la sesión personal durante las pruebas.
4. Validar Escritorio redirigido/OneDrive, carpetas UNC y varias pantallas con usuarios reales; la prueba de Sandbox usa carpetas locales. La clasificación nativa ya reconoce rutas absolutas UNC, pero no se ha validado un recurso de red extremo a extremo.
5. Uso diario en tu PC real: anotar lo que falle (instalado el 2026-10-08).
6. Multimonitor/DPI y sleep/resume (necesitan hardware real).
7. Optimizar la RAM.
8. Publicar en GitHub (los dos repositorios y el paquete), cuando tú los crees.

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
- **Hardware sin probar:** Bluetooth, batería y brillo están programados pero solo se han probado sin hardware (ver D21).
- **Bandeja:** el menú de ii para fijar/desfijar iconos se cambió por el menú nativo de cada app. Los iconos propios de Explorer (volumen, quitar USB) también aparecen.
- **Sin `ii-host`:** tras reiniciar Explorer, el fondo de ii puede quedar por encima de la barra de Windows. Con `ii-host` (el uso normal) la barra está oculta y no se nota.
- **Escritorio:** los iconos de varias pantallas comparten la carpeta pero no se reparten entre pantallas. Los archivos cortados no se ven atenuados (Windows no lo informa). Una miniatura de un archivo editado sin cambiar su ruta puede conservarse en la caché hasta reiniciar la shell. `%PUBLIC%\Desktop` supone la ubicación pública habitual.
- **Avisos QML heredados:** aparecen valores inicialmente indefinidos en `SystemInfo`, `NotificationPopup`, `WorkspaceModel`, `ConflictKiller`, `BarContent` y `ToolbarTabBar`; faltan traducciones `es_CO` y comandos de Linux. `Qt.btoa(string)` conserva el código heredado y emite aviso de deprecación. La shell sigue funcionando, pero no se considera libre de avisos.
- **Apps en Sandbox:** no están instaladas todas las apps fijadas por defecto (Edge/Terminal); pueden aparecer iconos de respaldo. La prueba del dock usa Explorer, disponible en ese entorno.
