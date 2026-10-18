## ii-windows 0.5.0 (beta)

**Instalar:** descarga `ii-windows-Setup-0.5.0-20261018-1d1b3f1.exe`, ábrelo y sigue Siguiente → Acepto → Instalar. Windows puede avisar de que el instalador no está firmado (aún no lo está): "Más información → Ejecutar de todas formas". Todo se instala solo para tu usuario y se puede deshacer (Rescate de ii: Ctrl+Alt+Mayús+R; Desinstalar desde Configuración → Aplicaciones). El `.zip` es lo mismo sin asistente (`install.cmd`).

### Una pantalla de carga nueva, estilo Material 3 Expressive
- Tu foto de cuenta (o la inicial de tu nombre) sobre una forma "cookie" que gira despacio, rodeada por un **anillo de progreso ondulado** que avanza con lo que de verdad va cargando y se alisa al terminar.
- Un saludo según la hora ("Buenas tardes, …"), lo que se está preparando, y la hora y la fecha como en la pantalla de bloqueo de un Pixel. De fondo, tu propio fondo de pantalla difuminado: al final se funde con tu escritorio.
- **Sin parpadeos:** la barra y el dock ya no se asoman por encima mientras carga.
- **La tecla Windows no abre nada mientras carga** (ni Inicio ni StartAllBack).
- Nítida en pantallas al 125 % / 150 %, y más ligera en PCs lentos (baja sola a 30 fps).

### Nuevo
- **Letra de canciones en el widget de música del escritorio** (opcional, apagada por defecto): la línea que suena grande al centro, las demás desvanecidas, y las líneas largas se acomodan dentro de la tarjeta. Se activa en Configuración → Widget: Música, en *Editar escritorio* o con clic derecho sobre el widget.
- **Tienda de apps rehecha:** carrusel de recomendadas, una fila por categoría con "Ver todo", categorías en cuadrícula, búsqueda tipo píldora, y una barra abajo con lo que se está instalando o actualizando.
- **Win+R** abre el "Ejecutar" de Windows (cmd, regedit, %appdata%, rutas…).
- **El recorrido de bienvenida abre lo que explica:** el buscador, el dock, el panel derecho y el izquierdo, cada uno en su paso.

### Arreglos
- **Dock a la izquierda o a la derecha:** la barra de arriba ya no se corre; el dock se acomoda entre las barras, y los widgets del escritorio no quedan debajo de él. Con la barra abajo, el dock flota encima de ella.
- **Buscar apps con la rueda del ratón ya no se traba:** las casillas se preparan por adelantado y el desplazamiento es suave.
- Los **nombres del dock** ya no aparecen pegados a la izquierda de la pantalla al pasar el ratón muy rápido.
- **Tienda:** las apps ya instaladas no salen como "Instalar" mientras winget responde; winget en otros idiomas se entiende.
- **Instalación nueva:** ii usa **el fondo que ya tenías en Windows** (antes ponía el suyo marrón) y no agrega el widget de "Recientes".

### Sin comprobar todavía
Portátil real (batería, brillo, GPU híbrida), un PC lento real, pantallas de varios monitores con escalas distintas en la pantalla de carga.

Código del fork de Quickshell: https://github.com/TheCarlosS5/quickshell-windows (etiqueta `ii-windows-v0.5.0`).
