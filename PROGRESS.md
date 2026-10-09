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

## Hacia la versión 1.0 (2026-10-08 noche)
Revisión completa del inventario de ii en Linux contra el port: **`docs/INVENTARIO-WINDOWS.md`** (Codex: 517 puntos, cada uno con su estado y evidencia). Decisiones: **Waffle** (la versión "estilo Windows" de ii) queda fuera de alcance, no tiene sentido en Windows; lo que es del compositor Hyprland (tiling, gestos, scratchpad, mover ventanas ajenas entre escritorios) tampoco aplica.

Hecho en esta ronda (todo probado en Sandbox):
- [x] **Inicio con Windows rápido**: tarea programada "ii-windows" al entrar (el instalador pide administrador una vez; ii corre como tu usuario normal, sin permisos de administrador). Con `--boot`, ii-host y la shell arrancan con prioridad alta (60 s, luego normal para no robar a los juegos), la barra de tareas se vigila cada 200 ms y una pantalla con **tu fondo de ii** tapa el de Explorer hasta que ii está listo (~10 s). Si no das permiso: la clave `Run` como antes. `tests\ii-boot.ps1`, `test-install.ps1` 17/17.
- [x] **Modo edición**: esquina para cambiar el tamaño arrastrando sin deformar el widget (como una ventana), tamaños de 30 % a 400 % (marcas en 150 % y 200 % en Configuración), el widget que tocas pasa delante. Arreglado: los tamaños no se guardaban salvo en la foto.
- [x] **Sonidos de la interfaz** hechos para el port (`tools/sounds/make_sounds.py`, sin muestras de terceros): abrir/cerrar paneles, cambiar de escritorio, modo edición, soltar un widget; notificaciones opcional (Windows ya suena). Interruptor y volumen en Configuración > General > Sonidos. Callados con un juego a pantalla completa.
- [x] **Portapapeles (Win+V de ii)**: el historial de Windows (el mismo de su Win+V), con texto e imágenes, copiar, pegar, borrar, vaciar, y "superpaste". `cliphist` de ii-shim. `tests\ii-tools.ps1`.
- [x] **Teclado en pantalla** (Win+K): `ydotool` de ii-shim escribe de verdad (teclas, mayúsculas, texto con acentos).
- [x] **Claves de API** (chat de IA): `secret-tool` de ii-shim, cifradas con DPAPI para tu usuario.
- [x] **Emojis** (Win+. y `:` en la búsqueda).
- [x] **Pantalla de bienvenida** en el primer arranque (idioma, barra, estilo, fondo), sin los botones de Windows.
- [x] **Indicador de distribución de teclado** en la barra (si tienes más de un idioma de teclado), sigue a la app que tienes delante. `tests\ii-kblayout.ps1`.
- [x] **Win+Ctrl+R** reinicia ii (como Ctrl+Super+R en Linux).
- [x] `/konachanwallpaper`, descarga de ilustraciones de la galería y suspensión por batería crítica sin bash/curl.
- [x] **Vigilante de la shell** (tras una pantalla negra en tu PC: la shell se colgó al cargar y ii-host mantenía oculta la barra de Windows). Si la shell no muestra su fondo en 90 s, o deja de responder 20 s, ii-host la reinicia; tras 3 intentos devuelve la barra y el escritorio de Windows con un aviso. No cuenta mientras hay un juego a pantalla completa delante. `tests\ii-watchdog.ps1` 3/3, `test-host.ps1` sin fallos.

## 0.1.1 (2026-10-09, instalada en tu PC)

- **Paneles que se abrían al escribir** (arreglado): si ii-host perdía el aviso de que soltaste la
  tecla Windows (cambio de escritorio virtual, pantalla segura, una llamada del hook saltada), seguía
  creyendo que estaba apretada y cada letra contaba como Win+letra (`n` abría el panel derecho, `a`/`o`
  el izquierdo). Ahora el hook comprueba el estado real de la tecla. Prueba reproducible:
  `tools/sandbox/tests/ii-stale-win.ps1` (0.1.0: de "nota" llega "t"; 0.1.1: llega "nota").
- **fastfetch** con el logo de ii (`extras/fastfetch`, fastfetch 2.69.0 MIT): opcional al instalar;
  su carpeta va al final del PATH de usuario (manda el fastfetch que ya tengas) y el desinstalador
  devuelve el PATH exacto.
- **Reportar un problema**: acceso en el menú Inicio que guarda un diagnóstico sin tu nombre de usuario
  ni el del PC y abre el formulario de GitHub (`.github/ISSUE_TEMPLATE`, español e inglés).
- Prueba de instalación en Sandbox ampliada (fastfetch, PATH, reporte): 0 fallos.

## 0.1.2 (2026-10-09, instalada en tu PC y publicada)
- **Arranque de ~25–30 s a ~5 s en tu PC.** Quickshell tardaba 19 s en escanear la config:
  - guardaba las carpetas ya vistas como una lista de `QDir`;
  - en Windows, cada comparación de `QDir` consulta el disco;
  - con 590 archivos eso son decenas de miles de consultas, y Kaspersky las hace aún más lentas.
  - Ahora es un conjunto de rutas: 0,2 s.
- **QML compilado guardado entre arranques.** La config se carga desde una copia en archivos reales (`src/core/qmltree.cpp`), así Qt reutiliza lo compilado (668 archivos). Con `QS_NO_QMLTREE=1` se vuelve al modo anterior. Prueba: `tools/sandbox/tests/ii-startup.ps1`.
- Todos los arreglos P0 de la auditoría (abajo).
- `test-install.ps1`: 0 fallos.

## 0.1.3 (en curso, 2026-10-09 tarde; trabajo autónomo mientras viajas)
- **Escritorios como en Arch:**
  - `ii-shim vdesk` usa la interfaz interna de Explorer (la de la Vista de tareas). Solo funciona en Windows 11 24H2 o posterior; si no, no hace nada y quedan los atajos de antes.
  - Con ella: ir a un escritorio de golpe, cerrar uno sin visitarlo y mover ventanas de otras apps.
  - Comprobado en tu PC (25H2) solo con consultas de lectura.
  - La barra vuelve a los 10 espacios de ii.
  - Win+Mayús+número mueve la ventana de delante a ese escritorio.
  - En la vista general, una ventana arrastrada sobre un escritorio de la tira se mueve allí.
  - El último escritorio, si lo dejas vacío, se quita solo: `services/DesktopCleanup.qml`, opción `bar.workspaces.removeEmptyDesktops`.
- **Bloqueo (opción A):**
  - "Bloquear" en ii hace la animación de ii y luego el bloqueo de Windows.
  - Win+L, la inactividad o la tapa ponen a ii en su estado bloqueado por debajo.
  - Al desbloquear, ii sale con su animación. Antes nadie reseteaba ese estado tras desbloquear Windows.
- **Animaciones:** las laterales se deslizan desde su borde al abrir y al cerrar, y la vista general aparece con un pequeño zoom (`tools/port/patch_ii_anim.py`).
- **Configuración** (Codex, `tools/port/patch_ii_settings.py`): se ocultan las opciones que no hacen nada en Windows.
- **Arranque y consumo:**
  - Pantalla de carga siempre que arranca ii, con indicador y "Cargando ii…", o "Preparando ii por primera vez…".
  - ii-host lanza la shell antes.
  - ii y ii-host quedan fuera del ahorro de energía de Windows (EcoQoS).
  - El instalador pide la GPU de ahorro de energía para la shell.
  - El cursor se vigila por eventos en lugar de cada 16 ms.
  - Fuera las fuentes sin uso (10 MB).
- **Corrección a la auditoría:** el fondo **ya** se cargaba al tamaño de la pantalla (`StyledImage` pone `sourceSize`).
- **IA del panel izquierdo (Codex, revisado):**
  - `ii-shim ai-request` hace POST por WinHTTP con respuesta en streaming, también a `http://localhost` para Ollama. La clave nunca se escribe en disco: se expande desde una variable de entorno.
  - `ii-shim ls` sustituye a `ls -1` para los prompts y chats guardados.
  - `tools/port/patch_ii_ai.py` cambia el script de bash+curl por esa petición. Los adjuntos todavía no funcionan en Windows y lo avisa en el chat.
  - Probada contra un servidor local; no hubo llamadas reales a APIs.
- **Terminal (Codex, revisado):**
  - Dos perfiles en el fragmento de Windows Terminal, "ii · PowerShell" e "ii · CMD", con fastfetch y el esquema ii-windows.
  - El instalador pone JetBrains Mono Nerd Font para tu usuario (opcional y reversible).
  - El desinstalador borra el fragmento, que antes se quedaba en disco.
- **Pruebas en Sandbox:**
  - `ii-p0` 25/25.
  - `ii-desktop2` sin fallos (sus 5 fallos eran de la prueba: la bienvenida del primer arranque tapaba el escritorio).
  - `test-host` sin fallos.
  - `ii-startup`: QML en 0,9 s con caché.
  - `ii-desktops-direct` 9/9. Mover ventanas con `vdesk` funciona; en el Sandbox no se pudo poner delante la ventana de prueba para probar Win+Mayús+número con el teclado real.
  - `ii-splash`: la pantalla de carga sale y se va sola.
- **Errores míos atrapados por las pruebas:** `Session.qml` sin `import QtQuick` impedía cargar toda la config; `StandardPaths` sin `import QtCore` en Ai.qml.
- **Pendiente:**
  - la imagen de la pantalla de bloqueo de Windows con el fondo de ii (opción A completa);
  - respetar "No molestar" de Windows;
  - límite de fps;
  - Wallpaper Engine y el actualizador (pedidos).

## Pedidos para más adelante
- **Wallpaper Engine.** Muchos usuarios de Windows lo tienen.
  - Al instalar ii, los fondos PNG con transparencia dejaban ver el fondo animado de Wallpaper Engine, y esa combinación quedaba bien.
  - Idea: detectar Wallpaper Engine (y Lively) y ofrecer un modo "fondo de ii transparente". Las capas de ii (widgets, iconos, reloj) irían sobre el fondo animado sin taparlo, y los colores Material saldrían de una captura del fondo animado.
  - Cuidado:
    - ii y ellos pelean por la capa del escritorio (WorkerW);
    - hay que pausar el fondo animado con juegos, como ya hace ii.
- **Actualizador oficial.**
  - Un aviso de "hay una versión nueva" cuando se publique en GitHub.
  - La actualización bajaría solo lo que cambió (parches: QML y ejecutables modificados) en vez del paquete de 100 MB.
  - Antes de aplicar, rescate y copia; si algo falla, se vuelve atrás.
  - Las descargas firmadas o verificadas con hash.

## Auditoría 2026-10-09: velocidad, consumo y cosas que rompen ii (solo plan, nada implementado)

Fuentes de esta auditoría: tu instalación real (logs, procesos, ventanas, memoria), el código (`host/`, el fork `quickshell/src/win32`, el overlay y los parches) y una prueba en vivo de las APIs del panel izquierdo. Cada punto indica cómo se sabe:
- **C**: confirmado en el código o medido.
- **P**: probable; hay que comprobarlo en un portátil.
- **T**: sin probar.

### Lo que se midió en tu PC
| Qué | Resultado | Qué significa |
| --- | --- | --- |
| Arranque al encender | 22–30 s hasta "shell lista" (logs del 08-oct 21:32 y 21:33, 09-oct 11:30). Reparto del 09-oct: ~1 s en abrir quickshell y sus DLL, 0,7 s en fuentes, **~25 s sin ningún mensaje** (entre "fuentes cargadas" y "atajos listos") y ~3 s en primeros fotogramas y servicios | Casi todo es cargar y compilar el QML (causa 1). Confirmarlo con una traza antes de tocar nada |
| Caché de QML | `%LOCALAPPDATA%\quickshell\cache\qmlcache` tiene 16 archivos (76 KB), todos del 08-oct 05:10. ii tiene 607 QML (2,2 MB) | ii se compila entera en **cada** arranque, no solo el primero |
| RAM de quickshell | 1.300 MB privados y 909 MB en uso tras 35 min; 150 hilos, 2.494 handles | En un portátil de 8 GB es una sexta parte de la RAM |
| GPU de quickshell | 353 MB dedicados + 96 MB compartidos; el motor 3D al **~8 % sin tocar nada** | El fondo se redibuja sin parar (causa 6) |
| CPU en reposo | ~11 % de un núcleo, con **dos procesos `cava`** a la vez | Dos capturas de audio con FFT a 60 fps |
| Ventanas de la shell | 8 visibles y 19 ocultas (13 `_q_titlebar` de Qt, sidebars, overview…) | Cada ventana tiene su propio dispositivo D3D, sus texturas y su caché de letras |
| Fuentes | 42 MB cargadas al iniciar. *Material Symbols Outlined* (10 MB) y *Rubik* no aparecen en ningún QML | RAM sin uso |
| Tu config | Reloj japonés con `widgetScale: 1.1` y posición `x: 39.394, y: 55.197`. Otro widget en `1649.73, 47.716` con escala 1.3 | Explica lo borroso (causa 5) |
| APIs del panel izquierdo (probadas hoy) | Gelbooru **401** (ahora exige clave de API). Danbooru **403** con un User-Agent de navegador como el que manda ii, **200** con uno propio. Zerochan **500** con JSON mal formado. yande.re, Konachan y waifu.im **200**. Alcy 200 con etiqueta, página HTML sin etiqueta | Ver P0 |
| fastfetch | 467 ms la primera vez, 62 ms después | Bien para la terminal |

**Por qué a ti te va bien y a tus amigos no:**
- Tu PC es un escritorio (Ryzen 5 5500GT): 1080p a 75 Hz, escala 100 %, sin batería, y con *Mem Reduct* recortando memoria.
- Un portátil gamer típico es otra cosa:
  - pantalla 1440p–1600p a 144–240 Hz, con escala 125–150 %;
  - gráfica híbrida (Intel/AMD + NVIDIA) y modo batería;
  - núcleos de eficiencia y antivirus preinstalado.
- ii hoy redibuja pantallas completas a la frecuencia del monitor. Allí eso cuesta de 3 a 6 veces más.

### Causas encontradas
1. **Sin caché de QML (C).**
   - Quickshell sirve el QML con su esquema `qs:`, y Qt solo guarda compilados los archivos `file:`. El fork lo dice en `src/launch/launch.cpp`: "The qml engine currently refuses to cache non file (qsintercept) paths".
   - Cada archivo pasa además por la capa de red de Qt, y el antivirus lo escanea al leerlo.
2. **ii-host arranca la shell al final (C, `host/src/main.cpp`).** Antes lanza el guardián, la luz nocturna (lee con GDI la gamma de cada pantalla), los banners, el tema y el gancho de teclado. En tu PC son 0,1 s; en portátiles con dos GPU puede ser más.
3. **Todo se dibuja en el hilo principal (C, `src/win32/init.cpp` pone `QSG_RENDER_LOOP=basic`).** Mientras una ventana se dibuja, ese hilo no atiende ratón, teclado ni temporizadores. Con varias ventanas animándose y una GPU justa salen tirones.
4. **Popups que crean una ventana nueva al pasar el ratón (C).**
   - `bar/StyledPopup.qml` (recursos, reloj, batería, clima) y `PopupToolTip` (bandeja, aviso de la rueda) crean una ventana nativa al entrar el ratón y la destruyen al salir.
   - Cada vez hay que crear dispositivo D3D, swapchain y primer fotograma. Es la "pausa por pasada" de los portátiles.
5. **Widgets borrosos, tres causas (C).**
   - El tamaño del widget se aplica con `scale:`, y el texto de ii es `Text.NativeRendering`: se dibuja a tamaño 1 y después se estira.
   - Al arrastrar fuera del modo edición la posición se guarda con decimales (`saveDrop` solo redondea en modo edición), y el texto cae entre píxeles.
   - El reloj japonés usa `Text.Raised`, que dibuja una copia desplazada 1 px: se ve doble.
6. **El fondo se redibuja sin parar (C).**
   - El widget de música en reposo tiene una `RotationAnimation` infinita; con música, `cava` va a 60 fps.
   - Cualquier cambio en el fondo redibuja la pantalla entera (1920×1080, o 2560×1600 en un portátil), aunque una ventana maximizada lo tape.
   - El panel multimedia lanza además su propio `cava`.
7. **El cursor se consulta cada 16 ms (C, `InputRegions` en `native.cpp`).** Siempre hay una ventana con zona de clic (la barra, el dock), así que un temporizador de precisión despierta la CPU 60 veces por segundo para decidir si el clic atraviesa. Así un portátil no descansa nunca.
8. **El fondo se carga a resolución completa (C).** `Background.qml` no pone `sourceSize`. Una imagen 4K ocupa ~36 MB de RAM, más su textura, aunque la pantalla sea 1080p.
9. **Paneles cargados aunque estén cerrados (C).** El panel izquierdo (IA, booru, traductor) se crea al arrancar (`active: true`). Las ventanas ocultas conservan sus recursos de GPU.

### Plan por prioridad

#### P0. Errores que rompen o asustan (rápidos de arreglar)
> **Hecho el 2026-10-09 y probado en Sandbox (aún no instalado en tu PC).** `tools/sandbox/tests/ii-p0.ps1`: 25/25. Siguen pasando `test-host.ps1`, `ii-stale-win.ps1` e `ii-desktops.ps1`.
> - **Alt+F4 en el escritorio:** abre el menú de sesión de ii y el fondo sigue. En el resto de ventanas de ii, Alt+F4 no hace nada.
> - **Escritorios:**
>   - La rueda de la barra ya no crea escritorios.
>   - Win+1…0 cambia de escritorio. Si no existe, crea **uno** solo.
>   - Win+Mayús/Ctrl/Alt+número ya no abren apps de la barra oculta.
> - **Atajos:**
>   - Win+Q cierra la ventana de delante; en el escritorio no cierra nada.
>   - Win+S abre la búsqueda de ii.
>   - Win+W abre el panel izquierdo y Win+Alt+D el derecho.
>   - Win+T queda bloqueado.
>   - La cheatsheet ya los muestra.
> - **Batería:** la suspensión automática viene apagada. Si la activas, exige 1 minuto seguido con batería, avisa antes y nunca actúa con el cargador puesto. Cada suspensión queda anotada en `host.log` con el motivo.
> - **Panel izquierdo:**
>   - Gelbooru: campos `apiKey`/`userId` y un mensaje que explica la clave.
>   - Danbooru/Konachan: User-Agent propio.
>   - Zerochan: lee su JSON roto y pide las miniaturas en JPG (Qt no abre AVIF en Windows).
>   - Alcy: etiqueta por defecto.
>   - Mensajes según el error: 401/403/429/sin conexión.
> - **Widgets:**
>   - El reloj japonés escala sus fuentes (nítido a cualquier tamaño) y usa una sombra suave.
>   - Las posiciones se guardan en píxeles enteros, también la capa de widgets.
>   - Para que los demás widgets escalen igual, basta con `scalesContent: true`.
> - **Popups de la barra:** la ventana se crea una vez y se reutiliza 20 s (comprobado: el mismo identificador de ventana en la siguiente pasada). Los tooltips de la bandeja, igual durante 15 s.
> - **Escritorio tapado:** `services/DesktopCover.qml`. Con una app maximizada delante se paran el giro del widget de música, su espectro y el reloj japonés. El `cava` del widget no corre mientras el panel multimedia tiene el suyo.
> - **Fallo encontrado en la prueba y corregido:** Qt entrega el Alt+F4 de la cola de mensajes sin dónde guardar la respuesta, y escribir ahí cerraba la shell. Ahora se comprueba antes.
> - **Pendiente de P0:**
>   - el reloj de ii (CookieClock) y los demás widgets siguen escalando con `scale`;
>   - un solo `cava` compartido de verdad;
>   - campos de Gelbooru en la pantalla de Configuración (hoy van en `config.json`).
- [x] **Alt+F4 sobre el escritorio cierra el fondo (C).** El fork no intercepta `WM_CLOSE`/`SC_CLOSE`, y el fondo recibe el foco desde que tiene iconos.
  - Ignorar el cierre en todas las ventanas de la shell, dentro de `NativeEventRouter`: fondo, barra, dock, overview, sidebars, OSD y selector de región.
  - Alt+F4 con el escritorio delante abre el menú de sesión de ii, igual que Windows muestra "Apagar Windows". Lo mismo si delante está el escritorio de Explorer (Progman), que hoy abre el diálogo clásico.
  - Alt+F4 en las apps normales sigue igual.
- [x] **La rueda en la barra crea escritorios (C).** `bar/Workspaces.qml` manda `r+1`, y `focusWorkspace` (`compat/hyprland.cpp`) crea uno nuevo si ya estás en el último.
  - La rueda solo recorre los escritorios que existen: para en el último o da la vuelta.
  - Solo se crea con una acción explícita: "Nuevo escritorio", Win+Ctrl+D o Win+número (P2).
- [x] **Autosuspensión por batería: causa probable de "el portátil se apaga al terminar la instalación" (P).**
  - Por qué puede pasar:
    - ii trae `battery.automaticSuspend: true` (al 3 %), y en Windows eso llama a `SetSuspendState`.
    - Solo cuenta como "cargando" si Windows dice *Charging*. Enchufado pero lleno, o con limitador de carga (ASUS, Lenovo, MSI), cuenta como "no cargando".
    - Basta una lectura falsa de 0 % al arrancar o mientras se instalan drivers.
    - En portátiles con *Modern Standby* puede acabar en hibernación: el equipo parece apagarse, y al encenderlo aparece ii ya cargado.
  - Plan:
    - En Windows, desactivarla por defecto (Windows ya tiene su propia "acción de batería crítica").
    - Si el usuario la activa: nunca con el cargador conectado, solo tras varias lecturas seguidas durante 60 s, con un aviso cancelable de 30 s y una línea en `host.log`.
  - Cómo confirmarlo en el portátil de tu amigo: `Get-WinEvent -FilterHashtable @{LogName='System'; Id=42,107,1074,41,6008} -MaxEvents 20`. El evento 42 es la entrada en suspensión, con el motivo; el 1074 dice qué proceso pidió apagar. Añadir esos eventos a "Reportar un problema".
- [x] **Atajos de Windows que muestran su barra o su búsqueda (C: no están en la tabla de `host/src/keyboard.cpp`):**
  - Win+Q y Win+S abren la búsqueda de Windows.
    - Win+Q pasa a cerrar la ventana activa, como Super+Q en Arch. Manda `SC_CLOSE`, igual que Alt+F4: la app puede preguntar si guardas. Nunca se aplica a ventanas de ii, y Alt+F4 sigue igual.
    - Win+S abre la búsqueda de ii.
  - Win+1…0 abren las apps ancladas de la barra oculta. Pasan a cambiar de escritorio (P2).
  - Win+Mayús/Ctrl/Alt+número abren una instancia nueva, la última ventana o la lista de saltos de la barra oculta. Win+Mayús+número pasa a mover la ventana a ese escritorio (P2); los demás se bloquean.
  - Win+T y Win+B dan el foco a la barra o a la bandeja ocultas, y el teclado "desaparece": se bloquean.
  - Win+Alt+D abre el calendario de la barra de Windows: abrirá el de ii.
  - Win+W abre los Widgets de Windows: abrirá el panel izquierdo de ii.
  - Win+X (menú de enlaces rápidos) es útil y se deja.
  - Actualizar la cheatsheet (`overlay/ii/services/HyprlandKeybinds.qml`) con todo esto.
- [x] **Proveedores del panel izquierdo:**
  - **Gelbooru:** campos `api_key` y `user_id`, guardados con DPAPI como las claves de IA, y el mensaje "Gelbooru pide una clave de API" en vez del error genérico. Sin clave, sale de la lista.
  - **Danbooru y Konachan:** un User-Agent propio (`ii-windows/<versión> (+github)`), no el de Chrome.
  - **Zerochan:** leer el JSON aunque llegue con un 500 y limpiar la `{` sobrante. Pedir el usuario, porque Zerochan lo exige.
  - **Alcy:** usar la etiqueta `ycy` si no escribes ninguna.
  - Un mensaje propio para cada error (401, 403, sin conexión).
- [x] **Widgets nítidos:**
  - Redondear siempre la posición al guardarla.
  - Cambiar el tamaño multiplicando fuentes y medidas, en lugar de `scale:` (o usar `Text.CurveRendering` en los widgets escalables).
  - Quitar `Text.Raised` del reloj japonés y usar la sombra suave de ii.
  - Poner `smooth: true` en las imágenes escaladas.
- [x] **Popups de la barra sin ventanas nuevas:**
  - Una sola ventana de popup por barra, creada una vez y reutilizada: solo cambian su contenido y su posición.
  - Los tooltips de la bandeja, dentro de la propia ventana de la barra.
- [x] **Fondo quieto cuando no se ve:**
  - Una señal de "escritorio tapado" (ventana maximizada o a pantalla completa en ese monitor) que pausa las animaciones, `cava`, el reloj con segundos y el paralaje.
  - El widget de música en reposo, sin giro infinito.
  - Un solo `cava` para el widget y el panel multimedia, a 30 fps con batería.

#### P1. Arranque y primera ejecución
- [ ] **Caché de QML que funcione (la mejora más grande).**
  - Opción recomendada: el fork escribe a disco una copia espejo de la config, con los `qmldir` que hoy genera en memoria, y la carga con rutas `file:`. Así Qt guarda y reutiliza los `.qmlc`. Para las herramientas ya existe algo parecido (`src/core/toolsupport.cpp`).
  - Objetivo: de ~25 s a menos de 5 s con la caché ya llena.
  - Alternativa mayor: compilar ii por adelantado (qmlcachegen) dentro del paquete.
- [ ] **Precalentar en el instalador.** Último paso: "Preparando ii por primera vez…", con barra de progreso.
  - Arranca la shell oculta una vez, la deja llenar sus cachés y la cierra.
  - Cachés que se llenan: QML, shaders de Qt5Compat (`_qt_QGfxShaderBuilder`), pipelines, índice de apps e iconos.
- [ ] **ii-host lanza la shell lo primero.** Luz nocturna, banners y tema van después, en otro hilo.
- [ ] **Pantalla de carga siempre, no solo con `--boot`.**
  - Muestra el fondo de ii, el logo, un indicador Material y un texto ("Preparando ii por primera vez…" / "Cargando…").
  - La shell le avisa a ii-host de cada etapa (config, barra, fondo), así el progreso es real.
  - Si tarda demasiado: "Esto está tardando más de lo normal", con [Esperar] y [Usar Windows normal].
  - Ocultar la barra y los iconos de Windows solo cuando la barra de ii esté lista o con la pantalla de carga encima. Hoy, sin `--boot`, se ve un escritorio vacío unos 25 s.
- [ ] **Cargar los paneles al abrirlos.**
  - Solo al usarlos: panel izquierdo, ajustes, selector de fondos, cheatsheet, teclado en pantalla, selector de región y traductor de pantalla.
  - `keepRightSidebarLoaded` según la RAM del equipo. Con la caché de QML arreglada, abrir un panel tarda poco.
- [ ] **Paquete más ligero (menos que escanear y que cargar).** Probar cada quitada con test-install.
  - Estilos de Qt Quick Controls que ii no usa (FluentWinUI3 solo lo usa Waffle; también Imagine, Universal, Windows…).
  - `dxcompiler.dll`/`dxil.dll` (13,7 MB, solo sirven para D3D12).
  - Las fuentes sin uso.
- [ ] **Firma de código** (gratis con SignPath para código abierto, o Azure Trusted Signing). Sin firma:
  - *Smart App Control*, activo en algunas instalaciones nuevas de Windows 11, puede bloquear ii por completo.
  - SmartScreen avisa al instalar.
  - Los antivirus desconfían de un programa sin firma que tiene un gancho de teclado.
  - Además: `Unblock-File` del paquete al instalar, para quitar la marca de "descargado de Internet".

#### P1. RAM (objetivo: menos de 350 MB privados en un portátil de 8 GB)
- [ ] **Antes de recortar, medir dónde está la RAM** (VMMap/ETW). Prueba de 24 h con muestreo para encontrar fugas (hoy hay procesos `cava` duplicados).
- [ ] **Fondos a su tamaño.** Wallpaper con `sourceSize` igual a pantalla × zoom × escala, y las miniaturas de fondos guardadas a tamaño miniatura.
- [ ] **Ventanas cerradas que liberan la GPU.** `persistentGraphics`/`persistentSceneGraph` en false desde el fork, o destruir la ventana tras ~30 s cerrada (sidebars, overview, selector de fondos, ajustes).
- [ ] **Fuentes instaladas por usuario**, en lugar de cargarlas en la memoria de la shell. Van en `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + HKCU, sin admin y reversible. Windows las comparte entre programas, y Windows Terminal puede usar JetBrains Mono NF (fastfetch la necesita para sus iconos).
- [ ] **Menos caché sin control.**
  - Recoger la basura de JS tras el arranque y al cerrar los paneles grandes.
  - Poner límites a las cachés de imágenes: booru, carátulas, portapapeles y miniaturas del overview.
- [ ] **Probar `QT_QPA_DISABLE_REDIRECTION_SURFACE=1`.** Qt dibuja con DirectComposition (`dcomp.dll` está cargada), y la superficie de redirección de cada ventana es memoria duplicada. Verificar que la variable existe en Qt 6.12.

#### P1. Fluidez en portátiles
- [ ] **Bucle de render `threaded`** (dibuja fuera del hilo principal).
  - Se descartó porque las animaciones se congelaban en ventanas con click-through.
  - Volver a probarlo sin el cambio de estilo `WS_EX_LAYERED` y con el punto siguiente.
- [ ] **Click-through por eventos.**
  - Cambiar el sondeo de 16 ms por `SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE)` sobre el cursor (`OBJID_CURSOR`): solo trabaja cuando el ratón se mueve.
  - Con el ratón quieto, la CPU duerme.
- [ ] **GPU de bajo consumo.**
  - Registrar `quickshell.exe` como "Ahorro de energía" en las preferencias gráficas de Windows (`HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, reversible), o elegir desde el fork el adaptador que tiene la pantalla.
  - Así ii no despierta la NVIDIA ni copia imágenes entre las dos GPU.
- [ ] **Que Windows no la frene (P).**
  - Sacar quickshell e ii-host del *power throttling*/EcoQoS con `SetProcessInformation(ProcessPowerThrottling)`.
  - ii nunca está en primer plano. Con batería, Windows puede mandarla a los núcleos de eficiencia (Intel de 12.ª generación o posterior). Probarlo en un portátil.
- [ ] **Límite de fps para ii.** En pantallas de 120 Hz o más, animar a 60 (intervalo de swap 2), y siempre con batería. Opción en Configuración.
- [ ] **Modo juego automático.** Con un juego a pantalla completa, además de apartarse, ii **oculta** sus ventanas y para temporizadores y servicios. Hoy se aparta, pero puede seguir dibujando debajo.
- [ ] **Modo batería.** Menos consultas (recursos, clima, red), sin espectro ni paralaje, y `cava` apagado.
- [ ] **Recorte barato.** Cada efecto de Qt5Compat (`OpacityMask`, `GaussianBlur`) cuesta una capa extra.
  - Compilar los shaders HLSL de `ClippingRectangle` para Windows (`qsb --hlsl`) y volver a su recorte, que es más barato.
  - Usar `MultiEffect` en el resto de efectos.

#### P2. Escritorios como en Arch
- [ ] **10 espacios fijos en la barra**, como ii en Linux, en vez de uno por escritorio existente.
  - Hoy `shownCount` es el número de escritorios reales; por eso salían 27 bolitas.
  - Un escritorio vacío se ve igual que uno que no existe. Si hay más de 10, aparece un "+".
- [ ] **Escritorios efímeros** (opción, activada por defecto).
  - Al salir de un escritorio vacío, ii lo quita, como Hyprland borra los workspaces vacíos. El 1 no se quita nunca.
  - Así nunca se acumulan.
- [ ] **Win+1…0 lleva al escritorio N.**
  - Si N no existe, crea **uno** al final y va ahí. Nunca varios de golpe.
  - Win+Mayús+N mueve la ventana activa al escritorio N.
- [ ] **Saltar directo y mover ventanas de otras apps.**
  - Windows no tiene API pública para esto. La única vía es la interfaz no documentada que usan VirtualDesktopAccessor y MScholtes/VirtualDesktop (ambos MIT), y sus GUID cambian entre versiones de Windows.
  - Plan seguro:
    - una tabla por número de build (22621/22631, 26100/26200);
    - las llamadas en un hilo aparte, con tiempo límite;
    - si el build no está en la tabla o algo falla, vuelven los atajos de hoy.
  - Lo que permite:
    - ir del 1 al 7 sin pasar por los intermedios (hoy son 6 animaciones seguidas);
    - Win+Mayús+N;
    - **arrastrar ventanas a otro escritorio en la vista general**, soltando la tarjeta sobre un escritorio de la tira.

#### P2. Pantalla de bloqueo de ii
**Límite real:** ningún programa normal puede dibujar en el escritorio seguro de Windows (contraseña, Ctrl+Alt+Supr). Tampoco puede sustituir el inicio de sesión del arranque sin un *credential provider*, que es una DLL de sistema en HKLM. Eso es arriesgado y va contra las reglas de seguridad del proyecto. Opciones:
- **A. Animación + bloqueo real (recomendada por defecto, segura).**
  - Win+L o "Bloquear" lanza la animación de ii: fondo con desenfoque y zoom y el reloj, como en el dotfile. Después bloquea Windows de verdad. Al desbloquear, la animación inversa.
  - La pantalla de bloqueo de Windows lleva el fondo de ii, sin "datos curiosos" ni widgets (HKCU). Falta verificar que la API de imagen de bloqueo funciona fuera de la Store.
- **B. Bloqueo de ii (opcional).**
  - Una pantalla de bloqueo propia de ii, con su campo de contraseña.
    - La contraseña se comprueba con `LogonUserW` (cuentas locales y cuentas Microsoft con contraseña).
    - PIN, huella o cara, con Windows Hello (`UserConsentVerifier`: sale la ventanita de Windows Hello).
    - Mientras está activa, el gancho de teclado bloquea Win, Alt+Tab y Alt+F4.
  - **No es una barrera de seguridad:** Ctrl+Alt+Supr siempre funciona. Por eso, en cualquiera de estos casos, ii-host llama al bloqueo real de Windows:
    - aparece la pantalla segura;
    - se abre el Administrador de tareas;
    - la shell se cierra;
    - el equipo se va a dormir;
    - pasan N minutos.
  - Quien intente saltárselo cae en el bloqueo de Windows.
- **C. Solo PCs de casa, con advertencia: inicio de sesión automático + B al arrancar.**
  - Así no se ve la pantalla de Windows al encender.
  - Requiere admin y guarda la contraseña como secreto LSA. Sin BitLocker, quien tenga el equipo puede entrar.
  - ii-host tendría que mostrar su cobertura de bloqueo **antes** de que cargue la shell.
- **Quitar la "cortina" del bloqueo de Windows** (ir directo a la contraseña): política `NoLockScreen` (HKLM, admin). Según Microsoft solo aplica en Enterprise y Education; verificarlo en Pro y Home.

#### P2. Animaciones de los paneles
- En Hyprland, las animaciones de abrir y cerrar paneles las hace el compositor (`layerrule animation slide/popin` por *namespace*).
- En Windows, ii las desactiva (`DWMWA_TRANSITIONS_FORCEDISABLED`) y nada las reemplaza: los paneles aparecen de golpe (C: `SidebarLeft.qml` solo cambia `visible`).
- [ ] **Un componente común en el overlay**, que anima el contenido dentro de la ventana con las curvas de ii:
  - las sidebars se deslizan desde su borde;
  - *popin* para el overview y la cheatsheet;
  - fundido para el menú de sesión y los OSD;
  - el dock sube y las notificaciones se deslizan.
- [ ] **El cierre se anima entero:** `visible: false` espera a que termine la animación de cierre.
- [ ] Respetar "Reducir animaciones" de Windows y el modo batería.

#### P2. Configuración: solo lo que funciona en Windows
- [ ] **Ocultar lo que no funciona en Windows** (un parche en `tools/port`, sin borrarlo del upstream):
  - actualizaciones del sistema ("Arch only");
  - Distro y Dotfiles en *Acerca de*;
  - estilo automático y traducción con Gemini (la IA aún no tiene transporte);
  - reconocimiento de música (SongRec);
  - opciones del bloqueo de Linux (hyprlock, huella, desbloquear el llavero);
  - grabar la pantalla (no hay `record.sh`) y la selección circular de región;
  - "Workspaces shown" (lo fija el port);
  - la familia de paneles Waffle;
  - la posición automática de widgets ("menos/más ocupado", usa Python);
  - "Constantly rotate" del reloj (su propio texto dice que gasta el 50 % de la GPU);
  - la transparencia con desenfoque (Windows no difumina lo que hay detrás).
- [ ] **Monitor de las notificaciones como lista desplegable.** Hoy pide nombres tipo `eDP-1`; en Windows son `DISPLAY1`.
- [ ] **Terminal y Qt apps:** dejar solo lo que alimenta el esquema de Windows Terminal.
- [ ] Cuando algo se implemente (el bloqueo, la IA), su opción vuelve a aparecer.

#### P2. Terminar el panel izquierdo
- [ ] **IA (hoy no conversa).** ii conversa con `bash` + `curl`, y eso no existe en Windows.
  - Hacer el transporte en `ii-shim`, que ya tiene un cliente HTTP (`host/src/http.cpp`), con respuestas en streaming para Gemini, OpenAI/OpenRouter, Mistral y Ollama local. Las claves ya se guardan con DPAPI.
  - Arreglar el listado de prompts y chats guardados (`ls -1` → `FolderListModel`).
  - Arreglar los errores `commandPrefix of null` del log.
- [ ] **Booru:** lo de P0, más descargas con `ii-shim fetch` y una caché limitada.
- [ ] **Botón de fijar el panel:** hoy llama a `hyprctl` (`togglePin`); hacerlo directo.
- [ ] **Traductor:** ya funciona con Google; falta un error claro cuando no hay internet.

#### P2. Terminal de ii con fastfetch
- [ ] **Perfiles en Windows Terminal.** Añadirlos a la *fragment* que ya escribe `switchwall.cpp`:
  - "ii · PowerShell": `powershell -NoLogo -NoExit -Command fastfetch` (o pwsh si está instalado);
  - "ii · CMD": `cmd /k fastfetch`.
- [ ] **Estilo de los perfiles:** el esquema ii-windows, JetBrains Mono NF (instalada por usuario, ver RAM), acrílico suave y márgenes.
- [ ] **Perfil por defecto:** preguntar antes; implica editar `settings.json`, con copia de seguridad.
- [ ] **Opcional:** un prompt con los colores de ii (starship, MIT).
- [ ] **No usar** el `AutoRun` de cmd ni el `$PROFILE` de PowerShell. Se ejecutan también en scripts (`cmd /c`, `powershell -File`) y romperían programas o los harían más lentos.

#### P3. Windows en equipos de 8 GB: "modo ligero" opcional
Opcional en el instalador: lista para elegir y todo reversible, con copia antes, como hoy. Los ahorros son aproximados, en un Windows 11 recién instalado.

| Qué | Cómo (reversible) | Ahorro aprox. |
| --- | --- | --- |
| Widgets de Windows (noticias) | Política `AllowNewsAndInterests=0` (admin). Windows protege el valor de HKCU en los builds recientes | 100–200 MB (WebView2) |
| Edge en segundo plano y su "aumento de inicio" | Políticas de usuario de Edge: `StartupBoostEnabled=0`, `BackgroundModeEnabled=0` | 100–300 MB |
| Sugerencias web en la búsqueda | `DisableSearchBoxSuggestions=1` (HKCU) | SearchHost más ligero |
| Apps al inicio (Teams personal, Copilot, utilidades del fabricante; OneDrive si no lo usas) | Los mismos interruptores de Administrador de tareas > Inicio (`StartupApproved`), en una lista para elegir | Variable |
| Grabación en segundo plano de Xbox Game Bar | `AppCaptureEnabled=0` / `GameDVR_Enabled=0` (HKCU). El Modo juego se deja | CPU y GPU en juegos |
| Apps que se instalan solas y consejos | `ContentDeliveryManager` (HKCU) | Menos programas sin pedir |
| Indexador de búsqueda | No desactivarlo (rompe las búsquedas). En un PC nuevo termina en unas horas: avisar | — |
| No tocar | Integridad de memoria (HVCI), Defender, SysMain, Inicio rápido | Seguridad y arranque |

Además, avisar en la bienvenida: en las primeras horas de un PC nuevo, Windows se actualiza, indexa y escanea, así que todo va lento, no solo ii.

### Casos en que el usuario puede romper o confundir el entorno
Estado: **C** confirmado · **P** probable · **T** sin probar.

**Teclado**
| Caso | Qué pasa hoy | Protección |
| --- | --- | --- |
| Alt+F4 con el foco en el escritorio, la barra, el dock, el overview o un panel | C: se cierra esa ventana de ii; el fondo desaparece y queda el de Explorer | P0 |
| Win+Q / Win+S | C: búsqueda de Windows | P0 |
| Win+número, también con Mayús/Ctrl/Alt | C: apps de la barra oculta o su lista de saltos | P0 / P2 |
| Win+T, Win+B | C: foco en la barra o la bandeja invisibles | P0 |
| Win+Alt+D, Win+W | C: paneles de Windows | P0 |
| Tecla Windows con una app de administrador delante | P: el gancho no ve teclas de apps elevadas y se abre el Inicio de Windows | Documentarlo; no hay solución limpia (UIAccess exige firma e instalar en Program Files) |
| Equipo muy cargado (primer arranque, antivirus) | P: Windows quita en silencio un gancho de teclado lento (está documentado) y la tecla Windows abre el Inicio hasta reiniciar | ii-host reinstala el gancho cada minuto y al reanudar o desbloquear |
| Ctrl+Alt+Mayús+R por accidente | C: ii se cierra del todo, sin aviso | Aviso: "ii se cerró (atajo de pánico). Menú Inicio > Iniciar ii" |
| Teclas de volumen y brillo | C: salen dos OSD, el de Windows y el de ii | Investigar cómo ocultar el de Windows, o no mostrar el de ii |
| Ctrl+Alt+Fin (menú de sesión) dentro de un escritorio remoto | C: choca con el Ctrl+Alt+Supr remoto | Ya documentado; combinación alternativa opcional |

**Ratón, touchpad y pantalla táctil**
| Caso | Qué pasa hoy | Protección |
| --- | --- | --- |
| Rueda sobre los escritorios de la barra | C: crea escritorios sin fin | P0 |
| Gestos del touchpad: 3 dedos (búsqueda de Windows por defecto), 4 dedos (notificaciones), 3 dedos hacia arriba (Vista de tareas); deslizar desde los bordes en pantallas táctiles | P: abren la interfaz de Windows | Mientras ii corre, cambiarlos a "atajo personalizado" (Windows 11 lo permite) que abra lo de ii. Guardar y restaurar como los banners; antes, averiguar dónde los guarda Windows |
| Esquinas de la pantalla | P: abren paneles sin querer (en Windows la gente va abajo a la izquierda buscando el Inicio) | Revisar los valores por defecto; opción "clic para abrir" |
| Pasar rápido el ratón por la barra | C: crea y destruye ventanas | P0 |
| Toque o lápiz sobre zonas con click-through | P: el primer toque atraviesa (la consulta va 16 ms por detrás) | Se arregla con los eventos del cursor (P1); probar en un 2 en 1 |
| Widget al 400 % o fuera de la pantalla | P: lo tapa todo o se pierde | Límite según el tamaño de pantalla y "Restablecer widgets" en el menú del escritorio |

**Windows y el equipo**
| Caso | Qué pasa hoy | Protección |
| --- | --- | --- |
| Terminar quickshell en el Administrador de tareas | C: ii-host la reinicia | Ya está bien |
| Terminar ii-host | C: el guardián restaura Windows, y ii no vuelve hasta reiniciar | Aviso con un botón "Iniciar ii" |
| Terminar ii-host y también el guardián | P: barra en autoocultar y sin región hasta el próximo inicio | El rescate ya existe; el siguiente arranque de ii-host repara lo que quedó |
| Actualización del driver de la GPU (Windows Update en un PC nuevo, muy común) | P: se pierde el dispositivo D3D y quedan ventanas negras o cuelgues. En tus logs hay un cierre por fallo `0xC0000005` el 08-oct a las 16:30, de causa desconocida | Detectar la pérdida del dispositivo y el cambio de adaptador, y reiniciar la shell sola |
| Suspender, hibernar o cerrar la tapa | T | Al reanudar, registrar de nuevo la AppBar, el gancho y los servicios; probar en un portátil |
| Cambiar resolución, escala o rotación; conectar o quitar un monitor; Win+P; dock USB-C | T (multimonitor y DPI siguen pendientes) | Pruebas; recolocar paneles y fondo |
| Escritorio remoto (RDP) o Parsec | P: Qt dibuja por software (WARP) y gasta mucha CPU | Detectar la sesión remota y bajar efectos |
| Cambiar en Configuración la barra de tareas de Windows (alineación, autoocultar) | P: Explorer recrea la barra y se ve hasta 2 s; el autoocultar original podría guardarse mal | Vigilar el cambio y ocultarla al momento |
| Cambiar el tema o el acento de Windows con ii abierto | C: al cambiar de fondo, ii vuelve a poner el suyo; al salir, vuelve el de antes de ii | Detectar el cambio del usuario y respetarlo, sin restaurar encima |
| No molestar / Concentración de Windows | P: ii muestra sus popups igual | Respetar el estado de Windows |
| Antivirus de terceros (Kaspersky; McAfee o Norton preinstalados) | P: el gancho de teclado y `SendInput` parecen un keylogger y pueden acabar en cuarentena; además escanean los 607 QML en cada arranque | Firma; documentar la exclusión; detectar el gancho caído |
| Smart App Control activado | P: ii no arranca | Firma; el instalador lo detecta y lo explica |
| ZIP sin "Desbloquear", o `install.cmd` abierto dentro del ZIP sin extraer | P: aviso de SmartScreen o "Paquete incompleto" | `Unblock-File`; mensaje "extrae el ZIP primero" |
| Escritorio e Imágenes en OneDrive (por defecto en muchos PC nuevos), con nombres traducidos ("Imágenes") | P: la carpeta de fondos `~/Pictures/Wallpapers` queda mal, y las miniaturas de archivos que solo están en la nube los descargan | Rutas con `SHGetKnownFolderPath`; para archivos en la nube, solo miniaturas ya guardadas |
| Usuario con tilde, espacio o apóstrofo (`José O'Brien`) | T: los comandos con comillas de bash pasados a cmd pueden romperse | Probar en Sandbox con ese nombre |
| Región con coma decimal (es-CO) | T: números como "0,5" en los shims y en QML | Probarlo |
| Wallpaper Engine, Lively, Rainmeter, ExplorerPatcher, StartAllBack, TranslucentTB | P: se pelean por el escritorio o la barra | Detectarlos al iniciar y avisar |
| Fondo de video, GIF animado o imagen 8K | P: fondo negro, redibujo continuo o mucha RAM | Reducir la imagen al tamaño de la pantalla; video: avisar o darle soporte |
| Windows 11 ARM (Snapdragon) | P: corre emulado y lento | Avisar en el instalador |
| Disco lleno al guardar `config.json` | P: la config queda cortada | Escritura atómica y una copia de la última config buena, que se restaura sola |

**Configuración de ii**
| Caso | Protección |
| --- | --- |
| Elegir Waffle, o cambiar de familia por IPC | Ocultarlo en Windows |
| "Constantly rotate", transparencia con desenfoque, paralaje | Avisar del coste u ocultarlo |
| Editar `config.json` a mano y dejar un error | Validarlo y volver a la copia buena, con un aviso |
| Pegar una clave de IA y que la IA no conteste | Ocultar la IA hasta que tenga transporte (P2) |
| GPS del clima | Ya viene apagado por defecto (Windows pide permiso) |

**Instalador**
| Caso | Protección |
| --- | --- |
| El portátil se "apaga" al terminar | Autosuspensión (P0) y registro de los eventos de energía |
| "¿Iniciar ii ahora?" viene en No | Ponerlo en Sí, con pantalla de carga y precalentado |
| Punto de restauración lento, o "Protección del sistema" apagada (común en portátiles nuevos) | Tiempo límite y un mensaje claro |
| Muchas preguntas en la consola | Más adelante, un instalador con ventana (mismas preguntas, mismo `install.json`) |

### Cómo se comprobará (antes de dar nada por hecho)
- **Arranque:** tiempos en frío y en caliente sacados de los logs, en Sandbox y en tu PC. Objetivo: menos de 5 s en caliente.
- **RAM y GPU:** las de quickshell a los 10 min y a las 24 h. Objetivo: menos de 350 MB y sin crecer.
- **Reposo:** GPU y CPU con el escritorio tapado (objetivo ≈ 0 %) y con música.
- **Ratón:** pasar por la barra no crea ventanas ni da tirones.
- **Pruebas nuevas en `tools/sandbox/tests`:**
  - Alt+F4 en cada panel;
  - rueda y Win+número;
  - atajos bloqueados;
  - batería simulada (`normalizeBattery` y la regla de suspensión);
  - proveedores booru con respuestas grabadas;
  - widgets nítidos (captura y comparación).
- **Un portátil real** (de tus amigos), con el reporte ampliado: eventos de energía, qué GPU usa ii, frecuencia y escala de la pantalla.

## Pendiente (en este orden)
0. El plan de la **Auditoría 2026-10-09** (arriba): primero P0, medir, y después P1.
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
. .\tools\dev\vsenv.ps1
pwsh -File .\tools\dev\fetch_mcu.ps1   # una vez: biblioteca de colores de Google (commit fijo)
cmake --build .\quickshell\build
cmake --build .\host\build
pwsh -File .\tools\dev\deploy.ps1      # quickshell + Qt + fuentes → dist\
pwsh -File .\tools\dev\stage-ii.ps1    # ii original + overlay → build\ii
```

### En Windows Sandbox (recomendado, no toca tu sesión)
```powershell
cd .\tools\sandbox
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
Las capturas quedan en `%USERPROFILE%\sbx-xchg\outbox\`.

### Si algo sale mal (en cualquier equipo)
- **Ctrl+Alt+Shift+R** mientras corre `ii-host`.
- O doble clic en `tools\rescue\ii-rescue.cmd`.
- O Ctrl+Shift+Esc → Archivo → Ejecutar nueva tarea → `powershell -ExecutionPolicy Bypass -File ".\tools\rescue\ii-rescue.ps1" -RestartExplorer`.

## Problemas conocidos
- **RAM:** ~500–600 MB en el Sandbox (wallpaper 3840×2400, ~15 ventanas Qt y fuentes de 15 MB). En tu PC, el 2026-10-09: ~1,3 GB privados + ~450 MB de GPU tras 35 min. Plan en la Auditoría 2026-10-09 (P1, RAM).
- **Notificaciones:** los botones propios de cada notificación de Windows (p. ej. "Responder") no se pueden pulsar desde fuera; ii muestra un botón "Open" que abre la app. La primera notificación de una app nueva puede salir también como banner de Windows (una sola vez).
- **Hardware sin probar:** Bluetooth, batería y brillo están programados pero solo se han probado sin hardware (ver D21).
- **Bandeja:** el menú de ii para fijar/desfijar iconos se cambió por el menú nativo de cada app. Los iconos propios de Explorer (volumen, quitar USB) también aparecen.
- **Sin `ii-host`:** tras reiniciar Explorer, el fondo de ii puede quedar por encima de la barra de Windows. Con `ii-host` (el uso normal) la barra está oculta y no se nota.
- **Escritorio:** los iconos de varias pantallas comparten la carpeta pero no se reparten entre pantallas. Los archivos cortados no se ven atenuados (Windows no lo informa). Una miniatura de un archivo editado sin cambiar su ruta puede conservarse en la caché hasta reiniciar la shell. `%PUBLIC%\Desktop` supone la ubicación pública habitual.
- **Avisos QML heredados:** aparecen valores inicialmente indefinidos en `SystemInfo`, `NotificationPopup`, `WorkspaceModel`, `ConflictKiller`, `BarContent` y `ToolbarTabBar`; faltan traducciones `es_CO` y comandos de Linux. `Qt.btoa(string)` conserva el código heredado y emite aviso de deprecación. La shell sigue funcionando, pero no se considera libre de avisos.
- **Apps en Sandbox:** no están instaladas todas las apps fijadas por defecto (Edge/Terminal); pueden aparecer iconos de respaldo. La prueba del dock usa Explorer, disponible en ese entorno.
