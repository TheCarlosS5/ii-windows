# 04 · Bloque C — Configuración: más rápida, más corta y fácil de encontrar

> **En simple:** hoy la página "Escritorio" tiene **todos** los widgets uno debajo de otro (23 secciones, 72 controles,
> 915 líneas) y se crean todos a la vez al entrar. Cada widget nuevo la hace más larga y más lenta. La solución: una
> **galería de widgets** (tarjetas con un interruptor y "Personalizar"), donde las opciones de cada widget se abren en su
> propia página **solo cuando la pides**. Además: un **buscador** de ajustes, páginas reorganizadas por tema, sliders que
> no traban la shell, y una sola ventana de Configuración (hoy se puede abrir dos veces).

Va en la **0.8.0** (lo urgente de C5/C6, en la 0.7.0).

---

## C0 · Diagnóstico (0.6.0 tal como se publicó)

| Página (archivo en `modules/settings/`) | Líneas | Secciones/subsecciones | Controles aprox. | Problema |
|---|---|---|---|---|
| Escritorio (`BackgroundConfig.qml`) | **915** | **13 / 10** | **72** | Mezcla reloj (≈520 líneas, 11 subsecciones), 12 widgets, iconos y "Desktop widgets". Crece con cada widget. |
| Paneles (`InterfaceConfig.qml`) | 632 | 7 / 7 | 53 | Cajón de sastre: chuleta, bloqueo, seguridad, estilos, notificaciones, barras laterales, OSD, vista general. |
| Apariencia (`AppearanceConfig.qml`) | 398 | 6 / 9 | 32 | 6 subsecciones solo de fuentes; rendimiento escondido aquí. |
| Barra (`BarConfig.qml`) | 384 | 7 / 5 | 29 | Notificaciones de la barra separadas de las de Paneles. |
| Inicio (`QuickConfig.qml`) | 371 | 2 / 3 | 7 | Bien. |
| General (`GeneralConfig.qml`) | 361 | 6 / 3 | 26 | Audio, batería, idioma, Gemini, políticas, sonidos y hora juntos. |
| Servicios (`ServicesConfig.qml`) | 251 | 7 / 2 | 22 | IA, red, recursos, rutas, búsqueda, prefijos, clima. |
| Acerca de, Avanzado, Dock | 293 / 123 / 122 | — | — | Bien; Avanzado crecerá. |

Cómo funciona hoy (`settings.qml`):
- Ventana aparte: cada entrada (Win+I, menú del escritorio, menú del dock, panel derecho) hace
  `Quickshell.execDetached(["qs", "-p", …settings.qml])` → **un proceso nuevo cada vez**; dos pulsaciones = dos ventanas.
- Un `Loader` por página (bien: solo existe la página abierta), pero **dentro** de la página todo se crea de golpe:
  `ContentPage` = `StyledFlickable` + `ColumnLayout` sin virtualizar.
- `Config.readWriteDelay = 0` en la ventana de ajustes: **cada paso de un slider escribe `config.json`**, y la shell
  (que vigila el archivo con `FileView { watchChanges: true }`, recarga a los 50 ms) relee y reevalúa todos sus *bindings*
  en cada paso → tirones en la shell y en la ventana mientras se arrastra.
- No hay buscador.

**Medición que se añade antes de tocar nada:** `II_SETTINGS_BENCH=1` registra por página el tiempo desde `source` del
`Loader` hasta `onLoaded` y hasta el primer cuadro (`frameSwapped`). Objetivo final: **< 150 ms** por página en la laptop
AMD a 150 % y **< 300 ms** en el "PC lento" emulado (`coldstart.ps1 -Slow`).

---

<a id="c1"></a>
## C1 · Nueva organización (mapa de páginas)

```
Configuración
├─ Inicio ............ resumen: fondo y colores, posición de la barra, modo (claro/oscuro), accesos frecuentes, buscador
├─ Personalizar
│   ├─ Fondo y colores        (selector, Material You, fondo aleatorio/diario, fondos animados)
│   ├─ Tema y fuentes         (esquema, fuentes → subpágina, esquinas, transparencia de ii)
│   └─ Animaciones            (velocidad, curvas, minimizar al dock, animaciones de ventanas)
├─ Barra ............. pestañas: Diseño · Contenido · Bandeja · Avisos
├─ Dock
├─ Escritorio
│   ├─ Widgets  ★ galería (C2)
│   ├─ Iconos del escritorio
│   └─ Modo edición y cuadrícula
├─ Paneles
│   ├─ Barras laterales y ajustes rápidos
│   ├─ Vista general y lanzador (incluye prefijos de búsqueda)
│   ├─ Notificaciones y No molestar (une las de Barra y Paneles)
│   ├─ Avisos en pantalla (OSD, píldora de Bloq Mayús/cargador)
│   └─ Bloqueo
├─ Atajos  (nuevo: lista de shared/actions.json, conflictos, editar shortcuts.ini; ver E16)
├─ Sistema: Audio · Batería y energía · Idioma y hora · Sonidos de la interfaz
├─ Servicios: Clima · IA · Búsqueda web · Carpetas
├─ Rendimiento (nuevo: Ligero/Normal/Completo, dibujo, transparencia de otras ventanas, juegos)
├─ Actualizaciones (nuevo, ver B3)
├─ Avanzado: Integración con Windows · Copia y restauración · Diagnóstico (logs, crashes, modo seguro, restablecer)
└─ Acerca de
```

Reglas: una página no muestra más de ~25 controles; lo raro va en un desplegable "Opciones avanzadas"; los nombres en
español de usuario ("Ocultar la barra sola"), no de programador.

---

<a id="c2"></a>
## C2 · Galería de widgets (lo que pidió Carlos)

```
Escritorio › Widgets
┌─────────────────────────────────────────────────────────────────────────────┐
│ Mostrar widgets  [■■■□]      [ Editar escritorio ]   [ + Añadir widget ]   │
│ 🔍 Buscar widget…    (Todos) (Tiempo) (Productividad) (Multimedia) (Sistema)│
├─────────────────────────────────────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐                         │
│ │  🕒      │ │  🎵      │ │  ☀       │ │  🗓       │                         │
│ │ Reloj    │ │ Música   │ │ Clima    │ │ Calendario│                        │
│ │ [■■ on ] │ │ [■■ on ] │ │ [□□ off] │ │ [■■ on ]  │                         │
│ │Personalizar›│Personalizar›│Personalizar›│Personalizar›                       │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘  … (GridView virtualizado) │
└─────────────────────────────────────────────────────────────────────────────┘
```

### C2.1 Un registro de widgets (fuente única)
`services/WidgetRegistry.qml` (Singleton, *overlay*) con una entrada por widget:

```js
{
  id: "clock",
  name: Translation.tr("Clock"), description: Translation.tr("Time and date, digital or analog"),
  icon: "schedule", category: "time",
  enabledKey: "background.widgets.clock.enable",       // ejemplo: usar la clave que ese widget ya tiene en Config.qml
  settingsPage: "modules/settings/widgets/ClockSettings.qml",
  quickOptions: [                                       // para el engranaje en modo edición (C7)
    { key: "background.widgets.clock.style", type: "choice", label: Translation.tr("Style") },
    { key: "background.widgets.clock.showSeconds", type: "switch", label: Translation.tr("Seconds") }
  ],
  multiInstance: false,
  heavy: false                                           // true = el widget anima o consulta seguido (aviso en Rendimiento)
}
```

- El escritorio (`modules/ii/background/…`, que hoy enumera los widgets a mano) lee **el mismo registro**: añadir un
  widget = 1 entrada + su QML + su página de ajustes. Nada más crece.
- Las claves de `config.json` **no cambian** (sin migración): solo se mueve la interfaz.
- `multiInstance` prepara el futuro (dos fotos, varias notas): instancias en un arreglo `background.widgets.<id>.instances`.

### C2.2 La página de la galería
`modules/settings/widgets/WidgetsPage.qml`:
- `GridView` (virtualizado: solo crea las tarjetas visibles + `cacheBuffer` de una fila) con `model: WidgetRegistry.list`
  filtrado por categoría y texto.
- `WidgetCard.qml`: icono (o miniatura estática `assets/images/widgets/<id>.webp`), nombre, interruptor que escribe
  `enabledKey`, y "Personalizar ›".
- "Añadir widget" = los apagados primero, con su descripción; activar lo coloca en un hueco libre de la cuadrícula del
  escritorio (lógica del modo edición).

### C2.3 Página de cada widget (se crea solo al abrirla)
- `StackView` dentro de la página Escritorio: "Personalizar" hace `push` de un `Loader { asynchronous: true; source:
  entry.settingsPage }` con un esqueleto gris mientras carga; Atrás, Esc y el botón "atrás" del ratón hacen `pop`.
- Migas: `Escritorio › Widgets › Reloj`.
- Arriba, **vista previa en vivo** del widget (la misma pieza QML a escala, si es ligera; si no, la miniatura).
- Sección común al final de cada página (componente `WidgetCommonSettings.qml`): Tamaño (restablecer), Opacidad, "Mostrar
  en: todas las pantallas / la principal", "Pausar cuando una ventana tapa el escritorio" (rendimiento, ver
  [D2](05-rendimiento.md#d2)), Restablecer este widget.

### C2.4 Reloj: de 520 líneas a una página con pestañas
`ClockSettings.qml` con `PrimaryTabBar` y un `Loader` por pestaña (solo existe la abierta):
**Estilo** (digital/cookie/…, estilo en bloqueo) · **Esfera** · **Manecillas** (hora, minuto, segundo) · **Fecha** ·
**Frase**. Vista previa fija arriba, que cambia al momento.

---

<a id="c3"></a>
## C3 · Buscador de ajustes

- **Índice generado al preparar el QML:** `tools/port/gen-settings-index.py` (corre en `stage-ii.ps1` después de los
  parches) recorre `modules/settings/**/*.qml`, toma `title:` de `ContentSection`/`ContentSubsection` y `text:` de cada
  `ConfigSwitch`/`ConfigSpinBox`/`ConfigSelectionArray`/`ConfigSlider`…, la clave de `Config.options.*` que usa, y la
  traducción de `translations/es_MX.json`. Escribe `settings-index.json`:
  `[{ "page": "widgets/clock", "section": "dial", "label": "Estilo de la esfera", "key": "background.widgets.clock.dial", "keywords": ["reloj","esfera","dial"] }]`.
- Sinónimos a mano en `tools/port/settings-synonyms.json` ("oscuro" → modo oscuro, "fondo" → wallpaper, "transparente",
  "barra de tareas" → barra, "inicio" → lanzador…).
- **Interfaz:** campo arriba del riel de navegación (Ctrl+F o empezar a escribir). Mientras escribes, la página se
  reemplaza por resultados (búsqueda difusa, sin tildes ni mayúsculas). Enter/clic → abre la página, baja a la sección
  (`objectName` = id de sección) y la resalta 2 s.
- **El mismo índice en el lanzador:** escribir "barra abajo" en la búsqueda de ii ofrece "Configuración › Barra ›
  Posición". Ver [E1](06-plus.md#e1).

---

<a id="c4"></a>
## C4 · Rendimiento de todas las páginas

1. **`LazySection`** (`modules/common/widgets/LazySection.qml`, nuevo): un `ContentSection` cuyo contenido está en un
   `Loader` que se activa cuando la sección entra a 1,5 pantallas de lo visible (`contentY`), y queda creada una vez
   vista. Mientras no, ocupa una altura estimada (para que la barra de desplazamiento no salte). Se usa en las páginas
   largas que queden (Paneles, Barra, Sistema).
2. **Sliders y números que no traban la shell:** `ConfigSlider` escribe en `config.json` al **soltar** (`onPressedChanged`
   con `!pressed`) o con 200 ms sin moverse; `ConfigSpinBox` con 300 ms. Mientras se arrastra, la vista previa local
   cambia al instante. Quitar `Config.readWriteDelay = 0` o dejarlo solo para interruptores.
3. **Sin efectos caros en ajustes:** nada de `OpacityMask`/`MultiEffect`/sombras en listas (en `About.qml` la foto se
   recorta con `OpacityMask`; aceptable porque es una sola).
4. **Páginas visitadas, vivas:** guardar las 3 últimas páginas abiertas (`Loader` por página con `active` tras la primera
   visita) para que volver sea instantáneo. La ventana es un proceso aparte, el costo de memoria es acotado (medirlo).
5. Medir con `qmlprofiler` (`quickshell --debug PORT`) antes/después; guardar las cifras en `docs/RONDA-…`.

---

<a id="c5"></a>
## C5 · Una sola ventana de Configuración, abierta donde hace falta

- **Fork:** nuevo tipo QML `Quickshell.Windows.SingleInstance { name: "ii-settings"; onActivated: (args) => … }`
  (C++: `CreateMutexW(Local\ii-windows-settings)`; si ya existe, el segundo proceso manda sus argumentos por
  `WM_COPYDATA` a una ventana oculta del primero y sale). El primero trae su ventana al frente
  (`WindowTracker::forceForeground`) y navega.
- **Abrir en una página concreta:** `II_SETTINGS_PAGE=widgets/clock` (el mismo patrón que `II_STORE_PAGE` en `store.qml`).
  Un solo ayudante en la shell, `GlobalStates.openSettings(page)`, usado por Win+I, el menú del escritorio, el del dock,
  el panel derecho y el engranaje de cada widget.
- Opcional (casilla en Rendimiento, apagada por defecto): **"Abrir Configuración más rápido"** = precargar la ventana
  oculta 60 s después del arranque (cuesta ~80–120 MB; medirlo).

---

<a id="c6"></a>
## C6 · Ajustar cada widget desde el propio escritorio

En modo edición, cada widget muestra un engranaje ⚙. Al pulsarlo, un *popover* con las 3–5 `quickOptions` del registro
(estilo, tamaño, color, segundos…) y "Más opciones…" (abre C2.3 con `openSettings`). Lo más usado ya no necesita abrir
Configuración.

---

<a id="c7"></a>
## C7 · Qué se mueve, se junta o se esconde (por página)

| Hoy (página › sección) | Pasa a | Nota |
|---|---|---|
| Escritorio › Widget: Reloj (11 subsecciones) | Escritorio › Widgets › Reloj (pestañas) | C2.4 |
| Escritorio › Widget: Música/Foto/Recientes/Calendario/Tareas/Temporizador/Recursos/Nota/Reloj japonés/Clima | Escritorio › Widgets › (cada uno) | Galería |
| Escritorio › Desktop widgets | Escritorio › Modo edición y cuadrícula | |
| Escritorio › Desktop icons | Escritorio › Iconos del escritorio | |
| Apariencia › Fonts (6 subsecciones) | Personalizar › Tema y fuentes › Fuentes (subpágina) | Solo "Fuente principal" visible; el resto en avanzado. |
| Apariencia › Performance, Drawing, Windows of other programs | Rendimiento | Con el selector Ligero/Normal/Completo arriba. |
| Apariencia › Transparency and motion | Personalizar › Tema (transparencia) y › Animaciones | |
| Apariencia › Wallpaper selector, Color generation, Parallax | Personalizar › Fondo y colores | |
| Barra › Notifications + Paneles › Notifications | Paneles › Notificaciones y No molestar | Una sola página para avisos. |
| Barra (12 subsecciones) | Barra con pestañas Diseño · Contenido · Bandeja · Avisos | |
| Paneles › Cheat sheet, Super key symbol | Atajos | |
| Paneles › Lock screen, Security | Paneles › Bloqueo | |
| Paneles › Window animations | Personalizar › Animaciones | |
| Paneles › Overview | Paneles › Vista general y lanzador | Con Servicios › Search/Prefixes (avanzado). |
| General › Audio, Battery, Sounds, Time, Language | Sistema (subpáginas) | |
| General › Generate translation with Gemini | Sistema › Idioma › avanzado | |
| General › Policies | Servicios › IA (si son de IA) o Avanzado | Revisar qué hace cada una en Windows. |
| Servicios › AI, Weather, Web search, Save paths | Servicios (subpáginas) | |
| Servicios › Networking, Resources | Rendimiento o Barra › Contenido | Según qué controlen. |
| Avanzado › If something goes wrong | Avanzado › Diagnóstico | + crashes, modo seguro, abrir logs, restablecer todo. |
| — | Actualizaciones (nueva) | B3 |
| — | Atajos (nueva) | E16 |

Además: quitar lo que no hace nada en Windows y quedó (revisar con `settings-pages.ps1` y un recorrido manual); cada
texto que siga en inglés, traducirlo (ver [H1](08-calidad-y-publicacion.md#h1)).

---

## C8 · Aceptación del bloque

- Cada página abre en < 150 ms (laptop AMD, 150 %); la galería tarda lo mismo con 12 o con 40 widgets.
- El buscador encuentra por su nombre en español al menos el 95 % de los ajustes (lista de prueba de 60 términos).
- Arrastrar cualquier slider no produce recargas de `config.json` en la shell hasta soltar (comprobar con el log de la shell).
- Win+I dos veces = una sola ventana, al frente.
- `settings-pages.ps1` recorre todas las páginas y subpáginas nuevas sin avisos QML.
- El recorrido de bienvenida (`modules/ii/tour`) y `docs/CONFIGURACION.md` explican la nueva organización.
