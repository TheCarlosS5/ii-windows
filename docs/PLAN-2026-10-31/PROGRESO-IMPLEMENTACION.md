# Progreso de la implementación del plan (desde 2026-10-31 noche)

Ramas: `impl/plan-2026-10-31` en ii-windows y en el fork `quickshell`. Nada subido (*push*) ni publicado.

Leyenda: ✅ hecho y probado · 🟡 hecho, prueba parcial · ⏳ pendiente

| ID | Estado | Notas |
|---|---|---|
| A1 mpris | ✅ | Fork 4941949. `test-mpris-stress` 877 y 2356 sesiones sin fallo; con el código viejo, crash 0xC0000005 a los 163 s (reproducción confirmada). |
| A3 manejador de crashes (shell) | ✅ | `crash.cpp`/`crash.hpp`: dump + JSON + subsistema; probado con `II_TEST_CRASH=null/mpris/terminate/abort`. |
| A8 herramienta de estrés | ✅ | `ii-media-churn.exe`, `tests/media/mpris-watch`, `tools/sandbox/tests/test-mpris-stress.ps1`. |
| A2 QML multimedia, D7 avisos | ✅ | patch_ii_plan31.py; settings-check.ps1 sin errores nuevos. |
| A4 política de crashes + modo seguro | ✅ | crashpolicy.* (23 pruebas), test-host-crash-policy (29). |
| A5 hilo del host | ✅ | SHQueryUserNotificationState en su hilo (notifystate.cpp). |
| A3.2 símbolos | ✅ | PDB en release, sin rutas de la máquina; symbolize.ps1, crash-locate.py. |
| A7 ready/verified + rollback | ✅ | rollout markReady/markVerified/rollBack; orden `rollback`. |
| A9 portada | ✅ | Clic/Esc, 3 opciones tras problemas, "Hoy no"; capturas revisadas. |
| B1–B5, B10 actualizador | ✅ | ii-shim update (test-updater 39 ok); claves en %USERPROFILE%\.ii-release-key (¡respaldar!). |
| B3 aviso/UI | ✅ | Host: búsqueda cada 6 h, avisos con botones (Actualizar/Novedades/Más tarde). QML IiUpdates + Configuración > Actualizaciones + punto en la barra + Acerca de (capturas). Upstream ya tenía services/Updates.qml (Arch): los nuestros son IiUpdates / config iiUpdates. |
| B1.3 publish-release.ps1 | 🟡 | Sintaxis ok; falta -DryRun con un paquete real (al final de la ronda). |
| F1 indicadores de privacidad | ✅ | PrivacyMonitor (fork) + barra; test-privacy-monitor 5/5, captura. |
| D4 conserje + desinstalador | ✅ | ii-shim janitor diario, host.log rota a 2 MB; test-janitor, test-ownership. |
| C5 una ventana + C4.2 sliders | ✅ | SingleInstance (fork); probado con dos lanzamientos. |
| A6 auditoría nativa | ✅ | `check-winrt-null.py` + test-winrt-null; getters WinRT revisados. |
| H1 español | ✅ | `find-untranslated.py` + test-untranslated: 0 textos sin es_MX. |
| G2 CI básica | 🟡 | `.github/workflows/build.yml` escrito; nunca corrido en GitHub (no se sube sin permiso). |
| C2 galería de widgets + C6 engranaje | ✅ | `gen_widget_pages.py` (915 → 84 líneas), WidgetGallery, engranaje en modo edición → `backgroundconfig/<widget>` (SettingsRequest). Capturas. |
| C2.4 reloj con pestañas | ✅ | Estilo · Esfera · Manecillas · Fecha · Cita; aviso en las de Cookie. |
| C3 buscador + C8 | ✅ | `gen_settings_index.py` (304 entradas), sinónimos, Ctrl+F, salta y resalta (también dentro de widgets/pestañas). `check-settings-search.py` 72/72, test-settings-search. |
| C4.1 LazySection | ✅ | `gen_lazy_sections.py` (27 secciones). `settings-switch-bench.ps1`: todas las páginas < 150 ms al cambiar (Paneles 135 → 87 ms). |
| C1/C7 reorganización | ✅ | `compose_settings_pages.py`: página Rendimiento nueva, General → Sistema, animaciones de ventanas y fondos animados a Apariencia, avisos de la barra en Paneles › Notificaciones. |
| D1 rastreador incremental | ✅ | Fork: un evento relee solo su ventana; AppId/escritorio en caché; escaneo completo de red cada 10 s. `test-toplevels`: 62 ms vs 516 ms de CPU con 17 ventanas (−88 %). |
| D2 escritorio tapado | ✅ | Arreglo de fondo: las ventanas no tenían pantalla (QScreen::name ≠ nombre del dispositivo) → DesktopCover nunca tapaba. Ahora por HMONITOR; DesktopCover por eventos; DesktopTime para relojes; tarjeta de recursos quieta. `test-desktop-cover` (164 ms / 211 ms). D2.4 (barra bajo pantalla completa) no hecho: solo redibuja 1/min. |
| D5 arranque | 🟡 | Portada (A9) y fases ya estaban. Precalentado (D5.2/D5.3) **no** hecho: el Prefetcher de Windows ya carga exe/DLL; hace falta un trazo WPR de un inicio de sesión real con ii instalado para decidir. |
| D8 memoria | 🟡 | `tools/dev/soak.ps1` (CSV + veredicto). Falta la corrida de 8 h con ii instalado. |
| F17 apps que piden atención | ✅ | Fork: `urgent` por shell hook (HSHELL_REDRAW sin título nuevo = parpadeo). Dock: rebote + punto terciario. test-toplevels 7/7. |
| F2/F14 reinicio pendiente / poco espacio | ✅ | ii-host `syshealth.cpp` (hilo propio, cada hora), avisos con botón a ms-settings (lista cerrada), `system-status.json`, sesión "Actualizar y reiniciar", Sistema > Avisos de Windows. `test-host-syshealth` 14/14. |
| F4 ahorro de energía | ✅ | Interruptor rápido (estado por SystemStatusFlag; abre su página, Windows no deja cambiarlo). |
| F3 actualizaciones de apps | ✅ | La tienda ya tenía "Actualizar todo"; ahora el dock muestra el número (AppUpdates, winget cada 12 h). 34 = 34. |
| F23 multi-monitor | 🟡 | Barra y dock: todas las pantallas o solo la principal. Sin segundo monitor aquí para verlo. |
| E16 atajos | ✅ | Host: `[keys]` en shortcuts.ini (tabla en tiempo de ejecución, 102 pruebas). Configuración > Atajos: lista, cambiar con conflictos, juegos y teclas de audio. Probado a mano. |
| G6 winget | ✅ | `make-winget-manifest.ps1` (validado con `winget validate`). El PR a winget-pkgs lo hace el autor. |
| Cierre 0.8.0 | ✅ | Paquete `ii-windows-0.8.0-20261101-8410070` + Setup, `publish-release -DryRun` firmado con la clave real, `test-updater-real` 13/13. Suite local: 32 ok; test-config (línea de log vieja), los tests que buscaban ii-shim solo en build-clang (`Get-IiShim`) y test-vdesk (marcos UWP ocultos) arreglados. **Hay que rehacer el paquete**: ver la fila siguiente. |
| Tarea de inicio (R06) | ✅ | Error real: la tarea vieja `\ii-windows` y la carpeta nueva `\ii-windows\` tienen el mismo nombre; registrar la nueva antes de borrar la vieja dejaba una tarea que Windows no carga (sin inicio automático y `Get-ScheduledTask` roto en todo el PC; **este PC lo tiene**: arreglo de una vez como administrador `schtasks /delete /tn \ii-windows /f`). Ahora la vieja se va primero, se lee por COM y "registrada" = Windows la carga (si no, entra la clave Run). test-autostart 31/31 con el caso de colisión. |
| E1 Buscar todo (MVP) | ✅ | `SearchPlus.qml` + `search_plus.js`: ventanas abiertas, ajustes de ii (índice de C3, abre y resalta con `locate:`), 61 páginas de Configuración de Windows, 31 acciones rápidas, conversiones (unidades, %, monedas open.er-api.com con caché diaria, hora en otra ciudad con `ii-shim timezones`). Un solo ranking con las apps. Node 76/76, test-search-plus 14/14 (incluye una ventana real). Archivos (índice de Windows/Everything) quedan para la 1.0 como dice el plan. |
| E2 Modos (MVP) | ✅ | `Modes.qml` + `modes_logic.js`: Clase/Trabajo, Juego, Presentación, Noche; manual (chips del panel derecho, búsqueda), horario (también de noche a mañana), apps abiertas (Juego: lista de juegos; opcional pantalla completa). Devuelve solo lo que sigue como lo dejó. Configuración > Modos. Node 40/40, `test-modes -EndToEnd` 10/10 (config.json respaldado y devuelto idéntico). Wi-Fi/monitor/cargador/presentación: 1.0. |
| E3 Hoy + horario | ✅ | Pestaña Hoy (saludo, clima, clases con Unirme, pendientes, batería, música); Servicios > Horario de clases; aviso N min antes con botón Unirme (`notify-send --ii-button`, orden de host `class-join` → atajo `classJoin`). Node 14/14, `test-timetable -EndToEnd` 8/8 (config y lista de avisos devueltos idénticos). ICS: 1.0. |
| E5 audio | ✅ | Batería de dispositivos Bluetooth en el fork (propiedad del nodo, PRO60 = 90 % leído), aviso < 20 % / < 10 %; Win+Mayús+A silencia el micrófono del sistema (host). Cambiar la salida ya existía (IPolicyConfig del fork). |
| E6 dock | 🟡 | Papelera en el dock (llena/vacía, abrir, vaciar) y contador de notificaciones por app. Arreglado: el globo "-1 apps se pueden actualizar" salía en todos los iconos. Recientes por app y pila de Descargas: 1.0. Progreso de descargas: descartado (exige tocar Explorer). |
| E9 compatibilidad | ✅ | `compat.json` (15 apps), `ii-shim compat`, Avanzado > Compatibilidad, línea en el reporte. Aquí detecta StartAllBack y PowerToys. |
| E7 capturas | 🟡 | Fijar una captura en pantalla (`crop … pin`, clic central / `regionPin` / búsqueda "Fijar una captura"); el selector de color recuerda (colors.txt) y la búsqueda convierte #hex/rgb()/hsl(). La anotación ya existía (Snipping/ii). **QR: no** (hace falta una librería decodificadora; decisión del autor). |
| E8 portapapeles | ✅ | Fragmentos (`search.snippets`, Configuración), pegar como texto plano, OCR de una imagen del historial. Arreglado: las imágenes se tomaban como texto (`\r` final). |
| E11 bienestar | ✅ | `Wellbeing.qml` + `wellbeing_logic.js`: límites diarios por app, descanso de la vista 20-20-20, resumen semanal. Node + `test-wellbeing`. |
| E12 notificaciones | ✅ | No molestar con horario (días, de noche a mañana) y apps VIP que lo atraviesan; resumen "Mientras Clase estuvo activo: llegaron N avisos" al terminar un modo con No molestar; buscar en las notificaciones (app, título, texto). Agrupar por app y deslizar ya existían. Arreglado de upstream: TypeError al borrar todo antes de 7 s. Node 53/53 (modos), probe con dos avisos de prueba. |
| E13 fondos vivos | ✅ | `randomwall bing` (imagen del día en el idioma del PC) o una carpeta propia que rota cada N min; tema claro/oscuro por horario o con el sol (amanecer/atardecer del clima). `DailyLook.qml`, Apariencia › Según el día. Node 37/37, `test-dailylook -Network` (descarga real). NASA APOD/Wallhaven: no (APOD pide clave y a veces es video). Un fondo por escritorio: 1.0. |
| F6/F7 HDR y Hz | ✅ | `ii-shim display` (DisplayConfig/ChangeDisplaySettingsEx; la frecuencia solo por la sesión). Ajustes rápidos HDR y Frecuencia de pantalla. Probado en este PC: 144→120→144 Hz, HDR encendido→apagado, todo como estaba. |
| F9/F10/F18 | ✅ | Ver E5 y E6. |
| F16 listas de salto | ⏳ 1.0 | `IApplicationDocumentLists` ya no devuelve nada en Windows 10/11; habría que leer los `.automaticDestinations-ms` (OLE). Va con "recientes por app" de E6 en la 1.0. |
| F19/F20 alto contraste y tamaño de texto | ✅ | `ii-shim a11y`; el host avisa en cada WM_SETTINGCHANGE; `WindowsAccessibility`: colores del tema de contraste sin transparencias, texto hasta 150 %, sin animaciones si Windows las apaga. Apariencia › Accesibilidad de Windows. Probado con un probe (no se activó un tema de contraste real en este PC). |
| F21 grabar pantalla | ✅ | "Grabar la pantalla" en la búsqueda → Recortes de Windows (`ms-screenclip:?type=recording`). |
| F24 presentación | 🟡 | El host avisa cuando Windows entra/sale de `QUNS_PRESENTATION_MODE` → modo Presentación (y cualquier modo que lo pida). E2E con la señal simulada 12/12. **No** visto con una presentación real: en este PC de escritorio `PresentationSettings /start` solo abre su ventana. |
| H2 teclado | ✅ | Anillo de foco con el color de acento, Enter/Espacio en todos los botones, una parada de Tab por interruptor. Probado con SendInput + UI Automation en Configuración (config.json respaldado y devuelto). Barra: no recibe teclado (ventana sin foco), queda para 1.0. |
| H3 accesibilidad | ✅ | Nombres para el Narrador en botones (texto, tooltip o icono), interruptores (casilla con estado y patrón Toggle), pestañas, ajustes rápidos, dock, notificaciones, campos. UIA: barra+dock 11/11, Configuración 100 % con nombre. |
| H4 pulido | 🟡 | Estados vacíos con acción (notificaciones), sonido suave al activar un modo y al tener lista una actualización. Revisión completa a 150 %: sin pantalla a 150 % aquí. |
| H5 recorrido y novedades | ✅ | Recorrido con Buscar todo, Modos y Hoy; "ii se actualizó a X" con "Ver novedades" (notas firmadas guardadas, `ii-shim update whatsnew`), también en Actualizaciones; modo ligero ofrecido a < 8 GB sin tarjeta gráfica (DXGI). |
| Cierre 0.9.0 | ✅ | Paquete `ii-windows-0.9.0-20261101-d4e3610` (exe con versión 0.9.0) + Setup 62 MB, `publish-release -Beta -DryRun` firmado con la clave real (notas de RELEASE-0.9.0.md dentro), `test-updater-real` 13/13. Suite local 42/43 (test-qs-smoke omitida: falta windeployqt). Arreglados al cerrar: test-search-plus leía la salida sin UTF-8 en la suite; F17 marcaba "pide atención" con cambios rápidos de título (fork 8a81403, test-toplevels 3/3). Nada subido ni publicado. |


## Retomar aquí
0.9.0 hecha (ver filas). Pendiente del autor: borrar la tarea fantasma como administrador (`schtasks /delete /tn \ii-windows /f`),
respaldar `%USERPROFILE%\.ii-release-key`, subir las ramas y publicar (nada se subió).
Trampas: pantalla dormida = capturas viejas (mover el ratón 1 px); heredocs y cadenas de Python comen las barras (usar Write/Edit);
`state` es palabra reservada en QML; upstream ya tiene services/Updates.qml; las pruebas QML que cambian la configuración
escriben el config.json real (respaldarlo y devolverlo, como test-modes); Qt.quit() en Component.onCompleted no cierra (usar un Timer);
un singleton se crea al primer uso (tocarlo al inicio en los probes); leer `data` en una vinculación avisa en cada botón.
