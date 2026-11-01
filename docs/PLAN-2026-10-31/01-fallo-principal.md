# 01 · El fallo "ii se cierra y se abre solo mientras navego"

> **En simple:** no es que ii "decida" reiniciarse. El programa de la interfaz (`quickshell.exe`) **se rompe de verdad**
> (un error de memoria, código `0xC0000005`) dentro del código que lee **la música y los videos que suenan en Windows**.
> Cuando navegas por X, YouTube o Reels en Brave/Chrome, el navegador abre y cierra "sesiones de multimedia" cada pocos
> segundos (cada video del feed es una). Si una sesión se cierra justo mientras ii la está leyendo, Windows le devuelve
> "nada" y ii intenta usar ese "nada" → crash. `ii-host` la vuelve a abrir (por eso "se cierra y se abre solo"), y con
> varios crashes seguidos se rinde y devuelve la barra de Windows (el "se crashea por completo").
>
> El error existe **desde la 0.1.3** (mismo sitio del código); la 0.6.0 no lo creó, solo coincidió con más uso del
> navegador. El arreglo es pequeño y está en [02 · A1](02-estabilidad.md#a1).

---

## 1. Lo que pasó en esta PC (cronología real)

Fuente: `%LOCALAPPDATA%\ii-windows\host.log` (12 470 líneas, del 08/10 al 29/10) y el Visor de eventos de Windows.

| Hora (25/10/2026) | Qué pasó | Fuente |
|---|---|---|
| 20:40 | Se instala la **0.6.0-20261025-6d92550** (`install.log`). | install.log |
| 20:41:12 | La shell queda lista (pid 3304). Durante la noche: osu!, PowerToys, Antigravity, Brave. | host.log |
| **21:19:51** | **Crash** de `quickshell.exe`: `0xc0000005` en `quickshell.exe+0x19ed74`. | Evento 1000 (Application Error) |
| 21:19:54 | `slow: keyboard::refreshContext took 3438 ms` (el host se quedó trabado mientras Windows atendía el crash). | host.log |
| 21:19:55 | `shell: exited with code 3221225477` (= `0xC0000005`). ii-host relanza en 1 s; lista a las 21:19:58. | host.log |
| **21:30:02** | **Mismo crash, mismo offset `0x19ed74`.** Relanzada, lista 21:30:07. | Evento 1000 |
| **21:38:22** | **Mismo crash otra vez.** El navegador al frente: `brave.exe "(1) … / X - Brave"`. | Evento 1000 |
| 21:38:27 | El latido (0.6.0) informa `hang: … silent for 5469 ms`: no era un congelamiento, era Windows (WER) escribiendo el informe del crash con el proceso suspendido. Barra de Windows devuelta, shell nueva lista a las 21:38:34. | host.log |
| 21:38:39 | **Atajo de pánico** (Ctrl+Alt+Mayús+R): el usuario lo apaga. | host.log |
| 26/10 → 29/10 | Pánico en casi todos los arranques, varias veces **1–3 s después de lanzar** (aún cargando). | host.log |
| 29/10 14:46 | `rescue.ps1` y después **desinstalación** (la carpeta `Programs\ii-windows` ya no existe). | host.log, disco |

**Lección:** un crash que se repite cada 10 minutos destruye la confianza aunque ii "se recupere solo". El arreglo debe
venir con (a) un manejador de crashes que deje rastro, (b) un modo seguro y (c) un aviso claro de qué pasó.

---

## 2. La prueba: dónde exactamente se rompe

### 2.1 Visor de eventos (los 3 crashes de la 0.6.0 son idénticos)

```
Nombre de aplicación con errores: quickshell.exe, versión: 0.3.1.0, marca de tiempo: 0x6ade8ef9
Nombre del módulo con errores: quickshell.exe, versión: 0.3.1.0, marca de tiempo: 0x6ade8ef9
Código de excepción: 0xc0000005
Desplazamiento con errores: 0x000000000019ed74
Ruta: …\Programs\ii-windows\versions\0.6.0-20261025-6d92550\quickshell\quickshell.exe
Id. de informe: f7973385-…  /  e680891a-…  /  fb8e63d2-…
```

El módulo que falla es `quickshell.exe` mismo (no una DLL de Qt ni un driver), y siempre en el mismo byte: es un error
determinista de **nuestro** código.

### 2.2 El binario exacto

Se descargó `quickshell.exe` del asset de la release v0.6.0 (marca de tiempo **0x6ADE8EF9**, la misma del evento). No
trae PDB, así que se ubicó la función con la tabla `.pdata` (excepciones x64) y se desensambló con `llvm-objdump`
(herramienta: [anexos/crash-locate.py](anexos/crash-locate.py)). Función que contiene el offset: `0x19e0c0–0x19f9da`.

```asm
0019ed01  mov  rcx, [rbp+1D0h]        ; rcx = session (IGlobalSystemMediaTransportControlsSession)
0019ed2b  mov  rax, [rcx]             ; vtable
0019ed35  call qword ptr [rax+48h]    ; vtable+0x48 = GetPlaybackInfo(&out)   → devuelve S_OK y out = NULL
0019ed40  mov  rcx, [rbp+270h]        ; rcx = info  (NULL)
0019ed58  mov  dword [rbp+258h], 440h ; línea 1088 del header de C++/WinRT (source_location)
0019ed74  mov  rax, [rcx]   <<<<<<<<  ; leer la vtable de NULL → 0xC0000005
0019ed7e  call qword ptr [rax+38h]    ; vtable+0x38 = get_PlaybackStatus
0019ed8f  cmp  eax, 5 / cmp eax, 4    ; Paused = 5, Playing = 4
0019ede3  call qword ptr [rax+30h]    ; info.Controls()  …luego IsPlayEnabled, IsPauseEnabled…
```

Mapa de la vtable (interfaces de `Windows.Media.Control`, los 6 primeros métodos son `IInspectable`):

| Offset | IGlobalSystemMediaTransportControlsSession | …SessionPlaybackInfo | …SessionTimelineProperties |
|---|---|---|---|
| 0x30 | `SourceAppUserModelId` | `Controls` | `StartTime` |
| 0x38 | `TryGetMediaPropertiesAsync` | **`PlaybackStatus`** | `EndTime` |
| 0x40 | **`GetTimelineProperties`** | `PlaybackType` | `MinSeekTime` |
| 0x48 | **`GetPlaybackInfo`** | `AutoRepeatMode` | `MaxSeekTime` |

Eso es, línea por línea, `quickshell/src/win32/services/mpris.cpp`:

```cpp
183		try {
184			auto info = session.GetPlaybackInfo();      // puede ser nulo
185			switch (info.PlaybackStatus()) {             // ← 0x19ed74: crash
```

### 2.3 No es nuevo: los crashes de octubre en versiones viejas son el mismo error

Se bajó con peticiones por rango solo el `quickshell.exe` de cada release y se miró el offset de cada crash viejo:

| Fecha | Versión (marca de tiempo) | Offset | Qué es |
|---|---|---|---|
| 11/10 16:08 | **v0.1.3** (`0x6ac965ad`) | `0x1db66b` | `consume_…PlaybackInfo::PlaybackStatus()` con `this` nulo (misma línea 1088 del header). |
| 11/10 18:52 | build de la 0.2.0 (`0x6acc1af1`) | `0x19ba7c` | Dentro de `pushState`: `call [rax+40h]` = **`GetTimelineProperties()`** devolvió nulo y se usó. |
| 08/10 16:30 | build de desarrollo (`0x6ac7d7fb`) | `0x1d7cbb` | Sin binario para comprobar. |
| 25/10 ×3 | **v0.6.0** (`0x6ade8ef9`) | `0x19ed74` | `GetPlaybackInfo()` nulo → `PlaybackStatus()`. |

De 6 crashes registrados en esta PC, **5 se identificaron y todos son esta misma función** (`Backend::pushState`).

---

## 3. Causa raíz (técnica)

1. **Los getters de WinRT pueden devolver nulo sin lanzar excepción.** `GetPlaybackInfo()`, `GetTimelineProperties()`
   e `info.Controls()` devuelven `S_OK` con un puntero nulo cuando la sesión ya se cerró del lado del navegador. C++/WinRT
   entonces da un objeto proyectado nulo, y cualquier llamada sobre él lee la dirección 0. El mismo proyecto ya lo sabía
   en `notifications.cpp:346` ("WinRT getters may hand back null references; calling through one crashes"), pero
   `mpris.cpp` no aplica esa regla.
2. **`catch (...)` no atrapa esto.** El fork compila con `/EHsc` (`src/win32/CMakeLists.txt:69`): solo atrapa
   excepciones de C++. Una violación de acceso es una excepción SEH: el `try/catch (...)` de la línea 183 no sirve y el
   proceso entero muere.
3. **La carrera es frecuente al navegar** porque:
   - `pushState()` corre en el *thread pool* de WinRT **por cada evento** (`MediaPropertiesChanged`, `PlaybackInfoChanged`,
     `TimelinePropertiesChanged`): varias copias a la vez para la misma sesión, cada una bloqueada en `.get()`.
   - Los manejadores de eventos **nunca se desuscriben** (`subscribe()` descarta los tokens): una sesión que ya se fue
     sigue disparando eventos un rato.
   - La clave de cada sesión es `app` o `app#n` **según el orden** en `GetSessions()`. Si se cierra la primera pestaña
     con video, la segunda pasa de `Brave#1` a `Brave`, y un evento viejo busca por nombre y encuentra **otra** sesión, o
     una que está muriendo.
   - Chromium/Brave crea una sesión de SMTC por cada elemento multimedia "controlable" (videos con sonido, Media Session API).
     En el feed de X o en Shorts/Reels eso es una sesión nueva cada pocos segundos. Los logs de la shell
     (`%TEMP%\quickshell\by-pid\<pid>\log.log`) muestran justo eso antes de cada crash: una carátula nueva cada 1–10 s.
4. **Por qué termina "crasheando por completo":** `ii-host` relanza la shell 1 s después de cada crash
   (`main.cpp:1133`); si hay 3 crashes en menos de 60 s se rinde con "ii no pudo mantener su shell" (`main.cpp:1128`).
   Con crashes cada 8–40 minutos nunca se rinde: el usuario ve cierres y aperturas sin fin, cada uno con un parpadeo de la
   barra de Windows, hasta que lo apaga a mano.

### Lo que **no** es la causa (descartado con evidencia)

- **El latido nuevo de la 0.6.0** no mató una shell sana: el único `hang:` (21:38:27) ocurrió 5 s después del crash de
  las 21:38:22, mientras WER tenía el proceso suspendido. Igual conviene que el host distinga "crasheando" de "congelado"
  ([A3](02-estabilidad.md#a3)).
- **El render loop *threaded*** (nuevo en 0.6.0): el crash está en código propio y ya ocurría en la 0.1.3/0.2.0 con el
  loop *basic*.
- **Drivers de la GPU:** el módulo que falla no es una DLL de AMD, D3D11 ni Qt.

---

## 4. Otros problemas encontrados en el mismo incidente

| # | Problema | Evidencia | Va en |
|---|---|---|---|
| 1 | `keyboard::refreshContext` bloqueó el hilo principal del host **1,1 / 3,4 / 4,8 s** justo en cada crash (atajo de pánico, latido y portada dependen de ese hilo). Sospechoso: `SHQueryUserNotificationState()` (pregunta a Explorer, que a su vez espera a las ventanas AppBar colgadas de la shell suspendida). | host.log 21:19:54, 21:30:04, 21:38:27 | [A5](02-estabilidad.md#a5) |
| 2 | Sin minidump, sin PDB publicados, sin firma del crash en el log: hubo que desensamblar el exe a mano. | — | [A3](02-estabilidad.md#a3) |
| 3 | La versión queda "verificada" en cuanto muestra el fondo una vez; 38 min después crasheaba y seguía "verificada". | `rollout::markVerified` en `onShellReady` | [A7](02-estabilidad.md#a7) |
| 4 | Avisos QML en cada cambio de canción: `PlayerControl.qml[85]`, `[147]`, `[299]` (`Unable to assign [undefined]`). | log de la shell | [A2](02-estabilidad.md#a2) |
| 5 | La carátula se "descarga" con un proceso `ii-shim fetch` **por canción**; para carátulas locales (`file:///…\Temp\ii-windows\mpris\*.img`) `fetch` solo acepta HTTPS y falla: `MediaWidget.qml[73]: Cannot open …/coverart/5e54…` y `colorquantizer: Failed to load image`, repetido en bucle. | log de la shell | [A2](02-estabilidad.md#a2), [D3](05-rendimiento.md#d3) |
| 6 | Carátulas guardadas en `%TEMP%\ii-windows\mpris` sin límite (34 archivos tras una noche), caché de Quickshell de **151 MB / 18 929 archivos** que quedó tras desinstalar. | disco | [D4](05-rendimiento.md#d4) |
| 7 | Al arrancar con Windows la portada tapó la pantalla **10,9 / 12,9 / 27,6 s** sin forma de saltarla (la tecla Windows queda retenida). | host.log 26–27/10 | [A9](02-estabilidad.md#a9), [D5](05-rendimiento.md#d5) |
| 8 | `QPixmap::fromWinHICON(), failed to GetIconInfo()` con iconos de bandeja/ventana inválidos. | log de la shell | [D7](05-rendimiento.md#d7) |

---

## 5. Cómo reproducirlo antes de arreglarlo (para comprobar el arreglo después)

1. **Navegador real (lo más fiel):** Brave o Chrome, sesión iniciada en X, bajar por el feed con videos 15–30 min con ii
   corriendo. Contar en `host.log` las líneas `exited with code 3221225477`.
2. **Página de estrés local** (determinista, sin cuentas): `tests/media/churn.html` (nuevo, ver [A8](02-estabilidad.md#a8))
   que crea un `<audio>` con un WAV de silencio en *data URI*, le pone `navigator.mediaSession.metadata`, lo reproduce,
   lo pausa y lo **elimina** cada 200–400 ms, en 3 pestañas a la vez. Sin sonido audible: se usa un WAV de silencio a
   volumen normal, porque Chromium normalmente no anuncia a Windows los medios silenciados con `muted` (comprobarlo en
   la primera corrida mirando si aparece la sesión en el panel de música de ii).
3. **Estrés nativo** (sin navegador, sirve en Windows Sandbox): un exe de prueba que crea y destruye
   `Windows.Media.Playback.MediaPlayer` con `SystemMediaTransportControls` y propiedades de pantalla, 20 veces por
   segundo, con el WAV de silencio (la memoria del proyecto ya tiene esa técnica: `MediaPlaybackItem` + display properties).

Criterio: con el código actual, (1) o (2) debe crashear en minutos; con el arreglo, **0 crashes en 2 horas**.
