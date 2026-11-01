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
| B3 aviso/UI | 🟡 | Host: búsqueda/avisos con botones (compila). QML: Updates.qml, UpdatesConfig.qml, punto en barra, About — SIN PROBAR. |

## Retomar aquí
1. `stage-ii.ps1` falla en **patch_ii_perf.py** (antes de plan31) tras añadir el bloque B3 de patch_ii_plan31.py: ejecutar
   `python -I tools/port/patch_ii_perf.py` con `II_STAGE_DIR=build/ii` para ver el error (¿build/ii a medias?).
2. Probar páginas Updates/About con settings-check.ps1; humo de la shell; confirmar (commit) lo pendiente.
3. Siguiente: publish-release.ps1, F1 indicadores de privacidad, D4 conserje, C (galería de widgets), D1/D2, Plus.
