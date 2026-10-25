# Estado del plan del 24 de octubre de 2026

Punto por punto, qué se hizo de `PLAN-ii-windows.md` y qué falta. Las decisiones y sus porqués están en `docs/DECISIONS.md` (D23 y D24). Rama: `fix/plan-2026-10-24`, en ii-windows y en el fork quickshell-windows. Para fusionar, primero el fork.

Leyenda: ✅ hecho y probado aquí · 🟡 hecho, falta probarlo en hardware real · ⏳ falta, con el motivo.

## Bloque 0

| Punto | Estado | Notas |
|---|---|---|
| 0.1 Latido y restauración inmediata | 🟡 | Probado con el congelamiento simulado (`test-host-heartbeat`) y con la shell real congelada a propósito. Falta un juego pesado de verdad. |
| 0.2 Luz nocturna apagada por defecto | ✅ | Con la migración de instalaciones anteriores. |
| 0.3 Fondo café y sincronización | ✅ | Fondo propio, el café reconocido por SHA-256. |
| 0.4 Tecla Windows y lanzador precargado | ✅ | Lanzador creado una vez, ventana calentada al arrancar, gancho en su propio hilo. |
| 0.5 Tecla Windows con juegos | 🟡 | Probado con juegos simulados (`test-host-games`). Falta probar osu! y Valorant de verdad. |
| 0.6 Lag con NVIDIA | 🟡 | GPU decidida en cada arranque, metadatos en los ejecutables, README. Falta la laptop con la 5070 Ti. |
| 0.7 Wallpaper Engine | 🟡 | `WS_EX_NOACTIVATE` en los paneles. Falta probarlo con Wallpaper Engine y la pausa activada. |

## Bloque 1

| Punto | Estado | Notas |
|---|---|---|
| 1.1 Render loop *threaded* | ✅ | Con GPU real, *threaded*; con el adaptador por software, *basic* (ahí se vio el fallo de D9). Opción en Configuración > Apariencia > Dibujo. |
| 1.2 Clic a través sin sondeo de 16 ms | ✅ | Ya iba por eventos del cursor. |
| 1.2 Notificaciones por evento | ⏳ | El evento exige identidad de paquete (MSIX), y eso exige firmar (1.4). Mientras tanto se consulta cada 1 s (5 s en reposo). |
| 1.2 Menos procesos de `ii-shim` | ✅ | Fondo animado y brillo: ya no lanzan un proceso cada pocos segundos. |
| 1.3 Caché QML siempre compilada | ✅ | El host la compila antes de lanzar la shell si falta (`test-host-precompile`). |
| 1.3 Texturas del desenfoque | ✅ | Ya era una sola imagen de 480 px compartida. |
| 1.3 README sobre la memoria | ✅ | Ya estaba. |
| 1.4 Firma | ⏳ | El script está listo (`tools/package/sign.ps1`). Falta el certificado: SignPath Foundation (gratis para código abierto), Azure Trusted Signing o una CA. |
| 1.4 Defender, VirusTotal, empaquetadores, metadatos | ✅ / ⏳ | `release-check.ps1` lo comprueba en cada paquete. Enviar cada versión a Microsoft es a mano (`docs/PUBLICAR.md`). |
| 1.5 Avisos de cargador y Bloq Mayús | ✅ | Píldora de ii. El del cargador lee los datos 1 s después. |

## Bloque 2

| Punto | Estado | Notas |
|---|---|---|
| 2.1 Barra junto al dock | 🟡 | Pastillas que nunca tocan el dock. Falta probarla en una pantalla pequeña con la barra de Windows oculta. |
| 2.2 Minimizar hacia el dock | ✅ | Sin animación al restaurar (se veía doble). |
| 2.3 Ocultar lo visual de Windows | ✅ | Alt+Tab propio, dock con el lanzador, teclas multimedia opcionales. Lo que queda de Windows y por qué: `docs/LO-QUE-QUEDA-DE-WINDOWS.md`. |

## Bloque 3

| Punto | Estado | Notas |
|---|---|---|
| Estilo sobrio en la bienvenida | ✅ | Paso del recorrido, reversible. |
| Para quién es ii-windows | ⏳ | Es una decisión del autor, no código. |
| Pedir reportes a quien lo desinstaló | ⏳ | Es una tarea del autor, no código. |

## Pruebas en máquinas reales, antes de publicar

osu! y Valorant, la laptop con NVIDIA, Wallpaper Engine con la pausa, un juego pesado que congele la shell, "Junto al dock" en una pantalla pequeña, y Alt+Tab sobre apps y sobre un juego. Lista completa en `docs/PUBLICAR.md`.
