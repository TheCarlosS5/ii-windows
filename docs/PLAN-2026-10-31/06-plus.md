# 06 · Bloque E — El "Plus": por qué alguien se cambiaría a ii-windows

> **En simple:** que se vea bonito ya lo tiene. El "Plus" es lo que **ahorra tiempo todos los días** y que Windows no
> trae: una sola búsqueda para todo, modos que se ponen solos (clase, trabajo, juego), un panel "Hoy" con tu día,
> una galería para compartir widgets y escritorios, y detalles que se notan (el micrófono, el dock, las capturas).

Cada idea trae: **para qué sirve a diario**, **qué hace**, **cómo** (APIs y archivos), **MVP** (lo mínimo que ya vale) y
esfuerzo (S/M/L/XL). Prioridad: ★★★ = el Plus principal (0.9.0), ★★ = 0.9/1.0, ★ = después de la 1.0.

---

<a id="e1"></a>
## E1 · ★★★ "Buscar todo": la tecla Windows lo hace todo — esfuerzo L

**A diario:** abrir apps, archivos, ajustes, hacer cuentas, convertir monedas, cambiar de ventana, apagar, instalar una
app… sin buscar en menús. Reemplaza Inicio + búsqueda de Windows + PowerToys Run con el estilo de ii.

**Qué hace:** el lanzador de ii (ya busca apps, calcula y tiene emojis) pasa a tener **proveedores**:

| Proveedor | Ejemplo | Cómo |
|---|---|---|
| Apps (ya) | "spoti" | `AppSearch`/índice actual + `AppUsage` (frecuencia y recencia) |
| Ventanas abiertas | "brave x" | `ToplevelManager` (título + app) → activar |
| Archivos | "informe sena" | `ii-shim search files <texto>` (nuevo, C++): consulta OLE DB al índice de Windows (`Provider=Search.CollatorDSO`, `SELECT System.ItemPathDisplay … FROM SystemIndex WHERE CONTAINS(System.FileName,'"informe*"') AND SCOPE='file:C:/Users/<usuario>'`), devuelve JSON. Si está instalado **Everything**, usar su IPC (más rápido). |
| Ajustes de ii | "barra abajo" | El índice de [C3](04-configuracion.md#c3) → `openSettings(page)` |
| Ajustes de Windows | "bluetooth", "sonido" | Lista curada en `shared/ms-settings.json` (nombre en español + sinónimos → `ms-settings:bluetooth`, `ms-settings:sound`…) |
| Calculadora y conversiones | "15% de 230", "5 km a millas", "100 usd a cop", "hora en tokio" | La calculadora actual + unidades (tabla local) + monedas (API gratuita sin clave, p. ej. frankfurter.app, con caché diaria) + zonas horarias (Qt `QTimeZone`) |
| Comandos | "bloquear", "suspender", "vaciar papelera", "modo oscuro", "no molestar 1 h", "captura" | Lista en `shared/commands.json` (id, nombres, icono, acción ii-host/QML) |
| Portapapeles | "cb factura" | El historial que ya hay (`cliphist` emulado) |
| Instalar apps | "instalar vlc" | La tienda (winget) en modo búsqueda directa |
| Web | "? clima medellín" | El que ya hay, con el buscador elegido |
| Traducir | "tr hola mundo en" | `ii-shim trans` (ya existe) |

- **Ranking único:** coincidencia difusa (sin tildes) × peso del proveedor × uso reciente; la primera fila siempre la más
  probable. Tab cambia de categoría; Ctrl+Enter = acción secundaria ("abrir ubicación", "ejecutar como admin" con UAC).
- **Rapidez:** cada proveedor responde en su hilo/proceso con *debounce* de 80 ms; los resultados llegan por partes (las
  apps al instante, los archivos cuando estén).
- **MVP (0.9.0):** ventanas abiertas + ajustes de ii y de Windows + comandos + conversiones. Archivos en la 1.0.

---

<a id="e2"></a>
## E2 · ★★★ Modos: Clase, Trabajo, Juego, Presentación, Noche — esfuerzo L

**A diario:** al entrar a la clase virtual del SENA, ii pone "No molestar", silencia lo que no es la clase, deja el
micrófono a mano y muestra el horario; al abrir Valorant, "Juego" quita widgets, animaciones y avisos; a las 10 p. m.,
"Noche" baja el brillo de colores y pone el tema oscuro. Nadie más en Windows hace esto con un clic **o solo**.

**Qué es un modo** (en `config.json` → `modes: [...]`, editable en Configuración > Modos):

```json
{ "id": "clase", "name": "Clase", "icon": "school",
  "apply": { "dnd": "all-but-vip", "theme": "keep", "wallpaper": null, "widgetsLayout": "clase",
             "bar": { "style": "keep" }, "openApps": ["ms-teams"], "volume": { "master": 60 },
             "nightLight": null, "focusTimer": 50 },
  "triggers": [ { "type": "schedule", "days": [1,2,3,4,5], "from": "18:00", "to": "22:00" },
                { "type": "app", "exe": "Teams.exe" } ],
  "exit": "previous" }
```

- **Disparadores:** manual (chip en el panel derecho, la búsqueda "modo clase", atajo), horario, app abierta al frente,
  red Wi-Fi (SSID, del servicio `Network`), monitor externo conectado, con/sin cargador, pantalla compartida o
  presentación (`SHQueryUserNotificationState` = `QUNS_PRESENTATION_MODE`).
- **Qué puede cambiar:** No molestar (con lista VIP), tema claro/oscuro, fondo, **distribución de widgets** (cada modo
  guarda su `desktop-layout.json` en `State/user/modes/<id>/`), estilo de barra, volumen, luz nocturna, plan de energía
  (`powercfg /setactive <guid>`, sin admin para planes existentes; comprobar), abrir/cerrar apps, temporizador de enfoque.
- **"Juego"** une lo que ya existe (ceder atajos, quitar el gancho con anticheat, latido que espera al juego) + pausa
  widgets y cava, No molestar y "modo ligero" mientras dure.
- **Al salir:** vuelve exactamente a como estaba (se guarda un "antes").
- **Archivos:** `services/Modes.qml` (estado, disparadores), `modules/settings/ModesConfig.qml`, chip en
  `sidebarRight`, comandos en E1. El host ayuda con lo que la shell no ve (juego al frente, presentación).
- **MVP:** 4 modos fijos editables (Clase/Trabajo, Juego, Presentación, Noche) con disparador manual + horario + app.

---

<a id="e3"></a>
## E3 · ★★★ Panel "Hoy" y horario de clases — esfuerzo M

**A diario:** al encender el PC ves tu día: clima, próximas clases/reuniones, tareas, batería, lo que sonaba, y un
"tienes clase en 10 min" a tiempo.

- **Tarjeta "Hoy"** arriba del panel izquierdo (o widget del escritorio): saludo, clima ahora + próximas horas, agenda,
  tareas pendientes de hoy, tiempo de pantalla de ayer, una frase.
- **Agenda sin cuentas ni OAuth:** el usuario pega la "dirección secreta en formato iCal" de Google Calendar u Outlook
  (Configuración > Servicios > Calendarios). `ii-shim ics <url>` (nuevo, C++ con el `http.cpp` existente) baja el `.ics`
  cada 15 min, expande eventos repetidos de los próximos 7 días y devuelve JSON. La URL se guarda en el almacén de
  secretos que ya existe (DPAPI, `secret-tool` emulado).
- **Horario de clases** (para estudiantes, sin internet): una semana con bloques (materia, hora, aula/enlace de Meet o
  Teams). Aviso 10 min antes con botón "Unirme" (abre el enlace). Se crea a mano o importando un `.ics`.
- **Recordatorios:** cualquier evento puede avisar N min antes con la notificación de ii.
- **MVP:** tarjeta Hoy con clima + tareas locales + horario de clases manual. ICS en la siguiente.

---

<a id="e4"></a>
## E4 · ★★★ Galería de widgets y temas (y compartir tu escritorio) — esfuerzo XL

**A diario / comunidad:** la gente que "ricea" su PC quiere **descargar y compartir** configuraciones. Un repositorio de
widgets y temas hace que el proyecto crezca solo.

- **Temas** (`.iitheme` = zip): paleta (color semilla o esquema Material), fondo(s), fuentes, estilo de barra/dock,
  sonidos, distribución de widgets. Aplicar con vista previa y **Deshacer**. "Exportar mi escritorio como tema" en
  Configuración > Personalizar (sin datos personales: ni notas, ni tareas, ni rutas de archivos).
- **Widgets de la comunidad:** paquete = `manifest.json` (id, nombre, autor, versión, `minIi`, permisos: `network`,
  `process`, `files`), `widget.qml`, `settings.qml`, captura. Se instalan en `%LOCALAPPDATA%\ii-windows\addons\widgets\<id>`
  y aparecen en la galería de [C2](04-configuracion.md#c2) (el registro acepta entradas de *addons*).
- **Seguridad (QML puede hacer de todo: procesos, archivos):** solo desde un índice curado
  (`TheCarlosS5/ii-windows-gallery`, `index.json` con `sha256` de cada paquete y firmado con la misma clave de B1). Cada
  widget pasa revisión de código por PR. La galería muestra sus permisos ("Este widget usa internet"). Los no firmados
  solo con "Modo desarrollador" activado.
- **Tienda dentro de ii:** pestaña "Widgets y temas" en la tienda actual (hoy de winget), con capturas y "Instalar".
- **MVP:** temas (exportar/importar/aplicar) + 5 widgets oficiales nuevos distribuidos por la galería. Widgets de
  terceros después de la 1.0.

---

<a id="e5"></a>
## E5 · ★★ Audio y llamadas — esfuerzo M

- **Cambiar de salida en 1 clic** (parlantes ↔ audífonos) desde el icono de volumen de la barra: lista de dispositivos de
  `IMMDeviceEnumerator`; cambiar el predeterminado usa la interfaz no documentada `IPolicyConfig` (la usan muchas apps;
  aislarla en `ii-shim audio set-default <id>` con comprobación de build, como `vdesk`).
- **Silenciar el micrófono en todo el sistema** con un atajo (configurable, p. ej. Win+Mayús+A) y botón en la barra:
  `IAudioEndpointVolume::SetMute` del dispositivo de captura predeterminado. Píldora roja "Micrófono silenciado" visible
  siempre que lo esté. Útil en clases y reuniones.
- **Batería de audífonos Bluetooth** (como los PRO60): leer la propiedad de batería del dispositivo que muestra
  Configuración de Windows (clave `{104EA319-6EE2-4701-BD47-8DDBF425BBE5},2`, la que usan las apps de batería Bluetooth;
  comprobar en esta PC) con `CM_Get_DevNode_PropertyW` sobre el nodo del dispositivo; en el menú de Bluetooth y aviso
  con < 20 %. Si el dispositivo no la publica, no se muestra nada.
- Mezclador por app (upstream ya tiene uno): comprobar que lista las sesiones de Windows con nombre e icono correctos.

---

<a id="e6"></a>
## E6 · ★★ Un dock que avisa y recuerda — esfuerzo M

- **"Esta app te necesita":** `RegisterShellHookWindow` + mensaje `SHELLHOOK` → `HSHELL_FLASH` (una app que parpadea: una
  llamada de WhatsApp/Discord, una descarga terminada) → el icono del dock rebota/brilla hasta que la abres. Hoy no se
  recibe (no hay *shell hook* en el fork ni en el host).
- **Contador de no leídos:** ii ya conoce las notificaciones por app → número en el icono del dock (sin APIs nuevas).
- **Archivos recientes por app** en el clic derecho del dock ("Recientes de Word"): `IApplicationDocumentLists::GetList
  (ADLT_RECENT)` con el AUMID de la app (API documentada de listas de salto).
- **Pila de carpeta** (como en macOS): un elemento del dock "Descargas" que abre una cuadrícula con lo último
  descargado; arrastrar desde ahí. **Papelera** en el dock con lleno/vacío (`SHQueryRecycleBinW`) y "Vaciar".
- **Progreso de descargas en el icono** (como la barra de Windows): las apps lo mandan con `ITaskbarList3` a la barra de
  Explorer; investigar en Sandbox si el `Shell_TrayWnd` propio de ii (bandeja, D13) puede observarlo sin inyectar nada.
  Solo si se puede **sin tocar Explorer**; si no, se descarta.

---

<a id="e7"></a>
## E7 · ★★ Capturas que hacen más — esfuerzo M

- Después del recorte (ya existe, con OCR): **anotar** (flecha, rectángulo, resaltador, texto, **pixelar** datos) antes
  de copiar o guardar.
- **Fijar** la captura en pantalla (ventana pequeña siempre encima, se mueve y se cierra con Esc). Útil para copiar algo
  de una imagen a otra ventana.
- **Leer un QR de la pantalla:** seleccionar región → decodificar con ZXing-C++ (Apache-2.0) en `ii-shim qr` → abrir el
  enlace, copiar el texto o unirse al Wi-Fi.
- **Grabar pantalla:** botón que abre la grabación de Recortes de Windows (atajo Win+Mayús+R / URI `ms-screenclip:`;
  comprobar cuál responde en 25H2). Sin meter un codificador propio (pesado); más adelante, si se quiere, `Windows.Graphics.Capture`.
- **Selector de color** (ya existe `hyprpicker` emulado): historial de colores y formatos (HEX, RGB, HSL).

---

<a id="e8"></a>
## E8 · ★★ Portapapeles con memoria — esfuerzo S–M

Sobre el historial actual (Windows): **fijar** elementos, **buscar**, vista previa de imágenes, "pegar como texto sin
formato", OCR de una imagen copiada, y **fragmentos** (`:correo` → tu correo) solo desde la búsqueda (sin un segundo
gancho de teclado, por los anticheat).

---

<a id="e9"></a>
## E9 · ★★ Convive con tus otras apps de personalización — esfuerzo M

**A diario (y menos reportes de error):** muchos usuarios ya tienen StartAllBack (instalado en esta PC), ExplorerPatcher,
Windhawk, TranslucentTB, RoundedTB, Rainmeter, Wallpaper Engine/Lively, PowerToys (instalado: Run, ZoomIt, Quick
Access), Flow Launcher, AutoHotkey, Nilesoft Shell.

- **Configuración > Avanzado > Compatibilidad:** lo que ii detectó (procesos, claves de usuario, servicios), los
  conflictos conocidos y un botón para cada arreglo. Ejemplos: "StartAllBack también cambia la barra de tareas: ii la
  oculta igual; si ves dos barras, desactiva la de StartAllBack"; "PowerToys Run usa Alt+Espacio: sin conflicto";
  "Selector de color de PowerToys usa Win+Mayús+C, igual que ii: ¿cuál prefieres?" (escribe `shortcuts.ini`).
- Tabla de conocimiento en `shared/compat.json` (detección + texto + arreglo), fácil de ampliar con cada reporte.
- El reporte de problemas incluye la lista detectada (ayuda a reproducir).

---

<a id="e10"></a>
## E10 · ★★★ Seguridad visible: micrófono, cámara y ubicación en uso — esfuerzo S (P1, 0.7.0)

**Hueco real:** Windows muestra en **su** barra de tareas cuándo una app usa el micrófono, la cámara o la ubicación.
**ii oculta esa barra**, así que hoy el usuario pierde esos avisos de privacidad. Hay que devolverlos.

- Leer `HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\{microphone,webcam,location}`:
  cada app (empaquetadas por nombre de paquete; las de escritorio bajo `NonPackaged\<ruta con #>`) tiene
  `LastUsedTimeStart` y `LastUsedTimeStop`; **en uso** = `Start > 0` y `Stop == 0`.
- Vigilar con `RegNotifyChangeKeyValue` (subárbol, hilo propio en el host) → mensaje a la shell → píldora en la barra
  "🎙 Discord" / "📷 Teams" (clic → `ms-settings:privacy-microphone`). Nunca se oculta mientras está en uso.
- Prueba: grabadora de voz de Windows abierta → aparece en < 1 s; cerrada → desaparece.

---

<a id="e11"></a>
## E11 · ★★ Bienestar digital — esfuerzo M

Sobre "Tiempo de pantalla" (ya existe en el panel derecho): metas por app o categoría con aviso amable ("Llevas 2 h en
YouTube hoy"), resumen semanal el domingo, recordatorio 20-20-20 para los ojos, sesiones de enfoque con estadísticas
(el pomodoro ya existe). Todo local, nada sale de la PC.

---

<a id="e12"></a>
## E12 · ★★ Notificaciones como en el teléfono — esfuerzo M

Agrupar por app (con contador), deslizar para descartar, buscar en el historial, No molestar con horario y **automático**
al presentar, compartir pantalla o jugar (E2), apps VIP que lo atraviesan, "resumen" al terminar una sesión de enfoque.
(Las ideas 4 y 5 de `docs/IDEAS-OTRAS-SHELLS.md` ya lo describían; los presets de No molestar ya están.)

---

<a id="e13"></a>
## E13 · ★★ Fondos vivos sin esfuerzo — esfuerzo S–M

- **Fondo del día:** Bing (imagen del día), NASA APOD, Wallhaven (API pública), o una carpeta propia que rota cada N min.
  Los colores Material cambian con él (ya existe la generación).
- **Un fondo por escritorio virtual:** Windows 11 lo permite por escritorio (`IVirtualDesktopManagerInternal::SetWallpaper`,
  interfaz no documentada que ya usa `ii-shim vdesk`; mismo cuidado de IIDs por build).
- **Por hora del día:** conjuntos mañana/tarde/noche y tema claro de día, oscuro de noche (o por amanecer/atardecer con
  la ubicación aproximada del clima, sin pedir GPS).

---

<a id="e14"></a>
## E14 · ★ IA opcional, primero local — esfuerzo M–L

Upstream ya trae la barra lateral de IA. Plus para Windows, **apagado por defecto** y sin enviar nada sin permiso:
- Proveedores: local (Ollama / LM Studio en `localhost`), o Gemini/otros con tu clave (ya existe el transporte
  `ii-shim ai-request`).
- Acciones con contexto: "Explicar esta captura" (OCR existente → texto), "Resumir lo copiado", "Traducir lo
  seleccionado", y **ajustes por lenguaje natural** ("pon el dock a la izquierda"): la IA solo puede proponer claves del
  índice de C3; ii muestra el cambio y pide confirmar.

---

<a id="e15"></a>
## E15 · ★ El teléfono en el escritorio (investigación)

Las notificaciones de Enlace Móvil / KDE Connect ya llegan como avisos de Windows y ii las muestra. Investigar si KDE
Connect para Windows expone batería y archivos del teléfono por alguna vía local estable antes de prometer un widget.

---

<a id="e16"></a>
## E16 · ★★ Atajos editables desde la interfaz — esfuerzo M (0.8.0)

Configuración > Atajos: la lista de `shared/actions.json` con su combinación, buscador, **detectar conflictos** (con
Windows, PowerToys y entre sí), "grabar" una combinación nueva, y escribir `shortcuts.ini` (`[policy]`, `[yield]`,
`[unhook]`, `[audio]` también con interruptores: hoy solo se cambian a mano). La chuleta y `docs/ATAJOS.md` siguen
saliendo de la misma lista.

---

## Por qué estas y no otras (para la presentación del proyecto)

| Necesidad diaria | Windows 11 | ii-windows con este plan |
|---|---|---|
| Encontrar cualquier cosa | Inicio + búsqueda lenta con anuncios web | E1: una barra, al instante, sin anuncios |
| Pasar de clase/trabajo a juego | Manual, ajuste por ajuste | E2: un clic o automático |
| Ver mi día | Widgets con noticias que no pedí | E3: mi agenda, mis tareas, mi horario |
| Personalizar y compartir | Temas limitados | E4: temas y widgets de la comunidad, Material You |
| Privacidad | Indicadores en la barra | E10: los mismos avisos, también con ii |
| Saber qué me necesita | Iconos que parpadean | E6: rebote, contador de no leídos, recientes |
| Actualizarse sin miedo | — | B: aviso, firma, vuelta atrás automática |
