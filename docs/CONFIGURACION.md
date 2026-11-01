# Configuración de ii: comprobar, recuperar, exportar e importar

El archivo es `%LOCALAPPDATA%\quickshell\illogical-impulse\config.json`. La herramienta es `ii-shim config …` (código en `host/src/configtool.cpp`; el esquema sale de `Config.qml` con `tools/dev/gen-config-schema.py` y está en `shared/config-schema.json`).

## Las páginas de Configuración (desde la 0.8.0)

La ventana se abre con Win+I (una sola: si ya está abierta, viene al frente). Arriba, **Buscar ajustes** (Ctrl+F) lleva a
cualquier ajuste por su nombre, en español o en inglés, y lo resalta.

| Página | Qué tiene |
|---|---|
| Inicio | Fondo y colores, posición y estilo de la barra, esquinas de la pantalla. |
| Apariencia | Transparencia, generación de color, selector de fondos, fuentes, paralaje, animaciones de ventanas, fondos animados. |
| Barra | Posicionamiento (también **Pantallas**: todas o solo la principal), bandeja, botones, clima, escritorios, avisos emergentes. |
| Dock | Todo el dock (también **Pantallas** y la tienda en el dock). |
| Escritorio | **Galería de widgets** (cada uno con "Personalizar"; el reloj con pestañas) e iconos del escritorio. En el modo edición del escritorio, el engranaje de cada widget abre sus ajustes aquí. |
| Paneles | Chuleta, bloqueo, **notificaciones** (también las de la barra), barras laterales, avisos en pantalla, vista general. |
| Sistema | Audio, batería, idioma, políticas, sonidos, hora y **Avisos de Windows** (reinicio pendiente, poco espacio). |
| Servicios | IA, redes, recursos, rutas, búsqueda, clima. |
| Rendimiento | Todos los efectos o ligero, reducir animaciones, dibujo, ventanas de otros programas. |
| Atajos | Los atajos de ii (cambiar o quitar), cuándo ceden ante juegos, teclas de volumen y multimedia. Escribe `shortcuts.ini`. |
| Avanzado | Integración con Windows, copia y restauración, diagnóstico (crashes, modo seguro). |
| Actualizaciones | Versión nueva, novedades, opciones del actualizador, volver a la anterior. |
| Acerca de | Versión, créditos. |

Abrir en una página concreta: `II_SETTINGS_PAGE=<archivo>` (por ejemplo `backgroundconfig/clock`, `updatesconfig`).

## Lo que pasa solo

- **Antes de arrancar la shell** (`ii-host`): si `config.json` no es JSON válido (truncado por un apagón o un disco lleno, mal editado), se aparta como `config.json.invalid-<fecha>` (se guardan las 10 últimas) y se pone la última copia buena (`config.last-good.json`). Sin copia buena, ii arranca con sus valores por defecto. Se avisa con una notificación cuando la shell está arriba y queda en `host.log`.
- Si el JSON es válido pero una opción tiene **el tipo equivocado** (un texto donde va un entero, una lista donde va un objeto), se guarda antes `config.before-repair-<fecha>.json` y solo esas opciones vuelven a su valor por defecto. Los valores fuera de rango o fuera de la lista documentada **no se tocan** (pueden ser deliberados): `ii-shim config check` los muestra como avisos.
- Un archivo con `configVersion` mayor que el de esta versión (de un ii más nuevo) **no se toca**.
- La primera vez que se ve un archivo sin `configVersion`, se guarda `config.pre-v1.json` tal como estaba.
- La **última copia buena** se guarda una vez cuando la shell ya arrancó y otra al cerrarse con normalidad, solo si el archivo es válido y sin opciones mal tipadas; nunca por cada cambio ni a partir de un archivo dañado.

## Comandos

```
ii-shim config where
ii-shim config check [--file F]         0 sin errores (los avisos no cuentan) · 1 errores · 2 no es JSON
ii-shim config guard                    lo que hace ii-host al arrancar
ii-shim config keep-good                lo que hace ii-host cuando la shell funciona
ii-shim config export <pack.json> [--force]
ii-shim config import <pack.json> [--apply] [--prefer pack|mine] [--map-monitor viejo=nuevo]
```

## Exportar / importar

El pack lleva solo opciones **conocidas** de ii (las del esquema), sin credenciales: se dejan fuera los miembros cuyo nombre acaba en `apiKey`, `token`, `secret`, `password`, `privateKey`, `authorization`, `userId`, y `cookie` cuando es un valor simple (el estilo de reloj `cookie` es un objeto y se conserva). Las claves de cuentas viven además en el almacén cifrado de Windows (R11), no en este archivo. Chats, notificaciones, portapapeles y temporales no son parte de `config.json` y no se exportan. Los atajos (`shortcuts.ini`) **no** van en el pack todavía.

`import` **solo previsualiza** salvo con `--apply`:

- `set` (se escribe), `same` (ya igual), `keep` (tu valor difiere y se queda; con `--prefer pack` gana el pack), `skip` (con el motivo).
- Se descarta: opción desconocida, tipo equivocado, fuera del rango que permiten los ajustes, nombre de credencial, valor demasiado grande (cadena > 64 KiB, lista > 1000), ruta que no existe en este PC, monitor que no está conectado (con `--map-monitor` se puede reasignar; en `bar.screenList` se quedan solo los monitores que existen aquí).
- Un pack mayor de 1 MiB, más profundo de 32 niveles, de un `configVersion` más nuevo, o que no sea un pack, se rechaza sin escribir nada.
- Nunca se ejecuta nada de un pack ni se escribe fuera de la carpeta de configuración; los nombres como `../../x` no son opciones y se descartan.
- `--apply` hace antes `config.before-import-<fecha>.json` y reemplaza `config.json` de una vez (archivo temporal + renombrado) **solo si el archivo sigue siendo el que se leyó**: si otro escritor (ii, un editor) lo cambió entremedias, no se reemplaza nada y se avisa. Cancelar = no pasar `--apply`.

## Límites conocidos

- Mientras ii está abierto, escribe `config.json` entero desde su estado en memoria cuando cambia una opción; importar con ii abierto funciona (ii recarga el archivo) pero si ii escribe justo después de un `--apply` puede volver a escribir su estado. Lo más limpio es importar con ii cerrado.
- No hay migración de valores todavía (la versión 1 es la primera); el mecanismo (`configVersion`, copia previa, rechazo de versiones nuevas) está, las migraciones concretas se añadirán con el primer cambio de formato.
- No hay botones de exportar/importar en los ajustes de ii: se usa la línea de comandos.
