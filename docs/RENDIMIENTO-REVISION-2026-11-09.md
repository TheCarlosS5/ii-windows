# Segunda revisión de lógica y rendimiento

Correcciones sobre ii-windows `47c393a` y quickshell-windows `30fb3f6`; el commit del fork que las completa es `b6361b0`. Se publican con el instalador como una versión de prueba, sin instalarlo en la sesión del usuario.

| Caso | Corrección |
| --- | --- |
| Cancelar una versión pendiente | El host devuelve el código específico 18 cuando se cancela voluntariamente antes de estar listo. El lanzador conserva la versión pendiente y devuelve el intento al contador, sin activar la anterior. Los fallos reales siguen provocando recuperación. |
| Escala, resolución y área útil | HyprlandData escucha también `geometryChanged`. El fork propaga los cambios del área útil y notifica el cambio de su objeto de monitor. |
| Traslado con Explorer lento | El rastreador conserva las ventanas conocidas que Windows oculta mientras su consulta de escritorio está pendiente. Al terminar la consulta vuelve a evaluar su pertenencia sin emitir un cierre intermedio. |
| Recuperación durante precarga | Las opciones de recuperación usan una ventana nativa independiente. La precarga puede continuar; el lanzamiento de la shell espera la decisión o el plazo original de nueve segundos. «Hoy no» cancela sin revertir la actualización. |
| Publicaciones durante arrastre | La posición y el tamaño se exponen mediante propiedades observables por ventana. Los consumidores siguen recibiendo geometría actualizada, conservando la lista, su índice y los resúmenes de escritorios. Los cambios reales de pertenencia siguen publicándose. |
| Traspaso de CAVA | Las suscripciones se agrupan durante 30 ms antes de decidir la demanda. Una baja seguida de un alta conserva la captura; modo Ligero y bloqueo siguen deteniéndola inmediatamente. |

Comprobaciones realizadas en Windows:

- Compilación de host, lanzador y fork: correcta.
- `test-startup-cancel-recovery.ps1`: 40 aserciones con el host y el lanzador reales. Incluye cuatro cancelaciones alternando cierre y pánico, y las decisiones Modo seguro/Hoy no con el compilador ya terminado.
- `test-performance-native.ps1`: 22 aserciones. Incluye geometría reactiva sin publicación del modelo, DPI simulado de 100 % a 200 % con foco fijo en Qt real, traslado de la ventana de prueba a otro escritorio existente con respuestas de Explorer retrasadas, y diez comprobaciones de CAVA. El traspaso entre consumidores no añade otro productor.
- La prueba de 12 miniaturas visibles registró 24 envíos a DWM y 864 actualizaciones idénticas omitidas.
- `test-host-precompile-async.ps1`: 21 aserciones; `test-host-launch.ps1`: 38; `test-runtime.ps1`: 74. Se mantienen los casos de rollback por fallo real e instalación interrumpida.
- Node: 40 ventanas y 8 escritorios, con 90 movimientos sin sustituir las listas ni los resúmenes de escritorios. Se comprueban también las altas/bajas agrupadas de CAVA.
- Árbol preparado y precompilación QML completa: correctos (685 componentes compilados; 3 requieren contexto). La herramienta de Qt dejó avisos de destrucción de hilos al finalizar, con código de salida 0.
- El proceso PowerShell 5.1 de la prueba de instalación interrumpida inicializa su propia ruta de módulos, evitando heredar los módulos incompatibles del PowerShell 7 del entorno de desarrollo.

Instalador generado: `out/ii-windows-Setup-0.9.0-20261109-47c393a.exe`, sin las imágenes ni el icono personalizados de ii-windows. Se comprobó visualmente la pantalla inicial con el diseño estándar y se cerró el asistente antes de instalar.

El paquete contiene fuentes, iconos y cursores completos; su manifiesto de 2739 archivos se verificó sin discrepancias. Es una compilación sin firma digital, con `dirty: true` en build-info.json porque se compiló antes de guardar estas correcciones en commits. Sigue pendiente comparar CPU/GPU y tiempo de arranque completos antes/después en una sesión normal.
