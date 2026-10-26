## ii-windows 0.6.0 (beta)

> ⚠️ **Sin probar todavía en un PC con tarjeta gráfica dedicada (NVIDIA/AMD) ni con juegos.** Esta versión se probó en una laptop con gráfica integrada AMD a 150 % de escala. Lo relacionado con juegos (la tecla Windows y Alt+Tab encima de un juego, quitar el gancho del teclado con anticheats como el de Valorant, el latido que reinicia ii si un juego pesado lo congela) y con gráficas dedicadas (lag en laptops gamer, preferencia de GPU) solo se probó con simulaciones. Si juegas o tienes una gráfica dedicada, pruébala con cuidado y reporta lo que veas (menú Inicio → ii-windows → Reportar un problema).

**Instalar:** descarga `ii-windows-Setup-0.6.0-….exe`, ábrelo y sigue Siguiente → Acepto → Instalar. Windows avisará de que el instalador no está firmado (aún no lo está): "Más información → Ejecutar de todas formas". Todo se instala solo para tu usuario y se puede deshacer (Rescate de ii: Ctrl+Alt+Mayús+R; Desinstalar desde Configuración → Aplicaciones). El `.zip` es lo mismo sin asistente (`install.cmd`). Se instala encima de la 0.5.0 conservando tu configuración.

### Nuevo
- **Alt+Tab de ii:** mantén Alt, Tab avanza (Mayús+Tab o ← retrocede), al soltar se elige y Esc cancela. Miniaturas en vivo en orden de uso y el dock visible mientras tanto. Encima de un juego sigue siendo el de Windows.
- **El dock aparece con el menú de apps** (tecla Windows) y con la vista de ventanas, y se vuelve a esconder al regresar a la app o al juego.
- **Barra "Junto al dock":** nueva posición de la barra. Sus cosas (bandeja, reloj, red, sonido, batería, recursos, escritorios, música) en dos pastillas a los lados del dock, que nunca se le montan encima: si falta espacio, quitan primero la fecha y luego agrupan la bandeja en un botón.
- **Minimizar hacia el dock:** la ventana se va al dock con una animación propia (duración y curva en Configuración → Interfaz).
- **Aviso del cargador:** al conectar o desconectar, la píldora dice "Cargando · 45 %".
- **Estilo sobrio** en el recorrido de bienvenida, para quien viene de Windows: barra junto al dock, dock fijo, colores neutros. Se deshace con un botón.
- **Teclas multimedia (opcional):** con `shortcuts.ini [audio] mediakeys=ii`, play/pausa y siguiente van al reproductor de ii.
- **Sonidos de la interfaz** más suaves y bajos.

### Más rápido y más estable
- **Al presionar Windows ya no se traba:** el lanzador está listo desde el arranque.
- **Si la interfaz se congela** (por ejemplo con un juego pesado), en unos 5 s vuelve la barra de Windows y ii se reinicia solo. Con un juego al frente espera a que termine.
- **Dibujo en un hilo aparte** en PCs con gráfica: un momento de mucho trabajo ya no congela la pantalla (Configuración → Apariencia → Dibujo, por si en algún PC falla).
- **Menos procesos en segundo plano** (fondo animado, brillo) y la interfaz siempre precompilada: menos memoria en el primer arranque.
- La **luz nocturna** ya no se enciende sola, y **nunca vuelve a salir el fondo café**.
- **Wallpaper Engine** no debería pausarse al tocar la barra o el dock (falta comprobarlo con el programa real).
- La tecla Windows **nunca se pierde**: si ii no puede mostrarse, se abre el Inicio de Windows.
- Ventanas de Configuración que no cabían a 150 % de escala.

### Sin comprobar todavía
- **PC con gráfica dedicada y juegos** (ver el aviso de arriba): osu!, Valorant, laptop con RTX 5070 Ti, un juego pesado que congele la shell.
- **Wallpaper Engine** con la pausa activada.
- "Junto al dock" en una pantalla pequeña con muchas apps.

### Pendiente
- **Firma de los ejecutables** (por eso Windows y algunos antivirus avisan).
- **Actualizador automático:** por ahora hay que descargar cada versión a mano. Ver `docs/AUTOACTUALIZADOR.md`.

Código del fork de Quickshell: https://github.com/TheCarlosS5/quickshell-windows (etiqueta `ii-windows-v0.6.0`).
