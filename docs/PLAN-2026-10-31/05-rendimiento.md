# 05 · Bloque D — Rendimiento, consumo y limpieza

> **En simple:** que ii gaste menos mientras usas otras cosas (sobre todo el navegador), que no deje basura en el disco y
> que al encender el PC no te haga esperar.

Versiones: D3, D4, D7 en la 0.7.0; D1, D2, D5, D8 en la 0.8.0; D6 va con C4; D9 es vigilancia continua.

---

<a id="d1"></a>
## D1 · El rastreador de ventanas trabaja de más mientras navegas — P1, esfuerzo M

**Dónde:** `quickshell/src/win32/toplevels.cpp`.

**Qué pasa hoy:** `onWinEvent` escucha `EVENT_OBJECT_CREATE…HIDE`, `LOCATIONCHANGE…NAMECHANGE`, `CLOAKED…UNCLOAKED`,
foco y minimizar **de todas las ventanas del sistema**. Cualquiera (un cambio de título de una pestaña, una ventana que
se mueve, un *tooltip* de otra app) programa un `refresh()` completo a 40 ms, que hace `EnumWindows` y, **por cada
ventana conocida**, `GetWindowTextW`, `SHGetPropertyStoreForWindow` (COM), `VirtualDesktops::desktopOf` →
`IVirtualDesktopManager::GetWindowDesktopId` (**llamada entre procesos a Explorer**), `DwmGetWindowAttribute`,
`MonitorFromWindow`… en el hilo GUI. Con un navegador que cambia el título seguido o al arrastrar una ventana son hasta
25 recorridos completos por segundo. Además, una llamada a Explorer que tarda congela la interfaz (y con el latido de la
0.6.0, una espera de 5 s sin CPU = la shell "congelada" y reiniciada).

**Cómo arreglarlo:**
1. Procesar **por ventana**, no todo:
   - `NAMECHANGE` → solo `title` de esa `hwnd` (si está en `byHwnd`).
   - `LOCATIONCHANGE` → solo geometría/pantalla/pantalla completa de esa `hwnd`, agrupado 50 ms.
   - `SHOW/CREATE/UNCLOAKED` → `isAppWindow(hwnd)` y alta si corresponde; `HIDE/DESTROY/CLOAKED` → baja o recheck.
   - `FOREGROUND` → `activated` y `mActive`, sin recorrer.
   - `MINIMIZESTART/END` → `minimized` de esa ventana.
2. **Cachés por ventana:** el AUMID (`appUserModelId`) se lee al dar de alta la ventana y se revisa cada 30 s (no hay un
   evento para su cambio, que además es raro); el escritorio virtual solo se relee con `VirtualDesktops::changed` o con
   `CLOAKED/UNCLOAKED` de esa ventana.
3. **Recorrido completo** como red de seguridad: máximo 1 por segundo y solo si hubo un evento que lo justifique, más uno
   cada 10 s.
4. Llamadas COM a Explorer (`GetWindowDesktopId`) fuera del hilo GUI (un hilo con la cola de ventanas a consultar) o con
   resultado en caché.
5. **Medir** con `tools/dev/sampler.cpp` (`--pid`) y el contador de `refresh()`: arrastrar una ventana 30 s y desplazarse
   en X 60 s. Objetivo: −70 % de CPU del hilo GUI de `quickshell.exe` y ninguna espera > 100 ms.

---

<a id="d2"></a>
## D2 · Todo lo que anima se detiene cuando una ventana tapa el escritorio — P1, esfuerzo S–M

Ya existe `services/DesktopCover.qml` (pantallas con una ventana maximizada o a pantalla completa) y lo usan
`MediaWidget.qml` y `JapaneseClock.qml`. **No** lo usan: `ClockWidget`/`CookieClock`/`DigitalClock`/manecillas (el
segundero redibuja cada segundo), `CookieQuote`, `CalendarCard`, `NotesCard`, `ResourcesCard` (consulta CPU/RAM),
`TimerCard`, `TodoCard`, foto con pase de diapositivas, clima.

1. `AbstractBackgroundWidget.desktopCovered` ya está; añadir `readonly property bool animate: visible && !desktopCovered
   && !GlobalStates.screenLocked && !Performance.light` y usarlo en **todos** los `Timer`, `Animation` y consultas
   periódicas de los widgets (`running: root.animate`).
2. Al destaparse: actualizar al instante (la hora salta al valor correcto, no anima desde el valor viejo).
3. `DesktopCover` hoy recalcula cada 1 s con un `Timer` + eventos. Cambiar a solo eventos: conectar a
   `maximizedChanged`/`minimizedChanged`/`fullscreenChanged`/`screensChanged` de cada *toplevel* (señales que el fork ya
   emite) y quitar el `Timer`.
4. Lo mismo para la barra cuando una app a pantalla completa la tapa (reloj con segundos, visualizador, letra sincronizada).
5. **Medir:** GPU y CPU de `quickshell.exe` con Brave maximizado 10 min, antes y después (Administrador de tareas >
   Detalles, columnas GPU y CPU; o `typeperf`). Objetivo: ~0 % de GPU de ii con el escritorio tapado.

---

<a id="d3"></a>
## D3 · Carátulas sin procesos ni archivos que no existen — P0 (con A2), esfuerzo S

- Visto en los logs: un `ii-shim fetch` por canción y `Cannot open …/coverart/<md5>` repetido para carátulas locales.
- Arreglo en A1 (la carátula se guarda una vez por canción, en `%LOCALAPPDATA%\ii-windows\cache\media-art`) y A2 (QML:
  local directo, `https:` con `Image` de Qt).
- Bonus: precalcular el color de la carátula (`ColorQuantizer`) una vez por carátula y guardarlo junto al archivo
  (`<sha1>.json`), para no recalcularlo en cada panel que la muestra.

---

<a id="d4"></a>
## D4 · Conserje: cachés con tope y sin basura al desinstalar — P1, esfuerzo S

Medido en esta PC tras desinstalar: `%LOCALAPPDATA%\quickshell\cache` = **151 MB, 18 929 archivos**;
`%TEMP%\ii-windows\mpris` 34 carátulas tras una noche; `%TEMP%\quickshell\by-pid` con 18 carpetas.

| Qué | Dónde hoy | Regla nueva |
|---|---|---|
| Carátulas | `%TEMP%\ii-windows\mpris` | `%LOCALAPPDATA%\ii-windows\cache\media-art`, máx. 200 archivos / 50 MB, LRU |
| Iconos de bandeja | `%TEMP%\ii-windows\tray` | `…\cache\tray-icons`, por hash del bitmap, máx. 500 |
| Iconos de notificaciones | `%TEMP%\ii-windows\notification-icons` | `…\cache\notification-icons`, máx. 300 |
| QML compilado de versiones viejas | `%LOCALAPPDATA%\quickshell\cache\by-shell\<hash>` y `qmlcache` | Conservar solo los de la versión activa y la anterior |
| Logs de la shell | `%TEMP%\quickshell\by-pid\*` | Borrar los de más de 7 días |
| `host.log` | 860 KB y creciendo | Rotar a 2 MB (`host.log.1`) |
| Crashes | `…\ii-windows\crashes` | 5 últimos, 14 días (A3) |
| Descargas de actualizaciones | `…\ii-windows\update` | Borrar tras `verified` (B6) |

- Lo hace `ii-host` una vez al día, con el PC inactivo (sin juego, sin entrada 5 min), en un hilo de prioridad baja.
- **Desinstalador** (`tools/package/uninstall.ps1`): borrar también `%LOCALAPPDATA%\quickshell\cache\*` de ii y las
  carpetas de caché de la tabla; preguntar "¿Conservar tu configuración (widgets, notas, fondos)?" (Sí por defecto =
  deja `illogical-impulse` y `ii-windows\backup`).

---

<a id="d5"></a>
## D5 · Arranque con Windows: menos espera y nunca atrapado — P1, esfuerzo M

Medido (host.log): con la PC ya encendida la shell queda lista en 2–5 s; **al iniciar sesión, 10,9 / 12,9 / 27,6 s** de
portada (26–27/10), casi todo esperando E/S de disco mientras Windows arranca sus programas de inicio.

1. **Portada saltable y con tope de 12 s** ([A9](02-estabilidad.md#a9)).
2. **Precalentar archivos** con `--boot`: mientras se ve la portada, un hilo de `ii-host` con E/S de prioridad muy baja
   lee en orden `quickshell.exe`, las DLL de Qt que usa y los `.qmlc` de la caché (≈ 600 archivos) para que estén en la
   caché de Windows cuando la shell los pida. Medir con `tools/dev/coldstart.ps1` y un arranque real.
3. **Menos archivos:** estudiar empaquetar el QML compilado en uno o pocos archivos (recurso `.rcc` de Qt o un índice
   propio en `qmltree`). Investigación primero: medir cuánto del tiempo de arranque es abrir archivos (WPR/WPA: un trazo
   de arranque con *File I/O* y *CPU Usage (Sampled)* en esta PC).
4. **Primero lo visible:** barra y fondo en la fase 1 (ya), widgets del escritorio en la fase 2, todo lo demás (barras
   laterales, vista general, tienda) en la fase 3 (ya existe `GlobalStates.startupPhase`; revisar qué quedó en la 1).
5. **Tarea de inicio:** ya usa `-Priority 4` (normal, `tools/package/ii-autostart.ps1:77`), así que la E/S no arranca en
   prioridad baja. Comprobar en el trazo de WPR cuánto espera ii a que Windows termine de lanzar los demás programas de
   inicio, y si conviene mostrar primero la barra (fase 1) con el resto en segundo plano.
6. **Aceptación:** al iniciar sesión, escritorio de ii usable (barra + fondo + clic) en < 8 s en esta PC; portada nunca
   más de 12 s.

---

<a id="d6"></a>
## D6 · Ajustes que no traban la shell
Ver [C4.2](04-configuracion.md#c4): escribir `config.json` al soltar el slider. Es el mismo problema visto desde la
shell: cada escritura recarga toda la configuración.

---

<a id="d7"></a>
## D7 · Cero avisos QML nuevos (presupuesto de avisos) — P1, esfuerzo S

Avisos vistos en la 0.6.0 que hay que quitar:

| Aviso | Arreglo |
|---|---|
| `PlayerControl.qml[85/147/299]: Unable to assign [undefined]` | A2 |
| `MediaWidget.qml[73]: Cannot open …/coverart/…` y `colorquantizer: Failed to load image` | A2/D3 |
| `bar/BarContent.qml[134]: Unable to assign [undefined] to double` | Revisar el *binding* de esa línea (padding del grupo central) con `?? 0`. |
| `services/Translation.qml[21]: Unable to assign [undefined] to bool` | Valor por defecto. |
| `TranslationReader … illogical-impulse/translations/es_MX.json failed: File does not exist` | Es la carpeta de traducciones **generadas** por el usuario: comprobar que existe antes de leer (o crearla vacía). |
| `CookieClock.qml[69]: … wallpaper/category.txt failed` | Leer solo si existe; valor por defecto "general". |
| `QPixmap::fromWinHICON(), failed to GetIconInfo()` | Validar el `HICON` (A6, bandeja/ventanas) y conservar el último icono bueno. |

- `tools/dev/settings-pages.ps1` y `smoke-shell.ps1` guardan los avisos en un archivo y **fallan** si aparece uno que no
  está en `tools/dev/qml-warnings-allowed.txt` (lista que solo baja).

---

<a id="d8"></a>
## D8 · Memoria estable en sesiones largas — P1, esfuerzo S

- `tools/dev/soak.ps1` (A8): 8 h normales (navegador con videos, Spotify, 2 escritorios, notificaciones) registrando
  cada 5 min la memoria privada y los *handles* de `quickshell.exe` e `ii-host.exe`.
- Criterio: línea plana (±10 %) tras la primera hora. Si sube: `MaterialSymbol`/imágenes sin `sourceSize`, miniaturas
  DWM sin liberar (`ScreencopyView`), modelos que solo crecen (`players`, `tracked`).
- README: actualizar "unos 200 MB en el día a día" con la cifra medida.

---

<a id="d9"></a>
## D9 · Vigilar el render loop *threaded* (nuevo en 0.6.0)

No causó el crash, pero es un cambio grande y solo se probó en la laptop AMD. Con A3:
- El JSON de cada crash dice `renderLoop` y la GPU.
- Si un crash cae en `Qt6Quick.dll`, `d3d11.dll`, `dxgi.dll` o el driver, A4 lo trata como firma "render" y la
  siguiente shell arranca con `QSG_RENDER_LOOP=basic` (lo mismo que `appearance.renderLoop = "basic"`), avisando.
