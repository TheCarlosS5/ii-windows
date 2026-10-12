# Punto de retomada (2026-10-11)

Dónde quedó el trabajo sobre `TASKS_ii_windows.md`, para poder continuar sin releer la conversación. La fuente de verdad por tarea es `docs/seguimiento/<ID>.md` (y la sección 15 de `TASKS_ii_windows.md`, generada con `python -I tools/dev/tasks_status.py sync`).

## Estado

- **VERIFICADA (4):** B00, B01, R04, F01.
- **IMPLEMENTADA_SIN_VALIDAR_WINDOWS (16):** B02, R01, R02, R03, R05, R06, R07, R08, R09, R11, P04, P11, P15, U02, C12, D01. Hechas y con pruebas locales; falta validación de extremo a extremo (Win+L real, RDP, segundo usuario, notificaciones reales, etc.). Cada entrada dice qué falta.
- **EN_CURSO (3):** P12 (inventario de temporizadores, AppBar/layout), P17 (CI, manifiesto de compilación, cachés; `deploy.ps1` y `make-package.ps1` ya no dependen de la ruta de Visual Studio), U01 (catálogo solo de atajos; faltan tiles, menús, IPC, diálogos).
- **TODO (50):** R10; P01 P02 P03 P05 P06 P07 P08 P09 P10 P13 P14 P16 P18; U03–U09; W01–W04 (fondos externos); C01–C11 y C13; Q01–Q03 (cierre/paquete); X01–X10 (ideas, no se implementan).

## Hecho fuera de la lista de tareas (hallado probando en el escritorio real)

- Panel izquierdo que se cerraba con cualquier clic: la región de entrada no seguía a elementos movidos por `transform` (`quickshell`, `core/region.cpp`). Prueba `test-input-region`.
- Cuelgue intermitente al arrancar la shell: auto-bloqueo en `WindowTracker::instance()` (`toplevels.cpp`).
- Paquete sin la carpeta `shapes` del QML de upstream (submódulo sin inicializar): `check-qml-imports.py` en `stage-ii.ps1`, `smoke-shell.ps1`.
- Herramientas: `tools/dev/stackdump.cpp` (pilas de un proceso colgado), `tools/dev/smoke-shell.ps1`.

## Lanzamiento 0.2.0

Publicado en GitHub (`v0.2.0`, zip adjunto). Instalado en el escritorio del usuario; inicio con Windows migrado al lanzador. Detalle y límites: `docs/RELEASE-0.2.0.md`. **No probado en portátiles** ni con varios monitores.

## Siguiente, por este orden

1. Probar la 0.2.0 en un **portátil** (batería, brillo, tapa, GPU híbrida) y con varios monitores; sin eso no es «estable para portátiles».
2. Cerrar las tres EN_CURSO (U01 tiles/menús/IPC; P12 temporizadores; P17 CI y manifiesto).
3. R10 (convertir pruebas antiguas en regresiones con aserciones) y las P1 de rendimiento: P01, P02 (miniaturas DWM solo al cambiar), P03.
4. U03–U09 (interfaz), D01 restante (botones de exportar/importar en ajustes, migraciones).
5. W01–W04 (Wallpaper Engine / Lively): sin proveedor instalado en esta máquina.
6. C01–C13 y Q01–Q03 (cierre, documentación, paquete); las X no se hacen.

## Decisiones/avisos pendientes del usuario

- Probar una conversación real con IA (necesita clave: `/key` en el panel) y Gelbooru (clave de API).
- La tarea de inicio `ii-windows` fue reapuntada al lanzador con permiso de administrador; la 0.1.3 plana sigue en la carpeta de instalación como vuelta atrás (`current.txt`, `previous=`) hasta que una versión nueva quede verificada.
