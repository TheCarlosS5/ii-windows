## ii-windows 0.4.0 (beta)

**Instalar:** descarga `ii-windows-Setup-0.4.0-20261017-b236122.exe`, ábrelo y sigue Siguiente → Acepto → Instalar. Windows puede avisar de que el instalador no está firmado (aún no lo está): "Más información → Ejecutar de todas formas". Todo se instala solo para tu usuario y se puede deshacer (Rescate de ii: Ctrl+Alt+Mayús+R; Desinstalar desde Configuración → Aplicaciones). El `.zip` es lo mismo sin asistente (`install.cmd`).

### Más rápido y más ligero, sobre todo en PCs modestos
- **Arranque a la mitad** en un PC lento de prueba (~29 s → ~15 s hasta ver el escritorio completo); en un PC normal la bienvenida se va a los ~4,5 s. Los paneles que solo se abren después se cargan *detrás*, por partes, sin congelar nada.
- **El primer inicio ya no es más lento:** el instalador deja la interfaz compilada ("Preparando la interfaz").
- **~120 MB menos de RAM** (las fuentes variables cargaban pesos que no se usan) y casi nada de CPU en reposo: sin procesos repetidos cada pocos segundos, y sin nadie en el PC los avisos de Windows se leen cada 5 s.
- **Modo ligero** (Configuración → Apariencia → Rendimiento → *Ligero*): sin animaciones, sin transparencias en ii ni en tus ventanas, sin espectro de música. El recorrido de bienvenida lo ofrece en PCs con 4 hilos o menos de 7 GB.

### Nuevo
- **Qué está gastando tu PC:** pasa el ratón por el indicador de CPU/RAM de la barra y verás los programas que más usan (sumando sus procesos); un clic abre el Administrador de tareas.
- **Tiempo de pantalla:** pestaña *Uso* en el panel derecho, cuánto estuvo cada programa al frente hoy (solo mientras usas el PC; se queda en tu PC).
- **No molestar por un rato:** el botón de notificaciones del panel derecho silencia 1 hora o hasta mañana a las 8:00 y vuelve solo.
- **Letra sincronizada** de la canción en el panel de música y en el widget (botón de letra; solo entonces se consulta lrclib.net).
- **Cristal esmerilado** detrás de los paneles translúcidos y una **pantalla de bienvenida** como la de Windows mientras ii termina de cargar.

### Arreglos
- La barra lateral izquierda, la fila de apps más usadas y los nombres/iconos ya no se quedan vacíos en PCs lentos; muchos textos que seguían en inglés; GPU dedicada respetada en PCs de sobremesa; el fondo se decodifica una sola vez; el instalador limpia la caché de las versiones que quita.

### Sin comprobar todavía
Portátil real (batería, brillo, GPU híbrida), un PC lento real (las cifras son de un PC limitado por software), Lively real, Gemini con clave real.

Código del fork de Quickshell: https://github.com/TheCarlosS5/quickshell-windows (etiqueta `ii-windows-v0.4.0`).
