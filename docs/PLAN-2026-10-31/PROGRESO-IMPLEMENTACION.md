# Progreso de la implementación del plan (desde 2026-10-31 noche)

Ramas: `impl/plan-2026-10-31` en ii-windows y en el fork `quickshell`. Nada subido (*push*) ni publicado.

Leyenda: ✅ hecho y probado · 🟡 hecho, prueba parcial · ⏳ pendiente

| ID | Estado | Notas |
|---|---|---|
| A1 mpris | ✅ | Fork 4941949. `test-mpris-stress` 877 y 2356 sesiones sin fallo; con el código viejo, crash 0xC0000005 a los 163 s (reproducción confirmada). |
| A3 manejador de crashes (shell) | ✅ | `crash.cpp`/`crash.hpp`: dump + JSON + subsistema; probado con `II_TEST_CRASH=null/mpris/terminate/abort`. |
| A8 herramienta de estrés | ✅ | `ii-media-churn.exe`, `tests/media/mpris-watch`, `tools/sandbox/tests/test-mpris-stress.ps1`. |
