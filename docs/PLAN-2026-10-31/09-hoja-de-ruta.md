# 09 · Hoja de ruta: de la 0.6.0 a la 1.0

> **En simple:** primero un arreglo rápido (0.6.1) para que ii deje de cerrarse; después las actualizaciones
> automáticas (0.7.0) para que los arreglos lleguen solos; luego la nueva Configuración y el rendimiento (0.8.0); y al
> final el "Plus" (0.9.0) y la publicación grande (1.0).

Las estimaciones son en **días de trabajo de un agente con revisión** (no calendario) y suponen el bucle de desarrollo
actual (`redev.ps1`, Sandbox, PC real).

---

## 0.6.1 · "Ya no se cierra al navegar" (hotfix) — 2–3 días

| ID | Qué | Archivo principal |
|---|---|---|
| A1 | Backend de multimedia seguro (nulos, un hilo, claves fijas, *revokers*, `wait_for`) | `quickshell/src/win32/services/mpris.cpp` |
| A2 | QML de multimedia sin avisos y sin `ii-shim fetch` por canción | `PlayerControl.qml`, `MediaWidget.qml` (*overlay*/parche) |
| A3 | Manejador de crashes (dump + JSON + subsistema) y PDB publicados | `quickshell/src/win32/crash.cpp`, CMake, `make-package.ps1` |
| A4 (mínimo) | Aviso "ii se recuperó" + `II_DISABLE` por firma repetida | `host/src/main.cpp`, servicios del fork |
| A5 (medir) | `SlowStep` por sub-paso en `refreshContext` | `host/src/keyboard.cpp` |
| A8 | `ii-mpris-stress`, `churn.html`, `test-crash-handler` | fork, `tests/media/`, `tools/sandbox/tests/` |
| A9 (parte) | Portada saltable con clic/Esc y tope de 12 s | `host/src/splash.cpp` |

**Sale cuando:** 2 h de X/Shorts en Brave y Chrome sin crashes; `test-crash-handler` y `run-local-suite` en verde;
`test-install` 0 fallos. Notas: "Arregla los cierres de ii al ver videos en el navegador (existía desde la 0.1.3)".
Instalación manual (Setup), porque la 0.6.0 no tiene actualizador.

---

## 0.7.0 · "Se actualiza solo" — 8–12 días

| ID | Qué |
|---|---|
| B1–B8, B10–B12 | Actualizador completo: `release.json` firmado, buscar, avisar (notificación, puntito, tarjeta, página), bajar con reanudación, verificar, instalar sin PowerShell, aplicar al reiniciar o ahora, volver atrás, canales |
| A4 (completo) | Modo seguro por firma y completo, ventana propia en vez de `MessageBox` |
| A5 (arreglo) | `SHQueryUserNotificationState` y llamadas a Explorer fuera del hilo principal |
| A6 | Auditoría de nulos/esperas en el resto del código nativo + "día de caos" |
| A7 | `pending → ready → verified` y oferta de volver atrás tras 3 crashes |
| A9 (resto) | "La última vez ii tuvo problemas", "Pausar ii por hoy", reporte en 1 clic con crashes |
| C4.2, C5 | Sliders que escriben al soltar; una sola ventana de Configuración y `openSettings(page)` |
| D3, D4, D7 | Carátulas sin procesos; conserje de cachés; presupuesto de avisos QML |
| F1 (E10) | Indicadores de micrófono/cámara/ubicación en uso |
| G1–G3, H1 (inicio) | Ramas, CI básica (compilar + pruebas unitarias), reportes con firma, auditoría de español |

**Sale cuando:** B10 completo en verde; actualización real 0.6.1 → 0.7.0 → 0.7.1 (de prueba, canal beta) y vuelta atrás
en la PC real; 3–7 días en beta sin crashes nuevos (G4).

---

## 0.8.0 · "Configuración nueva y más liviano" — 8–10 días

| ID | Qué |
|---|---|
| C1–C3, C6–C8 | Nueva organización, galería de widgets con registro, Reloj con pestañas, buscador de ajustes, ajustar desde el escritorio |
| C4 (resto) | `LazySection`, páginas vivas, medición `II_SETTINGS_BENCH` |
| D1, D2, D5, D8 | Rastreador de ventanas incremental; todo widget se pausa tapado; arranque con portada corta y precalentado; *soak* de 8 h |
| E16 | Atajos editables |
| F2, F3, F4, F14, F17, F23 | Reinicio pendiente de Windows, actualizaciones de apps (winget), ahorro de energía, poco espacio, apps que piden atención, multi-monitor |
| G2 (completo), G6 (winget) | CI con parches, lint y paquete; primer manifiesto de winget |

**Sale cuando:** C8 y D-criterios cumplidos (cada página < 150 ms; −70 % CPU del rastreador; ~0 % GPU con el escritorio
tapado; arranque en frío < 8 s en esta PC).

---

## 0.9.0 · "El Plus" — 12–18 días

| ID | Qué |
|---|---|
| E1 (MVP) | Buscar todo: ventanas, ajustes de ii y Windows, comandos, conversiones |
| E2 (MVP) | Modos Clase/Trabajo, Juego, Presentación, Noche con disparadores manual, horario y app |
| E3 (MVP) | Panel Hoy + horario de clases |
| E5, E6, E7, E8 | Audio (salida en 1 clic, micrófono global, batería BT), dock que avisa y recuerda, capturas con anotación/QR/fijar, portapapeles con memoria |
| E9 | Compatibilidad con StartAllBack, PowerToys, Windhawk… |
| E11, E12, E13 | Bienestar, notificaciones agrupadas, fondo del día / por hora |
| F6, F7, F9, F10, F16, F18–F21, F24 | Integraciones del catálogo marcadas 0.9.0 |
| H2–H5 | Teclado, accesibilidad, pulido, recorrido y novedades |

---

## 1.0.0 · "Para todos" — 10–15 días

| ID | Qué |
|---|---|
| E1 (completo) | Archivos del índice de Windows / Everything |
| E2, E3 (completos) | Más disparadores (Wi-Fi, monitor, cargador, presentación) y calendarios ICS |
| E4 | Galería de temas (exportar/importar) y widgets oficiales por la galería |
| B9 | Actualizaciones pequeñas (delta) |
| G5, G6 | Firma de código (SignPath), winget estable, página web |
| H6 | Nombre definitivo decidido antes de winget/web |
| E14 (opcional) | IA local primero, apagada por defecto |

**Sale cuando:** G7 completo en al menos 3 máquinas distintas (esta PC, la laptop AMD 150 %, una con NVIDIA) y 14 días
seguidos de uso diario del autor sin crashes.

---

## Dependencias (qué necesita qué)

```
A1 ─┬─> 0.6.1
A3 ─┤      └─> A4 (usa firma y subsistema) ─> A7 (cuenta crashes por versión)
A8 ─┘
B1 (release.json firmado) ─> B2 (buscar) ─> B3 (avisar) ─> B4 (bajar) ─> B5 (instalar) ─> B6/B7 (aplicar, volver)
                                                                     A7 ──────────────┘
C2 (registro de widgets) ─> C6 (engranaje en el escritorio) ─> E4 (widgets de la galería)
C3 (índice de ajustes) ─> E1 (ajustes en Buscar todo) ─> E14 (ajustes por lenguaje natural)
D1 (rastreador incremental) ─> D2 (cobertura por eventos) ─> E2 (disparador "app al frente")
E2 (modos) ─> E12 (No molestar automático) / E3 (horario de clases dispara "Clase")
G2 (CI) ─> G6 (winget en cada etiqueta)
```

## Riesgos y cómo se cubren

| Riesgo | Cubierto por |
|---|---|
| Un arreglo de mpris que cambia el comportamiento con Spotify u otros reproductores | A1.3 regresión manual + `ii-mpris-stress` |
| El actualizador deja a alguien sin ii | Versiones lado a lado + `ii-launcher` vuelve solo + B10 |
| Robo del token de GitHub y una release falsa | `release.json` firmado con clave fuera del repo (B1) |
| Una API no documentada cambia con una actualización de Windows | Aislada en `ii-shim`, comprobación de build, se apaga sola (A6, F) |
| Más funciones = más lento | Presupuesto: cada página < 150 ms, *soak* plano, ~0 % con escritorio tapado (C8, D) |
| Conflictos con otras apps de personalización | E9 + `shortcuts.ini` |
