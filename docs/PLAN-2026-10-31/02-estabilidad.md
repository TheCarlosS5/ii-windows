# 02 · Bloque A — Estabilidad (P0)

> **En simple:** primero que ii **no se caiga** (A1, A2). Después, que si algún día se cae por otra cosa, **deje rastro**
> para arreglarlo en minutos (A3), **no entre en un bucle** de cierres (A4), le **diga al usuario** qué pasó y le deje
> elegir (A9), y que una versión nueva que falla **se pueda deshacer sola** (A7).

Orden: A1 → A2 → A8 (pruebas) → A3 → A4 → A5 → A9 → A7 → A6. Las A1, A2, A3, A8 y lo mínimo de A4/A9 forman la
**0.6.1 (hotfix)**; el resto va en la 0.7.0.

Todas las rutas son relativas al repo. "Fork" = `quickshell/` (repo `quickshell-windows`, rama `windows`).

---

<a id="a1"></a>
## A1 · Reescribir el backend de multimedia (`mpris.cpp`) — P0, 0.6.1, esfuerzo M

**Archivo:** `quickshell/src/win32/services/mpris.cpp` (y `mpris.hpp` si cambia la interfaz privada).
**Causa:** [01 §3](01-fallo-principal.md#3-causa-raíz-técnica).

### A1.1 Reglas que debe cumplir el código nuevo

1. **Todo objeto WinRT que devuelve un getter se comprueba antes de usarlo** (`if (!info) …`). Sin excepciones a la regla:
   `GetPlaybackInfo()`, `info.Controls()`, `GetTimelineProperties()`, `TryGetMediaPropertiesAsync()` → `GetResults()`,
   `props.Thumbnail()`, `OpenReadAsync()` → stream.
2. **Un solo hilo de trabajo** (MTA) hace todas las lecturas. Los eventos de WinRT solo **marcan** la sesión como
   "sucia" y despiertan al hilo; nunca leen ni bloquean el *thread pool*.
3. **Ráfagas agrupadas:** al despertar, el hilo espera 80 ms y procesa cada sesión sucia **una vez** (un video que
   cambia título, estado y línea de tiempo a la vez genera 1 lectura, no 3 en paralelo).
4. **Claves fijas:** cada sesión recibe su clave la primera vez que se ve (`Brave`, `Brave#2`, `Brave#3`…, con un contador
   por app que solo sube) y **la conserva hasta que desaparece**. Se empareja por identidad del objeto WinRT
   (`operator==` de C++/WinRT compara la identidad COM). *Comprobar en la primera prueba* que `GetSessions()` devuelve
   los mismos objetos entre llamadas; si no, emparejar por `SourceAppUserModelId` + orden y aceptar el desplazamiento,
   pero **siempre** leyendo del objeto de la lista actual, nunca de uno guardado de antes.
5. **Desuscribirse:** guardar los *revokers* (`winrt::auto_revoke`) de los 3 eventos por sesión y del `SessionsChanged`;
   al quitar la sesión se destruyen y dejan de llegar eventos viejos.
6. **Nada bloquea para siempre:** `.get()` se cambia por `wait_for(2s)`; si no completó, `Cancel()` y se reintenta en la
   próxima ronda. Un navegador colgado no deja a ii sin multimedia (ni acumula hilos).
7. **Carátula solo cuando cambia la canción** (título|artista|álbum distinto al último leído para esa sesión), máximo
   8 MB, en `%LOCALAPPDATA%\ii-windows\cache\media-art\<sha1>.img` (no en `%TEMP%`), con limpieza (ver [D4](05-rendimiento.md#d4)).
8. **Errores visibles en el log, no tragados:** `catch (winrt::hresult_error const&)` registra el HRESULT y la clave;
   nada de `catch (...) {}` vacío. **No** usar `/EHa` ni `__try` como parche: esconden el fallo y pueden dejar el
   `mutex` tomado (bloqueo total).

### A1.2 Esqueleto propuesto

```cpp
// Una entrada por sesión viva. Solo el hilo del worker la crea, la modifica y la borra.
struct SessionEntry {
	GlobalSystemMediaTransportControlsSession session {nullptr};
	QString key;      // fija mientras la sesión exista
	GlobalSystemMediaTransportControlsSession::MediaPropertiesChanged_revoker mediaRevoker;
	GlobalSystemMediaTransportControlsSession::PlaybackInfoChanged_revoker playbackRevoker;
	GlobalSystemMediaTransportControlsSession::TimelinePropertiesChanged_revoker timelineRevoker;
	std::atomic<bool> dirty {true};
	QString lastTrack; // "título\x1fartista\x1fálbum" de la última carátula leída
	QString lastArt;
};

class Backend: public QObject {
	// …
	void run() { // std::thread propio, nunca el GUI
		winrt::init_apartment(winrt::apartment_type::multi_threaded);
		auto op = GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
		if (op.wait_for(std::chrono::seconds(10)) != winrt::Windows::Foundation::AsyncStatus::Completed) return logUnavailable();
		this->manager = op.GetResults();
		if (!this->manager) return logUnavailable();
		this->sessionsRevoker = this->manager.SessionsChanged(winrt::auto_revoke, [this](auto&&, auto&&) { this->wakeUp(true); });
		for (;;) {
			{
				std::unique_lock lock(this->mutex);
				this->wake.wait(lock, [this] { return this->stopping || this->sessionsDirty || this->anyDirty; });
				if (this->stopping) return;
			}
			std::this_thread::sleep_for(std::chrono::milliseconds(80)); // agrupar la ráfaga
			if (this->takeSessionsDirty()) this->refreshSessions();      // altas y bajas, en este hilo
			for (auto& entry: this->entries) {
				if (!entry->dirty.exchange(false)) continue;
				if (auto state = this->readState(*entry)) this->post(entry->key, *state);
			}
		}
	}

	std::optional<PlayerState> readState(SessionEntry& e) {
		PlayerState s;
		try {
			auto propsOp = e.session.TryGetMediaPropertiesAsync();
			if (propsOp.wait_for(std::chrono::seconds(2)) == winrt::Windows::Foundation::AsyncStatus::Completed) {
				if (auto props = propsOp.GetResults()) {
					s.title = toQ(props.Title()); /* artist, album, albumArtist */
					s.artUrl = this->artFor(e, props); // solo lee la miniatura si cambió la canción
				}
			} else {
				propsOp.Cancel();
			}
			auto info = e.session.GetPlaybackInfo();
			if (!info) return std::nullopt; // la sesión se está cerrando; SessionsChanged la quita
			s.playback = toPlayback(info.PlaybackStatus());
			if (auto controls = info.Controls()) { /* canPlay, canPause, canNext, … */ }
			if (auto shuffle = info.IsShuffleActive()) s.shuffle = shuffle.Value();
			if (auto repeat = info.AutoRepeatMode()) s.loop = toLoop(repeat.Value());
			if (auto rate = info.PlaybackRate()) s.rate = rate.Value();
			if (auto timeline = e.session.GetTimelineProperties()) { /* length, position, positionUpdated */ }
		} catch (winrt::hresult_error const& error) {
			qCInfo(logMpris) << "Session" << e.key << "not readable:" << Qt::hex << static_cast<quint32>(error.code());
			return std::nullopt;
		}
		return s;
	}
};
```

- `refreshSessions()`: lee `GetSessions()` (con `try`), empareja con `entries`, crea `SessionEntry` nuevas (clave nueva +
  revokers con `winrt::auto_revoke` que capturan un `std::weak_ptr<SessionEntry>` y solo hacen `dirty = true; wakeUp()`),
  borra las que ya no están, y manda al hilo GUI **una** lista de altas/bajas (`QMetaObject::invokeMethod`).
- `MprisPlayer::apply()` y la lista `players` solo cambian en el hilo GUI (ya es así); un estado que llega para una clave
  que ya no existe se ignora.
- `withSession()` (play/pausa/siguiente desde el GUI) pide el objeto por clave **bajo el mutex**, comprueba nulo y lanza la
  operación asíncrona sin esperarla (ya es así). Añadir `try` con log.
- La sesión "actual" de Windows (`manager.GetCurrentSession()`) puede exponerse como `MprisQml.activePlayer` para que el
  panel elija bien cuál mostrar (hoy el QML adivina).

### A1.3 Pruebas (ver [A8](#a8))

- `ii-mpris-stress` (nuevo, en el fork, como `ii-hardware-test`): 2 000 sesiones creadas y destruidas en 10 min.
  Criterio: 0 crashes, `players` termina vacío, *handles* y memoria estables (±5 %).
- `tests/media/churn.html` en Brave, Chrome y Edge, 3 pestañas, 2 h: 0 líneas `exited with code` en `host.log`.
- Regresión manual: Spotify, YouTube, VLC y el reproductor de Windows muestran título, carátula, posición y botones.
- **Criterio de aceptación:** 2 h de feed de X + Shorts sin un solo crash; CPU de `quickshell.exe` durante la prueba
  < 3 % de media en la laptop AMD.

---

<a id="a2"></a>
## A2 · QML de multimedia sin avisos y sin un proceso por canción — P0, 0.6.1, esfuerzo S

Archivos (copias de upstream modificadas por `tools/port/*.py` o *overlay*; si el parche crece, pasar el archivo entero
a `overlay/ii/` como dice D11):

| Archivo | Línea (0.6.0) | Hoy | Cambio |
|---|---|---|---|
| `modules/ii/mediaControls/PlayerControl.qml` | 85 | `property string targetFile: root.artUrl` | `root.artUrl ?? ""` |
| idem | 147 | `live: root.player?.isPlaying` | `root.player?.isPlaying ?? false` |
| idem | 299 | `wavy: root.player?.isPlaying` | `root.player?.isPlaying ?? false` |
| idem | 84–90 | `Process { command: ["ii-shim", "fetch", targetFile, "--out", …] }` por canción | Si `artUrl` empieza con `file:` → usarla tal cual (`downloaded = true`), **sin proceso**. Si es `https:` → `Image { source: artUrl; cache: true }` directo (Qt descarga en su hilo); sin `ii-shim`. |
| `modules/ii/background/widgets/media/MediaWidget.qml` | 73 | Carga `Directories.coverArt/<md5>` que nunca se crea para carátulas locales | Misma regla: local directo; la ruta de caché solo para `https:` ya descargadas. |
| `ColorQuantizer` (donde se use con la carátula) | — | Corre aunque la imagen no exista | Activar solo con `status === Image.Ready`. |

Y en `services/MprisController.qml` (o donde se elija el reproductor activo): si la clave del jugador activo desaparece,
pasar al siguiente **sin** dejar `player` en `undefined` a mitad de un *binding* (usar `activePlayer` de A1.2).

**Aceptación:** `settings-pages.ps1` + 10 min de `churn.html` ⇒ 0 avisos nuevos de `PlayerControl`/`MediaWidget`/`colorquantizer`
en `%TEMP%\quickshell\by-pid\<pid>\log.log`; 0 procesos `ii-shim fetch` lanzados por carátulas locales (comprobar con
`--log-rules "quickshell.process.start.info=true"`).

---

<a id="a3"></a>
## A3 · Manejador de crashes, minidumps y símbolos — P0, 0.6.1, esfuerzo M

Hoy un crash solo deja una línea en el Visor de eventos. Con esto, el próximo error se encuentra en minutos.

### A3.1 En la shell (fork): `src/win32/crash.cpp` (nuevo)

- `installCrashHandler()` como **primera** línea de `main` en Windows (`src/win32/init.cpp` o el `main` de Quickshell con
  `#ifdef _WIN32`).
- Instala `SetUnhandledExceptionFilter`, `std::set_terminate`, `_set_invalid_parameter_handler`, `_set_purecall_handler`
  y `signal(SIGABRT, …)`; todos acaban en el mismo camino.
- Crea **al arrancar** un hilo "escritor" dormido (esperando un evento). El filtro no escribe nada desde el hilo que
  crasheó (puede tener la pila o el *heap* rotos): le pasa `EXCEPTION_POINTERS` + id de hilo al escritor y espera ≤ 10 s.
- El escritor guarda en `%LOCALAPPDATA%\ii-windows\crashes\`:
  - `quickshell-<versión>-<aaaammdd-hhmmss>.dmp` con `MiniDumpWriteDump(…, MiniDumpWithThreadInfo |
    MiniDumpWithUnloadedModules | MiniDumpWithIndirectlyReferencedMemory | MiniDumpScanMemory, …)` (1–5 MB).
  - `….json`:
    ```json
    {"schema":1,"app":"quickshell","version":"0.6.1-20261102-abc1234","code":"0xC0000005",
     "where":"quickshell.exe+0x19ed74","subsystem":"mpris","thread":"mpris-worker",
     "uptimeSeconds":2311,"renderLoop":"threaded","gpu":"AMD Radeon(TM) Graphics","windowsBuild":"26200.6899",
     "dump":"quickshell-0.6.1-20261102-211951.dmp"}
    ```
- Después: `TerminateProcess(GetCurrentProcess(), code)`. Así **no** actúa WER (que tuvo el proceso suspendido 4–5 s
  y provocó el falso `hang:` del 25/10) y el host ve la salida al instante.
- **Subsistema:** un marcador `thread_local const char* currentSubsystem` con un RAII `ScopedSubsystem s("mpris")` en la
  entrada de cada hilo propio (worker de mpris, lector de notificaciones, bluetooth, red…) y alrededor de cada *callback*
  nativo del hilo GUI (WinEvent de `toplevels.cpp`, `trayProc`, `sinkWndProc`, mensajes de `panel_window.cpp`). Con eso
  el JSON dice qué parte falló **sin símbolos**, y A4 puede apagar justo esa parte.
- Límite: se guardan los 5 últimos; se borran a los 14 días. **Privacidad:** el dump puede contener títulos de ventanas y
  textos de notificaciones → nunca sale de la PC sin permiso explícito (ver G3).
- Prueba: `II_TEST_CRASH=null|terminate|abort|mpris` (solo con `II_DATA_DIR`, como los demás interruptores de prueba de
  D22) provoca el fallo a los N segundos.

### A3.2 Símbolos (PDB) en cada release

- Fork y host, en *release*: compilar con `/Zi` y enlazar con `/DEBUG:FULL /OPT:REF /OPT:ICF /PDBALTPATH:%_PDB%`
  (`/OPT:*` mantiene el binario igual de optimizado; `/PDBALTPATH` evita que el exe lleve la ruta `C:\Users\<nombre>\…`
  de la PC que compila).
- `tools/package/make-package.ps1`: junta `quickshell.pdb`, `ii-host.pdb`, `ii-shim.pdb`, `ii-launcher.pdb` en
  `out\ii-windows-<versión>-symbols.zip` (**no** dentro del paquete instalable).
- `tools/package/release-check.ps1`: comprueba que el GUID/edad de cada PDB coincide con el *debug directory* de su exe
  (`llvm-readobj --coff-debug-directory`). Falla con `-Strict` si no.
- `docs/PUBLICAR.md`: subir el zip de símbolos como asset de la release.
- `tools/dev/symbolize.ps1 <archivo.json|módulo+offset> [-Version x]`: baja (o usa local) el zip de símbolos de esa
  versión y traduce con `llvm-symbolizer --obj=<exe> 0x<offset>`; con un `.dmp`, usa `cdb -z <dmp> -c "!analyze -v; q"`
  si está instalado (WinDbg).
- Para versiones viejas sin PDB queda `tools/dev/crash-locate.py` (la herramienta de [anexos](anexos/crash-locate.py),
  pasada a `tools/dev/`).
- De paso: el `quickshell.exe` publicado lleva 21 rutas de la máquina que compiló (`C:\Users\Admin\dev\…`, por
  `__FILE__` y el `source_location` de C++/WinRT). Quitarlas con `/clang:-ffile-prefix-map=<raíz>=.` y
  `WINRT_NO_SOURCE_LOCATION` ([anexo §6](anexos/evidencia-crash.md#6-detalle-menor-encontrado-de-paso)).

### A3.3 En el host

- `onShellExited` (`host/src/main.cpp:1099`): si el código es un NTSTATUS de error (`>= 0xC0000000`), leer el JSON más
  nuevo de `crashes\` creado después de `shellStartedAt` y registrar:
  `crash: quickshell.exe+0x19ed74 (C0000005) en mpris, 2311 s después de arrancar`.
- Contador por **firma** (`where` + `subsystem`) en `state.ini [crashes]`, que usa A4.
- Si un crash llega sin JSON (el manejador no alcanzó a escribir), igual se cuenta con firma `unknown`.

---

<a id="a4"></a>
## A4 · Política de reinicios con modo seguro — P0 (mínimo en 0.6.1, completo en 0.7.0), esfuerzo M

**Hoy** (`main.cpp:1119-1134`): cada crash → relanzar a 1 s; 3 crashes en 60 s → `abortLaunch` con un cuadro de mensaje.
Con crashes cada 10 min: bucle infinito.

**Propuesta** (ventana deslizante de 30 min, contando crashes de la shell, no los reinicios pedidos por el usuario):

| Crashes en 30 min | Qué hace ii-host | Qué ve el usuario |
|---|---|---|
| 1 | Relanza enseguida (como hoy). | Aviso de ii al volver: "ii se cerró por un error y se recuperó en 2 s. [Ver detalles] [Reportar]". |
| 2 | Relanza enseguida. | El mismo aviso, con "Si vuelve a pasar, ii desactivará la parte que falla". |
| 3 con la **misma firma** | Relanza con **esa parte apagada**: `II_DISABLE=mpris` (u otra según `subsystem`). | Píldora persistente: "Modo seguro: la música de ii está apagada por un error. [Reactivar] [Reportar]". |
| 4 (cualquier firma) | Relanza en **modo seguro completo**: `II_SAFE_MODE=1` (render loop *basic*, sin mpris, sin lector de notificaciones, sin miniaturas DWM, sin cava, sin widgets animados). | "ii está en modo seguro. [Reportar] [Volver a la versión anterior] [Salir de ii]". |
| 5 | Devuelve la barra de Windows y se detiene (como `abortLaunch`, pero con una ventana propia en vez de `MessageBox`). | Ventana con botones: Reportar (abre el reporte con el JSON), Volver a la versión anterior (si hay), Desinstalar, Cerrar. |

- **Fork:** cada *Backend* que se pueda apagar comprueba `II_DISABLE` (lista separada por comas) antes de arrancar:
  `mpris`, `notifications`, `tray`, `bluetooth`, `network`, `screencopy`, `toplevels-thumbnails`, `cava`. Apagado = modelo
  vacío y un log `disabled by II_DISABLE`. La bandeja (`tray`) no se apaga nunca sin avisar, porque sin ella el usuario
  pierde iconos.
- **QML:** `services/SafeMode.qml` (lee las variables con `Quickshell.env()`), píldora en la barra y tarjeta en el panel
  derecho.
- El modo seguro de una firma **dura hasta** que el usuario pulsa *Reactivar* o hasta que llega una versión nueva
  (el host borra `state.ini [crashes]` al cambiar de versión).
- Mientras relanza: hoy `exposeExplorer` muestra la barra de Windows unos segundos (parpadeo). Para reinicios
  inmediatos, en su lugar mostrar la portada mínima "ii se está recuperando…" durante ≤ 3 s (ya existe `splash.cpp`);
  si la shell no vuelve en 3 s, entonces sí devolver Explorer.
- **0.6.1 (mínimo):** el aviso "se recuperó" (filas 1–2) y `II_DISABLE` por firma (fila 3). El resto en la 0.7.0.

---

<a id="a5"></a>
## A5 · El hilo principal de `ii-host` no debe esperar a nadie — P1, 0.6.1 (medir) / 0.7.0 (arreglar), esfuerzo S–M

**Evidencia:** `slow: keyboard::refreshContext took 3438 ms` (y 1125, 4781 ms) justo durante cada crash. En ese hilo
corren el atajo de pánico (`WM_HOTKEY`), el latido, el *watchdog*, la portada y la tecla Windows suelta.

`refreshContext()` (`host/src/keyboard.cpp:246`) hace cada segundo y en cada cambio de primer plano: `FindWindowW`,
`loadRules()` (ya con caché por fecha), `GetClassNameW`, `GetWindowRect`, `MonitorFromWindow`, **`SHQueryUserNotificationState()`**
y `lowerExeName()`. La única que habla con otro proceso que puede estar trabado es `SHQueryUserNotificationState` (le
pregunta a Explorer; Explorer a su vez puede estar esperando a las ventanas AppBar de la shell suspendida).

1. **Medir primero (0.6.1):** `SlowStep` por sub-paso dentro de `refreshContext` (umbral 100 ms), para confirmar cuál es.
2. **Arreglo (0.7.0):**
   - `SHQueryUserNotificationState` en un hilo aparte con resultado en un `std::atomic<int>` y como máximo una consulta en
     vuelo; el hilo principal usa el último valor. Si la consulta tarda > 500 ms, se registra una vez y se sigue con el
     valor anterior.
   - La reconciliación de 1 s solo cuando cambió algo (primer plano, `shortcuts.ini`, la shell) en vez de siempre.
   - Revisar con la misma regla `watchShell()` (`EnumWindows` + `SendMessageCallbackW` ya es asíncrono, bien) y
     `taskbar::hide/reapply` (llegó a 313–719 ms: `SHAppBarMessage`/`SetWindowPos` a ventanas de Explorer). Todo lo que
     hable con Explorer, con `SendMessageTimeout(SMTO_ABORTIFHUNG, ≤ 500 ms)` o en un hilo.
3. **Aceptación:** 8 h de uso normal + un crash provocado (`II_TEST_CRASH`) ⇒ ninguna línea `slow:` > 250 ms en el hilo
   principal; el atajo de pánico responde en < 300 ms durante el crash.

---

<a id="a6"></a>
## A6 · Auditoría del resto del código nativo — P1, 0.7.0, esfuerzo M

Misma clase de error buscada en todo el fork y el host:

| Archivo | Qué revisar |
|---|---|
| `src/win32/services/bluetooth.cpp`, `battery.cpp`, `network.cpp` | Getters WinRT/COM sin comprobar nulo; `.get()` sin tiempo límite; eventos sin *revoker*; callbacks que tocan objetos Qt fuera del hilo GUI. |
| `src/win32/services/notifications.cpp` | Ya comprueba nulos (bien). Revisar `GetTextElements()` y el bucle `while (true)` sin salida (un `stopping` para cerrar limpio). |
| `src/win32/virtualdesktops.cpp` | Interfaces **no documentadas** de Explorer con IIDs por build: comprobar `QueryInterface` y la build antes de cada uso; si una actualización de Windows cambia los IIDs, desactivar la función en vez de crashear. |
| `src/win32/services/tray.cpp` | `saveIcon()` con `HICON` de otros procesos: validar con `GetIconInfo` antes; ya hay aviso `fromWinHICON failed` en el log. Iconos animados (Discord, descargas): no escribir un PNG por cada cuadro (caché por hash del bitmap). |
| `src/win32/toplevels.cpp` | `SHGetPropertyStoreForWindow` con ventanas colgadas (puede bloquear el GUI): ver [D1](05-rendimiento.md#d1). |
| `src/win32/panel_window.cpp`, `native.cpp` | Mensajes con `lParam` de otros procesos; `result` nulo en mensajes encolados (ya aprendido: "Qt passes result=nullptr for queued messages"). |
| `host/src/*.cpp` | Mismo criterio en `vdesk.cpp`, `capture.cpp`, `fileops.cpp`, `cava.cpp`, `brightness.cpp`. |

- `tools/dev/check-winrt-null.py` (nuevo): heurística que marca, en archivos que incluyen `<winrt/…>`, una variable
  asignada desde un getter que devuelve una *runtime class* y usada con `.` en la línea siguiente sin un `if (x)`. No es
  perfecto; sirve para revisar.
- **Día de caos** (en Sandbox y luego en la PC real, con ii corriendo, 1 h cada uno): reiniciar Explorer 5 veces,
  suspender/reanudar 3 veces, bloquear/desbloquear, conectar/desconectar monitor, cambiar DPI 100→150→125 %, apagar y
  encender Wi-Fi y Bluetooth, desenchufar audífonos, 50 notificaciones en 10 s (`ii-shim notify-send` en bucle),
  Spotify + YouTube + Brave a la vez, 30 ventanas abiertas y cerradas por script. Criterio: 0 crashes; si hay alguno, sale
  con JSON y firma (A3).

---

<a id="a7"></a>
## A7 · "Verificada" de verdad y ofrecer volver a la versión anterior — P1, 0.7.0, esfuerzo S–M

**Hoy:** `rollout::markVerified()` se llama en `onShellReady` (primer fondo visible) → la 0.6.0 quedó "verificada" y
crasheaba 38 min después. El *launcher* solo vuelve atrás si la versión no llega a "lista".

**Propuesta** (`host/src/rollout.*`, `host/src/launcher.cpp`, `tools/package/ii-runtime.ps1`):

- Estados: `pending` → **`ready`** (mostró el fondo; el *launcher* ya puede irse) → `verified` (10 min encendida sin
  crash, o un cierre limpio de sesión después de estar `ready`). `current.txt` gana `crashes=<n>` para la versión activa.
- `launcher.cpp:162-201`: esperar a `ready` en vez de `verified` (el *timeout* de 180 s sigue igual).
- Si la versión activa está en `ready` (no `verified`) y suma **3 crashes** (A3 cuenta), el host muestra:
  "La versión 0.7.0 se cerró 3 veces desde que se instaló. ¿Volver a la 0.6.1? [Volver] [Seguir con 0.7.0]".
  *Volver* = `ii-host --rollback` → `Invoke-IiRollback` en nativo (`rollout::write` con active↔previous,
  `state=rolled-back`) y relanzar con `ii-launcher`.
- `Remove-IiOldVersions` (y su equivalente nativo de B6) solo borra versiones viejas **después** de `verified`.

---

<a id="a8"></a>
## A8 · Pruebas de estrés y regresión — P0, 0.6.1, esfuerzo M

| Prueba (nueva) | Dónde | Qué comprueba | Criterio |
|---|---|---|---|
| `ii-mpris-stress.exe` | Fork, `src/win32/services/mpris_stress.cpp` (objetivo como `ii-hardware-test`) | Crea/destruye `MediaPlayer` + SMTC con silencio, 20/s, 10 min, con el `Backend` de mpris en el mismo proceso. | 0 crashes; `players` vacío al final; *handles*/memoria ±5 %. |
| `tests/media/churn.html` + `tools/dev/browser-churn.ps1` | PC real | Abre la página en Brave/Chrome/Edge (3 pestañas), mira `host.log` y el log de la shell 2 h. | 0 `exited with code`, 0 avisos nuevos. |
| `tools/sandbox/tests/test-crash-handler.ps1` | Sandbox | `II_TEST_CRASH=null` → `.dmp` + `.json` escritos, salida en < 1 s, host relanza; 3 veces con la misma firma → `II_DISABLE` aplicado; 4 → modo seguro; 5 → se detiene y restaura. | Todas en verde. |
| `tools/sandbox/tests/test-host-crash-policy.ps1` | Sandbox (shell falsa) | La tabla de A4 con una shell falsa que sale con `0xC0000005` N veces y distintas firmas. | Igual a la tabla. |
| `tools/dev/soak.ps1` | PC real | 8 h de uso: memoria privada y CPU de `quickshell.exe` cada 5 min a un CSV, `slow:` del host. | Memoria plana (±10 %), sin `slow:` > 250 ms. |

Todas entran en `tools/sandbox/run-local-suite.ps1` (las de PC real, con `-RealPc`).

---

<a id="a9"></a>
## A9 · Recuperar la confianza: que el usuario entienda y decida — P1, 0.6.1/0.7.0, esfuerzo S–M

1. **Portada que se puede saltar** (`host/src/splash.cpp`): clic o Esc ⇒ la portada se desvanece y se ve el escritorio
   de Windows mientras ii termina de cargar (la tecla Windows vuelve a ser de Windows hasta que ii esté lista).
   Hoy solo se va con la shell lista o a los 90 s (`TIMEOUT_MS = 90000`).
2. **Portada con tope visual de 12 s:** pasado ese tiempo se desvanece igual y queda una píldora pequeña "ii está
   terminando de cargar…" en una esquina (ventana propia del host, sin robar foco). El *watchdog* de 45/90 s no cambia.
3. **"La última vez ii tuvo problemas"**: si la sesión anterior terminó con crashes, modo seguro o pánico, la portada
   muestra 3 botones: **Iniciar normal** (por defecto en 5 s) · **Modo seguro** · **Hoy no** (devuelve Windows y no
   vuelve a arrancar hasta la próxima sesión). Así no hace falta el atajo de pánico al entrar.
4. **"Pausar ii por hoy"** en el menú de sesión y en el acceso "Rescate de ii": queda registrado como decisión del
   usuario (`shutdown (0)` + `state.ini [pause] until=<fin del día>`), no como error.
5. **Aviso al recuperarse** (A4 filas 1–2), con [Ver detalles] que abre una ventana corta en español: qué falló
   (subsistema), cuándo, qué hizo ii, y botón Reportar.
6. **Reporte en 1 clic** (`tools/rescue/ii-report.ps1`): incluye los JSON de `crashes\` de los últimos 7 días (sin el
   `.dmp`, salvo que el usuario marque la casilla "Adjuntar el volcado de memoria (puede contener títulos de ventanas)").
