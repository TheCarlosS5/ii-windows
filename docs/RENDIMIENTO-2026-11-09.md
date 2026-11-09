# Correcciones de rendimiento — 9 de noviembre de 2026

Correcciones en la rama `main` de dos repositorios:

- `ii-windows`, base `3816d17`, en `C:\Users\Admin\ii-windows`.
- `quickshell-windows`, base `8a81403`, commit de las correcciones `30fb3f6`, en `quickshell/` (repositorio independiente, ignorado por el padre).

Los cambios se guardan en commits locales. Ambos repositorios deben publicarse al integrar el trabajo.
Se exportó también el diff del fork en `build/quickshell-performance.patch` como copia local.

| Problema | Corrección |
| --- | --- |
| Arranque con caché vacía | El compilador se supervisa desde un temporizador, sin bloquear el bucle de mensajes. Un Job Object elimina el proceso al cerrar el host. Explorer se oculta después de que la shell esté lista. El fallo y el timeout permiten continuar; solo el éxito guarda la marca de compilación. |
| Consultas a Explorer | Un trabajador dedicado crea, usa y libera COM en su propio apartamento. El hilo gráfico lee la última respuesta válida. Se agrupan solicitudes y se descartan respuestas de una generación anterior de escritorios o de una ventana destruida. Los escaneos de respaldo también actualizan candidatos ocultos. |
| Miniaturas quietas | Se comparan destino, recorte, visibilidad, opacidad y flags antes de llamar a DWM. La caché solo se actualiza tras una llamada exitosa y se invalida al registrar otra miniatura. Se conservan los eventos y el sondeo que detectan animaciones y cambios de ventana. |
| Modelo QML en reposo | Se elimina el temporizador de un segundo y la serialización completa a JSON. Las señales agrupan cambios durante 30 ms y reconstruyen los clientes afectados. Los objetos de ventanas sin cambios conservan su identidad. |
| CAVA por monitor | `AudioSpectrum` comparte un productor entre widgets y panel multimedia. Las suscripciones controlan su vida; modo Ligero y bloqueo lo detienen. Se fuerza el cierre del productor de consola porque `QProcess::terminate()` usa WM_CLOSE en Windows. |
| GIF oculto | `AnimatedImage.paused` sigue `desktopCovered`, conservando el fotograma para reanudarlo. |

No se cambiaron estilos, tamaños, textos, controles ni disposición de la interfaz.

Validación realizada en Windows con clang-cl 23 y Qt 6.12:

- Compilación de `ii-host`, `ii-shim`, los productores de prueba y Quickshell: correcta.
- `test-host-precompile-async.ps1`: 21 aserciones, incluyendo cierre durante compilación, éxito, fallo y timeout.
- `test-host-precompile.ps1`: 7 aserciones, incluyendo reutilización de caché.
- `test-host-launch.ps1`: 38 aserciones sobre arranque, reintentos y recuperación.
- `test-performance-native.ps1`: 15 aserciones. Con una consulta a Explorer retrasada 10 s, el temporizador gráfico y el cierre terminaron en 2,18 s. Con 12 miniaturas visibles durante unos 3,2 s, se enviaron 24 actualizaciones a DWM y se omitieron 864 idénticas. El espectro pasó las nueve comprobaciones de suscripciones, datos, modo Ligero, bloqueo y destrucción; hubo un productor por periodo activo.
- `test-toplevels.ps1 -Seconds 5 -Extra 12`: 7 aserciones sobre altas, título, minimización, atención y cierre de ventanas.
- `node tests/performance/test.js`: modelo incremental, identidad de ventanas sin cambios, foco, escala, escritorios y suscripciones.
- Staging reproducible: 11 aserciones; sintaxis QML: 3; sintaxis PowerShell, finales de línea y revisión de whitespace: correctos.
- Precompilación del árbol QML preparado completo: salida 0. La herramienta informa 685 archivos compilados y 3 componentes que requieren contexto para compilarse.

Estas pruebas verifican el trabajo eliminado y la capacidad de respuesta ante demoras controladas. Sigue pendiente una comparación completa antes/después de CPU, GPU y arranque de ii en una sesión normal con dos monitores. Los contadores de miniaturas se activan con `QS_THUMBNAIL_STATS=1`; los registros de las pruebas quedan en `build/performance-*.log`.

Para repetir las pruebas nuevas después de compilar y desplegar:

```powershell
node tests/performance/test.js
./tools/sandbox/tests/test-host-precompile-async.ps1
./tools/sandbox/tests/test-performance-native.ps1
```

Las pruebas que limpian todos los procesos de una misma ruta de Quickshell deben ejecutarse en secuencia.
