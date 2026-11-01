# 08 · Bloques G y H — Calidad, pruebas, publicación, accesibilidad y pulido

> **En simple:** que cada versión salga probada, firmada y fácil de instalar (también con `winget`), que cualquiera pueda
> reportar un fallo con un clic, y que ii se pueda usar en español completo, con teclado y con accesibilidad.

---

## G · Calidad y publicación

<a id="g1"></a>
### G1 · Ramas y versiones
- Ramas por bloque: `fix/0.6.1-mpris` (hotfix), `feat/updater`, `feat/settings-gallery`, `feat/modes`… En los **dos**
  repos con el mismo nombre; se fusiona **primero el fork** (como dice `docs/PLAN-2026-10-24-ESTADO.md`).
- Versionado semver: parche (0.6.1) = solo arreglos; menor (0.7.0) = funciones. `make-package.ps1` toma la base de un
  único lugar (hoy `$baseVersion` en el script) y `release.json` la repite.
- Notas de cada versión en `docs/RELEASE-x.y.z.md` (español primero), que también van dentro de `release.json` (B1).
- Cada ronda deja su `docs/RONDA-AAAA-MM-DD.md` y sus decisiones en `docs/DECISIONS.md` (este plan abre **D25**).

<a id="g2"></a>
### G2 · Integración continua (GitHub Actions) — P1, 0.7.0–0.8.0, esfuerzo M–L
`.github/workflows/build.yml` en `windows-2022`:
1. Caché de Qt 6.12 MSVC (`tools/dev/fetch_qt.py`, ~1,5 GB; el límite de caché de Actions es 10 GB).
2. Compilar el fork (`quickshell/`, clang-cl) y el host (`host/`), en *release* con PDB (A3).
3. Pruebas unitarias del host que ya existen: `keyboard_test`, `config_test`, `vdesk_test`, `nightlight_test`,
   `lockstate_test` (+ `updater_test` de B).
4. `stage-ii.ps1 -Dest` contra el `upstream` fijado (commit del README): los parches de `tools/port/*.py` aplican limpio.
5. `qmllint` sobre `overlay/ii` y los QML nuevos; `check-qml-imports.py`, `check-eol.py`, `check-ps-syntax.ps1`.
6. `gen-settings-index.py` (C3) y `check-winrt-null.py` (A6) como avisos.
7. En etiquetas `v*`: `make-package.ps1` + `release-check.ps1 -Strict` (sin firma de código hasta G5; `release.json`
   se firma **fuera** de CI, en la PC del autor, porque la clave privada nunca sube).
- Las pruebas de Sandbox y de PC real siguen locales (`run-local-suite.ps1`).

<a id="g3"></a>
### G3 · Reportes de fallos sin telemetría — P1, 0.6.1–0.7.0
- "Reportar un problema de ii" (ya existe, `tools/rescue/ii-report.ps1`) añade: JSON de crashes (A3), modo seguro activo,
  `release.json` de la versión, apps detectadas de E9, últimas 300 líneas del `host.log` y del log de la shell (ya limpia
  usuario y nombre del PC). El `.dmp` solo con casilla marcada.
- Desde el aviso "ii se recuperó" ([A4](02-estabilidad.md#a4)) un botón **Reportar** abre el formulario de GitHub con la
  firma del crash ya puesta (`?title=Crash en mpris (quickshell.exe+0x19ed74)&labels=crash`).
- `docs/FIRMAS-CONOCIDAS.md`: firma → issue → versión que lo arregló. El host puede decir "Este error ya está arreglado
  en la 0.7.0: actualiza" cuando la firma esté en una lista que trae `release.json` (`fixes: ["quickshell.exe+…"]`).
- Para testers sin cuenta de GitHub: un formulario simple (Google Forms) enlazado al lado del de GitHub.

<a id="g4"></a>
### G4 · Canal beta y grupo de testers
- Canal Beta del actualizador (B8). Antes de cada estable, 3–7 días en beta con los testers (los 3 de la ronda del 15/10).
- Criterio para pasar a estable: 0 crashes nuevos en beta, `test-install` y `run-local-suite` en verde, lista de
  máquinas reales (G7) revisada.

<a id="g5"></a>
### G5 · Firma de código (pendiente desde el plan 1.4)
- Solicitar **SignPath Foundation** (gratis para código abierto; repositorio público ya cumple). Mientras tanto,
  `release.json` firmado (B1) protege las actualizaciones automáticas aunque Windows siga avisando con el Setup.
- Seguir enviando cada versión al portal de Microsoft (falsos positivos de Defender), como dice `docs/PUBLICAR.md`.

<a id="g6"></a>
### G6 · Que la gente lo encuentre e instale fácil — P1, 0.8.0–1.0
- **winget:** manifiesto `TheCarlosS5.ii-windows` (instalador Inno, `Scope: user`, `InstallerSwitches: /VERYSILENT
  /SUPPRESSMSGBOXES`) con PR a `microsoft/winget-pkgs` en cada estable → `winget install ii-windows`. Con firma (G5) se
  aprueba más fácil.
- **Página web** (GitHub Pages, `thecarloss5.github.io/ii-windows`): video promo (ya existe), capturas, botón de
  descarga de la última versión (lee `releases/latest`), "¿Es seguro?" (SmartScreen, antivirus, cómo se desinstala),
  preguntas frecuentes, novedades. En español con resumen en inglés.
- **README:** primera pantalla con GIF corto, 3 frases y el botón de descarga; lo técnico más abajo.
- Comunidad: plantillas de issues (ya), etiqueta `good first issue`, `CONTRIBUTING.md` (cómo compilar, reglas de
  seguridad, EOL, parches de `tools/port`).

<a id="g7"></a>
### G7 · Pruebas en máquinas reales (lista fija antes de cada estable)
Lo de `docs/PUBLICAR.md` §5 (osu!, Valorant, laptop NVIDIA 5070 Ti, Wallpaper Engine con pausa, juego pesado que congela,
"Junto al dock" en pantalla pequeña, Alt+Tab propio) **más**:
- [ ] 2 h de feed de X / Shorts en Brave y Chrome (A1).
- [ ] 8 h de *soak* (A8/D8).
- [ ] Dos monitores con DPI distintos (100 % + 150 %), desconectar y conectar el segundo con ii corriendo (F23).
- [ ] Escalas 100/125/150/175 % (`redev.ps1 -Scale`) y la ventana de Configuración en cada una.
- [ ] PC lento real (4 hilos, HDD o eMMC) además del emulado.
- [ ] Inicio de sesión en frío 5 veces (tiempo de portada, D5).
- [ ] Actualización 0.6.1 → 0.7.0 por el actualizador, y vuelta atrás (B10).
- [ ] Desinstalar y comprobar que no quedan cachés (D4).

<a id="g8"></a>
### G8 · Documentación para usuarios
- `docs/GUIA.md` (nuevo): qué es cada parte, con capturas/GIF, en español simple; enlazada desde Acerca de y desde la web.
- `docs/CONFIGURACION.md` y `docs/ATAJOS.md` al día con C1/E16.
- `docs/LO-QUE-QUEDA-DE-WINDOWS.md` con F1 y cada integración nueva.

<a id="g9"></a>
### G9 · "Terminado" significa
1. Código + prueba automática (o el paso manual escrito en la ronda).
2. Sin avisos QML nuevos (D7), `check-eol.py` en verde (los archivos CRLF siguen CRLF).
3. `host.log` limpio en una sesión de 1 h (sin `slow:` > 250 ms, sin `exited with code`).
4. Texto en español revisado y documentación actualizada.
5. Probado a 100 % y 150 %.
6. Commits a nombre de `Calos <carlosstivengutierrezramirez@gmail.com>`, **sin** líneas de coautor de IA.

<a id="g10"></a>
### G10 · Privacidad (sección nueva del README)
ii no tiene telemetría. Lo que sale de la PC: la consulta de actualizaciones a GitHub (B11), el clima (si está activado),
el fondo del día (si se elige), la IA (solo si se configura) y los calendarios ICS que el usuario pegue. Todo lo demás
(tiempo de pantalla, portapapeles, notificaciones, crashes) queda en `%LOCALAPPDATA%`.

---

## H · Accesibilidad y pulido

<a id="h1"></a>
### H1 · Español completo — P1, 0.7.0–0.8.0
- `tools/dev/find-untranslated.py` (nuevo): recorre el QML preparado, saca cada `Translation.tr("…")` y lista las que no
  están en `translations/es_MX.json` (y los textos visibles sin `tr`). Meta: 0 textos en inglés en Configuración,
  paneles, tienda, bienvenida y avisos del host.
- Revisar los avisos del host (`MessageBox`, notificaciones de Windows de `showNotice`) y del instalador: hoy mezclan.
- Mantener el resumen en inglés del README y ofrecer inglés como idioma de la interfaz (ya existe la elección).

<a id="h2"></a>
### H2 · Todo se puede usar con teclado
Barra (Tab entre elementos, Enter abre), paneles laterales, vista general, Configuración (ya hay atajos Ctrl+Tab/RePág),
tienda y menús del dock. Foco visible (anillo con el color de acento). Esc siempre cierra lo de arriba.

<a id="h3"></a>
### H3 · Accesibilidad
- Nombres para el Narrador (`Accessible.name`/`Accessible.role`) en botones de barra, dock, ajustes rápidos y
  notificaciones.
- Alto contraste de Windows → paleta de alto contraste de ii (F19). Tamaño del texto de Windows → escala de fuentes (F20).
- "Reducir movimiento" (Windows: *Efectos de animación* apagado → `SPI_GETCLIENTAREAANIMATION`) → ii sin animaciones,
  igual que el modo ligero pero sin quitar transparencias.

<a id="h4"></a>
### H4 · Pulido visual
- Estados vacíos con ilustración y una acción (sin notificaciones, sin tareas, sin música, sin resultados).
- Esqueletos de carga en vez de saltos (Configuración, tienda, galería).
- Consistencia M3 Expressive: radios, tamaños de icono y espaciado iguales en barra, dock, paneles y ajustes (revisión
  con capturas a 100 % y 150 %).
- Microinteracciones con los sonidos suaves actuales: activar un modo, terminar una descarga de actualización.

<a id="h5"></a>
### H5 · Primer arranque, recorrido y "Novedades"
- El recorrido (`modules/ii/tour`) se actualiza con la nueva Configuración (C1), los Modos (E2) y "Buscar todo" (E1).
- "Novedades" después de cada actualización (B3.6).
- Primer arranque en un PC sin GPU dedicada y < 8 GB: ofrecer el modo ligero (ya existe para ≤ 4 hilos o < 7 GB).

<a id="h6"></a>
### H6 · Decisiones de producto pendientes (del autor, no código)
- **Nombre:** sigue pendiente desde la ronda del 15/10 (se habló de cambiarlo). Decidir antes de winget y de la web
  (G6), porque cambia el id del paquete.
- **Para quién es ii-windows** (bloque 3 del plan anterior): define qué va por defecto (estilo sobrio o el de ii).
- **Pedir reportes a quienes lo desinstalaron:** en esta PC, tras los cierres del 25/10 se usó el atajo de pánico en
  cada arranque y el 29/10 se desinstaló; otros usuarios pueden haber hecho lo mismo sin reportarlo. La 0.6.1 debería
  anunciarse diciendo claramente "arregla los cierres al navegar".
