# Plan ii-windows · 31 de octubre de 2026

De la **0.6.0** a la **1.0**: el fallo que cierra y reabre ii al navegar, las actualizaciones automáticas, la nueva
Configuración y lo que hace falta para que la gente lo use todos los días.

> **Solo plan: no se implementó nada.** En esta ronda solo se sincronizaron los repositorios (avance rápido, sin cambios
> locales) y se escribió esta carpeta. No hay commits ni nada subido.

---

## Estado sincronizado

| Repositorio | Antes (local) | Ahora | Qué trajo |
|---|---|---|---|
| `ii-windows` (`main`) | `3eed626` · 0.5.0 | **`6d92550` · v0.6.0** | 41 commits del plan del 24/10: latido de la shell, Alt+Tab propio, barra "Junto al dock", minimizar al dock, GPU por pantalla principal, render loop *threaded*, QML precompilado por el host, firma/release-check preparados. |
| `quickshell-windows` (`windows`) | `332e062` | **`5e8ebeb` · `ii-windows-v0.6.0`** | 10 commits: latido desde el hilo GUI, *threaded* con GPU real, `WS_EX_NOACTIVATE`, `SystemProbe`, ScreencopyView, recursos de versión. |

- Rama remota nueva `fix/plan-2026-10-24` (= `main`). Release **v0.6.0** publicada el 26/10 (zip + Setup).
- GitHub: 0 issues abiertos o cerrados (los reportes de testers no están ahí).
- **Esta PC:** la 0.6.0 se instaló el 25/10, crasheó 3 veces esa noche navegando en Brave, del 26 al 29/10 se apagó con
  el atajo de pánico en casi cada arranque y el 29/10 se rescató y desinstaló.

---

## Resumen en un minuto

1. **"ii se cierra y se abre solo" es un crash real, no el latido.** `quickshell.exe` muere con `0xC0000005` en
   `quickshell/src/win32/services/mpris.cpp:184-185`: cuando el navegador cierra una sesión de video (X, YouTube,
   Shorts), `GetPlaybackInfo()` devuelve nulo y se usa sin comprobar; `catch (...)` no atrapa eso. Probado con el Visor
   de eventos, el binario exacto de la release y su desensamblado. **Existe desde la 0.1.3.** → [01](01-fallo-principal.md)
2. **El arreglo** (A1) es pequeño, pero va con: manejador de crashes con firma y minidump, PDB publicados, modo seguro
   por parte que falla, aviso "ii se recuperó", portada que se puede saltar y vuelta atrás si una versión nueva falla.
   → [02](02-estabilidad.md) · sale como **0.6.1**.
3. **Actualizaciones:** ii avisa con notificación + puntito + página propia; baja con reanudación, verifica una firma
   propia (gratis, sin certificado) y los hashes, instala al lado de la actual (eso ya existe) y vuelve sola atrás.
   → [03](03-actualizaciones.md) · **0.7.0**.
4. **Configuración:** galería de widgets con páginas que se crean al abrirlas, buscador de ajustes, páginas
   reorganizadas, sliders que no traban la shell y una sola ventana. → [04](04-configuracion.md) · **0.8.0**.
5. **Rendimiento:** el rastreador de ventanas deja de recorrer todo en cada cambio de título; todo widget se pausa
   tapado; cachés con tope; arranque más corto. → [05](05-rendimiento.md)
6. **El Plus:** Buscar todo, Modos automáticos (Clase/Trabajo/Juego/Presentación), panel Hoy con horario de clases,
   galería de temas y widgets, indicadores de micrófono/cámara (que hoy se pierden al ocultar la barra de Windows), dock
   que avisa. → [06](06-plus.md), [07](07-integraciones-windows.md) · **0.9.0–1.0**.

---

## Archivos del plan

| # | Archivo | Contenido |
|---|---|---|
| 01 | [01-fallo-principal.md](01-fallo-principal.md) | Diagnóstico completo del cierre/reapertura: cronología, prueba, causa raíz, cómo reproducirlo |
| 02 | [02-estabilidad.md](02-estabilidad.md) | Bloque A: arreglo de mpris, QML, crashes, modo seguro, host, auditoría, pruebas, confianza |
| 03 | [03-actualizaciones.md](03-actualizaciones.md) | Bloque B: actualizador completo (publicar, buscar, avisar, bajar, verificar, instalar, volver) |
| 04 | [04-configuracion.md](04-configuracion.md) | Bloque C: nueva Configuración, galería de widgets, buscador, rendimiento de páginas |
| 05 | [05-rendimiento.md](05-rendimiento.md) | Bloque D: rastreador de ventanas, pausa de widgets, carátulas, cachés, arranque, avisos QML |
| 06 | [06-plus.md](06-plus.md) | Bloque E: las 16 funciones del "Plus" con diseño, APIs y MVP |
| 07 | [07-integraciones-windows.md](07-integraciones-windows.md) | Bloque F: catálogo de 24 integraciones con Windows (API, riesgo, versión) |
| 08 | [08-calidad-y-publicacion.md](08-calidad-y-publicacion.md) | Bloques G y H: CI, reportes, beta, firma, winget, web, accesibilidad, pulido, decisiones del autor |
| 09 | [09-hoja-de-ruta.md](09-hoja-de-ruta.md) | Versiones 0.6.1 → 1.0, alcance, criterios de salida, dependencias, riesgos |
| — | [anexos/evidencia-crash.md](anexos/evidencia-crash.md) | Eventos, desensamblado, llamadas a Qt, crashes viejos, logs |
| — | [anexos/crash-locate.py](anexos/crash-locate.py) | Herramienta usada para ubicar un crash en un exe sin PDB |

---

## Prioridades

| Prioridad | IDs | Versión |
|---|---|---|
| **P0 — ya** | A1 mpris · A2 QML multimedia · A3 crashes y símbolos · A4 (mínimo) · A8 pruebas de estrés · D3 carátulas | 0.6.1 |
| **P1 — siguiente** | A4 completo · A5 host sin esperas · A6 auditoría nativa · A7 verificada de verdad · A9 confianza · B1–B12 actualizador · C5 una ventana · D4 cachés · D7 avisos QML · F1 indicadores de privacidad · G1–G3 · H1 español | 0.7.0 |
| **P1 — después** | C1–C8 Configuración nueva · D1 rastreador · D2 pausa tapado · D5 arranque · D8 memoria · E16 atajos · F23 multi-monitor · G2/G6 CI y winget | 0.8.0 |
| **P2 — el Plus** | E1 Buscar todo · E2 Modos · E3 Hoy · E5–E13 · F2–F4, F6–F10, F14, F16–F21, F24 · H2–H5 | 0.9.0 |
| **P2/P3 — 1.0 y más** | E1/E2/E3 completos · E4 galería · B9 deltas · G5 firma · G6 web · E14 IA · E15 teléfono · F5, F11–F13, F22 | 1.0 |

---

## Cómo usar este plan con agentes

- Cada archivo es un bloque que se puede dar entero a un agente. El orden de la [hoja de ruta](09-hoja-de-ruta.md) evita
  que dos agentes toquen los mismos archivos: A (fork `src/win32/services`, host `main.cpp`) antes que B (host
  `updater.*`, QML `services/Updates.qml`), y C (QML de `modules/settings`) en paralelo con D1 (fork `toplevels.cpp`).
- Para cada ID, el agente entrega: el cambio, la prueba (automática o los pasos manuales escritos), la nota en
  `docs/RONDA-AAAA-MM-DD.md` y, si cambia el diseño, una entrada en `docs/DECISIONS.md` (este plan abre **D25**).
- Revisar todo lo que hagan (el historial del proyecto tiene severidades infladas y reescrituras masivas de agentes).

## Reglas para quien implemente (las de siempre, resumidas)

1. **Seguridad primero:** todo por usuario y reversible; nada en `HKLM`, nada de `Winlogon\Shell`, nada inyectado en
   Explorer; punto de restauración y copias `.reg` antes de cambios externos; el atajo de pánico, el guardián y el rescate
   siempre deben funcionar. Pruebas riesgosas en Windows Sandbox (`tools/sandbox`), nunca sonido audible en el Sandbox.
2. **El juego manda:** con un juego al frente, ii se aparta (atajos, gancho con anticheat, actualizaciones, descargas).
3. **Finales de línea:** los archivos CRLF siguen CRLF (`tools/dev/check-eol.py`); parches con `tools/port/edit.py` o
   escritos con el editor, no con `sed`/heredocs (comen `\n`, `\t`, `\b`).
4. **QML de upstream:** no se edita a mano; parches pequeños en `tools/port/*.py` o archivos propios en `overlay/ii/`
   (D11). Después de cambiar QML, leer siempre `%TEMP%\quickshell\by-pid\<pid>\log.log`.
5. **Después de compilar el host:** `deploy.ps1` antes de `make-package.ps1` (lección de la ronda del 18/10).
6. **Commits** a nombre de `Calos <carlosstivengutierrezramirez@gmail.com>` y **sin** líneas de coautor de IA ni
   "Generated with…". Preguntar antes de hacer *push* o publicar una release.
7. **Español** en todo lo que ve el usuario, con palabras simples.

## Lo que este plan **no** comprobó (para no dar nada por hecho)

- El arreglo A1 no se programó ni se probó: la causa está demostrada con evidencia, el arreglo es el diseño.
- APIs marcadas "comprobar" en E5, E7, F4, F5, F11, F12 (comportamiento real en Windows 11 25H2) y la identidad estable de
  las sesiones de `GetSessions()` (A1.1 punto 4).
- La parte de juegos y NVIDIA de la 0.6.0 sigue sin probar en hardware real (lista de `docs/PUBLICAR.md` §5).
- No se revisaron uno por uno todos los QML de upstream ni los ~240 KB de `TASKS_ii_windows.md`; el plan se apoya en el
  código del fork y del host, el QML publicado en la 0.6.0, los logs reales de esta PC y los documentos de `docs/`.
