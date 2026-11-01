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


## Retomar aquí
Siguiente (0.7.0): A6 auditoría nativa → H1 español → G2 CI básica. Luego 0.8.0: C1–C3/C6–C8 (galería de widgets, buscador), D1, D2, D5, D8, E16, F2/F3/F4/F14/F17/F23.
Al final de la ronda: make-package + publish-release -DryRun + prueba del actualizador con el paquete real.
Trampas: pantalla dormida = capturas viejas (mover el ratón 1 px); heredocs comen las barras (usar Write/Edit);
`state` es palabra reservada en QML; upstream ya tiene services/Updates.qml.
