# Ronda nocturna (2026-10-17)

Carlos se fue a dormir y pidió trabajo autónomo: probar como usuario, corregir, mejorar, y sobre todo
responder **"¿por qué alguien lo instalaría si en PCs lentos no inicia rápido?"**. Rama `ux/noche-2026-10-17`
(sale de `ux/visual-polish`) en los dos repos (ii-windows y el fork `quickshell`, rama `windows`).
Nada se sube a GitHub sin preguntar.

## Cómo se midió un "PC lento" sin tener uno

`scratchpad/coldrun.ps1` + `slowjob.ps1` (copias en `tools/dev/` pendientes): copia la versión instalada
sin pasar por la caché de disco (`robocopy /J`), arranca ii-host desde ahí con su propia carpeta de datos y
mete **quickshell en un Job de Windows con la CPU limitada** (2 núcleos al 15 % ≈ un Celeron/Pentium de
portátil barato). Se mide hasta que se va la cubierta de "Bienvenido" (`splash-closed` en host.log).

Ojo: el límite es para todo el proceso, así que pasar trabajo a otro hilo no se nota en el emulador (sí en
un PC real con 2+ núcleos).

Herramientas nuevas:
- **perfil QML** con `qmlprofiler` (Qt) contra `quickshell --debug <puerto> --waitfordebug` → `.qtd`, y un
  script que suma tiempo por archivo/tipo. **Cuidado**: abre un puerto TCP y Windows pregunta por el
  Firewall; se respondió "Cancelar" (no se dio acceso a red). No usar con el ii instalado.
- **`tools/dev/sampler.cpp`**: perfilador por muestreo del hilo principal (pilas cada ~5 ms, símbolos del
  PDB de quickshell y exportaciones de Qt). Mostró lo que el perfil QML no ve (C++).
- **registro de procesos**: `quickshell --log-rules "quickshell.process.start.info=true"` lista cada
  proceso que lanza el QML.

## Resultados (PC lento emulado)

| | antes | ahora |
|---|---|---|
| Arranque normal (cubierta fuera) | 29 s | **14,7 s** |
| Primer arranque tras instalar | 37 s | **18 s** (con precompilado en el instalador) |
| CPU del shell hasta ver el escritorio | 7,3 s | **3,8 s** |
| Procesos lanzados al arrancar | 34 | 25 |
| Procesos en reposo | ~30 por minuto | ~3 por minuto |

En este PC (Ryzen): la cubierta se va a los **4,2–4,5 s** (antes 6–10 s).

Fuera del arranque:

| | antes | ahora |
|---|---|---|
| RAM del shell | 529 MB | **407 MB** (fuentes recortadas) |
| CPU en reposo sin nadie en el PC | 2,3 % de un núcleo | **0,6 %** |
| CPU en reposo usándolo | 2,3 % | ~2 % (avisos leídos cada segundo) |

## Qué se cambió

**Fork (quickshell):**
- `ObjectModel::diffUpdate` avisa **una vez** por actualización, no una por fila: la lista de apps
  (208) hacía que todo lo que la usa (búsqueda, dock, `TaskbarApps`) se recalculara **204 veces** al arrancar,
  con búsqueda difusa de todas las apps cada vez (~1,5 s de CPU aquí, ~6 s en un PC lento).
- Apps en orden estable (antes cada reescaneo las reordenaba todas).
- El primer recorrido del menú Inicio (COM + iconos) ya no bloquea el hilo de la interfaz.
- `QS_PRECOMPILE=1`: compila todo el QML a la caché de Qt y sale (lo usa el instalador).
- Registro opcional de procesos (`quickshell.process.start`).

**QML (`tools/port/patch_ii_perf.py`):**
- La cubierta de bienvenida solo espera lo visible (fondo, barra, dock, iconos y widgets). Los paneles que
  se abren después (barras laterales, vista general, notificaciones, OSD, bloqueo, capturas…) se crean
  **en segundo plano, por trocitos entre fotogramas** (`LazyLoader.loading`), sin congelar.
- Deduplicación de apps en una pasada (antes comparaba todas contra todas), caché de búsqueda de iconos.
- La familia de paneles "Waffle" (no se usa en Windows) ya no se compila al arrancar.
- Procesos: 9 → 3 para crear/vaciar carpetas; fuera `pidof kded6/mako/dunst`, `lscpu` (ahora el registro),
  `fprintd-list`, `which checkupdates`, `whoami`; el teclado en pantalla ya no "suelta" 249 teclas al cargarse;
  luz nocturna re-aplicada cada 5 s **solo si está encendida**; fondo animado buscado cada 20 s si no hay
  ninguno; plan de energía consultado solo con el panel abierto.
- Barra lateral izquierda: se llenaba en `Component.onCompleted`, que con la carga en segundo plano llegaba
  antes que su ventana (quedaba vacía). Dos avisos de cada arranque corregidos.

**Instalador:** "Preparando la interfaz (solo esta vez)" = precompilado (~5 s aquí); al quitar versiones viejas
borra también su copia del QML y sus compilados (~13 MB por versión; en este PC había 300 MB de restos).

**ii-shim:** `reset-dir` acepta varias carpetas; `system-info` dice hilos de CPU y memoria.

**Segunda parte (02:00–02:35):**
- **Fuentes: −122 MB de RAM.** Qt guarda una "cara" DirectWrite por cada *instancia con nombre* de una fuente
  variable, y cada una ocupa casi lo que el archivo: Google Sans Flex (4 MB, 18 instancias) eran 73 MB y
  Material Symbols (15 MB, 7) ~105 MB. `tools/dev/trim_fonts.py` (lo llama `deploy.ps1`) deja solo los pesos que
  el QML usa; todos los ejes variables siguen (comparado con capturas: idéntico). Probado dejar una sola instancia:
  las negritas salen sintéticas, así que no.
- **Notificaciones en reposo:** el fork leía todas las de Windows cada segundo (llamada entre procesos + XML de
  cada una). Sin nadie en teclado/ratón 1 minuto, cada 5 s (el informe de salud al host sigue cada segundo).
- **Árbol QML y escáner:** lo que hay en la copia sale de un solo listado de carpeta (antes ~1.000 consultas
  sueltas) y cada carpeta importada se mira una vez (stat 61 → 6 ms).
- **Vigilancia de los ~600 archivos QML** (recarga en caliente) apagada por el host en uso normal
  (`II_WATCH_QML=1` la deja para desarrollar): ~0,27 s menos al arrancar y menos hilos.
- **Fondo** decodificado una vez (antes dos: su tamaño cambiaba cuando respondía `magick identify`).
- **Host:** el aviso `TaskbarCreated` que manda la propia bandeja de ii al arrancar se tomaba por un reinicio del
  Explorador y se volvía a aplicar todo un segundo después.
- **Modo ligero** (`services/Performance.qml`): el selector Configuración → Apariencia → Rendimiento ahora aplica el
  preset completo (sin animaciones, sin transparencias en ii **ni en las otras ventanas**, dock sin lupa) y el
  recorrido de bienvenida lo **ofrece con un botón** en PCs con ≤4 hilos o <7 GB. "Light" salía "Claro" (como el
  tema): ahora "Ligero".

Probado al final, con el entorno de desarrollo: barras laterales, búsqueda, atajos, sesión, multimedia, recorrido
(paso nuevo + botón) y todas las páginas de Configuración (sin errores nuevos). Tu `config.json` quedó idéntico
(se restauró la copia tras probar el botón del modo ligero).

## Bitácora

- 01:05 Estado encontrado: ii no estaba corriendo (la sesión anterior terminó con el atajo de pánico el
  16/10 21:34). Instalada: 0.3.0-20261016-c794259.
- 01:10–01:45 medición, perfiles y cambios de arriba. Probados en el escritorio real (entorno de desarrollo):
  barras laterales, búsqueda, atajos, sesión, multimedia: bien.

## También esta noche

- **"Lo que más gasta"** en el panel de recursos de la barra (`ii-shim top`): los programas que más CPU y memoria
  usan, sumando sus procesos y con su nombre amigable; un clic en el indicador abre el Administrador de tareas.
- El espectro de música (cava) se detiene con "Reducir animaciones" / modo ligero.
- El modo ligero se ofrece una vez por notificación a quien ya había hecho el recorrido (PC modesto).
- README: sección "En un PC modesto".

## Revisión e instalación (02:45–05:55)

- Revisión independiente del diff (agente "critic"): nada que deje sin escritorio en uso normal. Corregido:
  fallo de carga en segundo plano que dejaba un puntero liberado (LazyLoader), escaneo de apps en su propio hilo,
  árbol QML con cambios de mayúsculas, fila "más usadas" vacía en PCs lentos, nombres/iconos que no se refrescaban
  al cargar la lista de apps, cambio a Waffle revertido (podía dejar sin paneles), `trim_fonts.py` que se niega a
  dejar una fuente sin sus pesos, limpieza de caché del instalador más prudente, `mkdir` que sigue tras un fallo,
  memoria instalada real (16 GB, no 14 utilizables), aviso del modo ligero solo desde el shell.
- Quedan anotados (bajo riesgo): un panel de fase 2/3 con `extraCondition` no se descargaría (hoy no hay ninguno);
  un `TaskbarCreated` del mismo Explorador al iniciar sesión se ignora (el gancho de la barra la sigue ocultando).
- **Instalada en el PC de Carlos:** `0.3.0-20261017-800f243` (anterior `c794259` como vuelta atrás; la `ecddf2f`
  se quitó con su caché). Precompilado en el instalador: 5 s. Primer arranque: cubierta fuera a **4,5 s** (la
  anterior, 9,7 s), `state=verified`, sin errores en el registro. `config.json` idéntico. Se dejó **detenida**,
  como estaba; la tarea de inicio de sesión la arranca la próxima vez.

## Después de la primera instalación (incluido en la reinstalación de las 06:59)

- **No molestar por un rato**: en el panel derecho, el icono del botón de notificaciones silencia como siempre;
  el resto del botón recorre "1 hora" → "hasta mañana a las 8:00" → mostrar, y dice "Hasta las HH:mm". El
  silencio se acaba solo. Probado con clics en el panel.
- **Letra sincronizada** (`services/Lyrics.qml`, LRCLIB): botón de letra junto a reproducir/pausa en el panel de
  multimedia y en el widget de música. Apagada hasta que se pulsa (solo entonces se envían artista/título/duración a
  lrclib.net); la línea actual ocupa el lugar del artista y sigue la canción. Probado con una sesión multimedia
  **silenciosa** (WAV de silencio, en mudo) "Daft Punk – Get Lucky". Se dejó apagada. El motor JS de Qt no tiene
  `String.matchAll` (fallaba en silencio): usar `RegExp.exec` en bucle.
- **Tiempo de pantalla** (pestaña "Uso" del panel derecho, junto a Calendario/Tareas/Temporizador): el host
  (`host/src/screentime.cpp`) suma un segundo al programa que está al frente, solo con actividad en los últimos 2 min
  o con algo a pantalla completa (películas, juegos), nunca con la sesión bloqueada ni para el escritorio, la barra o
  ii. Un JSON por día en `%LOCALAPPDATA%\ii-windows\screentime\` (30 días; nada sale del PC) con nombre (descripción
  del .exe) y ruta (para el icono). Apps de la Tienda: cuenta la app, no ApplicationFrameHost. Probado con el Bloc de
  notas al frente ~1,5 min; se borraron los datos de prueba y la pestaña quedó en Calendario como estaba.

## Reinstalación 06:59

`0.3.0-20261017-4cb587e` (con No molestar, letra y Uso), anterior `800f243` como vuelta atrás. Primer arranque:
cubierta fuera a 4,5 s, `state=verified`, sin errores. Detenida otra vez como estaba; datos de prueba de "Uso" borrados.

## Reinstalación 07:22

`0.3.0-20261017-5dd9f1c`: tiempo de pantalla sin caché por id de proceso (un id reutilizado se atribuía al
programa equivocado) y la línea de la letra solo se actualiza mientras suena. Verificada (4,5 s, sin errores),
anterior `4cb587e`, detenida como estaba.

## Pendiente

- Qt enumera **todas las fuentes del sistema** en el primer texto (~0,45 s aquí, ~1,5 s en un PC lento): no se
  evita sin cambiar Qt.
- RAM restante (406 MB): servicios ~180, fondo ~96 (imagen ~36, widgets ~28, ventana), barra ~35, dock ~21.
- **Prueba de memoria de uso diario (07:45):** abrir/cerrar 5 paneles 350 veces: 362 → 589 MB en la primera ronda
  (cada panel abierto por primera vez: barra derecha +47, izquierda +50, búsqueda +31, atajos +94 —tabla periódica
  ~25—, selector de fondos +57) y luego +6…+19 MB por cada 50 aperturas, bajando algo en reposo; los handles no
  crecen. No parece una fuga, sí un pico alto. Una ventana a pantalla completa vacía ya cuesta ~44 MB (Qt crea un
  dispositivo Direct3D y su cadena de imágenes por ventana). Opciones experimentales en el fork, **apagadas**:
  `QS_RELEASE_HIDDEN=1` (−50 MB, primer cuadro más lento al abrir) y `QS_SHARED_RHI=1` (un solo dispositivo,
  −30 MB, pero si la GPU se reinicia las ventanas quedarían en blanco). Hecho después: la tabla periódica se crea solo al abrir su pestaña (−26 MB cada vez que se abren los atajos).
- 950 textos (`StyledText`) creados al arrancar: los widgets de escritorio y la barra.
- Avisos leídos cada segundo mientras se usa el PC (~2 % de un núcleo aquí): Windows no da evento a apps sin paquete.
- Ideas de otras shells en `docs/IDEAS-OTRAS-SHELLS.md` (No molestar con presets, letras de canciones, etc.).
