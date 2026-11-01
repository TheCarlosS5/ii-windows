## ii-windows 0.8.0 (beta)

> Reúne lo que el plan del 31/10 separaba en 0.6.1, 0.7.0 y 0.8.0: el arreglo de los cierres al navegar, las
> actualizaciones automáticas y la Configuración nueva. **Es la última versión que hay que instalar a mano**: desde esta,
> ii avisa de las nuevas y se actualiza solo.

**Instalar:** descarga `ii-windows-Setup-0.8.0-….exe`, ábrelo y sigue Siguiente → Acepto → Instalar. Windows avisará de
que el instalador no está firmado (aún no lo está): "Más información → Ejecutar de todas formas". Todo se instala solo
para tu usuario y se puede deshacer (Rescate de ii: Ctrl+Alt+Mayús+R; desinstalar desde Configuración → Aplicaciones).
Se instala encima de la 0.6.0 conservando tu configuración.

### Arreglado: ii se cerraba solo al navegar
- **Ver videos en el navegador (X, Shorts, YouTube) cerraba y reabría ii una y otra vez hasta rendirse.** Era la parte de
  multimedia: Windows a veces responde "sin datos" sobre lo que suena, y ii lo leía igual. Existía desde la 0.1.3. Probado
  con miles de sesiones de video falsas apareciendo y desapareciendo: ningún cierre (antes, a los 2–3 minutos).
- Si algo vuelve a fallar, ii **guarda un informe** (qué parte falló) y, si una misma parte falla tres veces, **arranca sin
  ella** en vez de reiniciarse sin fin; a la cuarta, en **modo seguro**. Te avisa con botones: "Ver detalles", "Reportar",
  "Reactivar todo".

### Nuevo: se actualiza solo
- ii busca versiones nuevas cada 6 horas (nunca durante un juego) y te avisa: **Actualizar**, **Novedades**, **Más tarde**.
  También un puntito en la barra y la página **Configuración → Actualizaciones**.
- La descarga se reanuda si se corta, va solo por Wi-Fi o cable (no por datos medidos) y **se comprueba con una firma**:
  una versión que no firmó el autor no se instala.
- La versión nueva se instala junto a la que usas y se estrena al reiniciar ii. **Si no arranca, vuelve sola a la
  anterior**; y siempre puedes volver a mano desde Configuración → Actualizaciones.

### Nuevo: Configuración
- **Buscador** arriba (Ctrl+F): escribe "barra abajo", "oscuro", "segundero"… y te lleva al ajuste, resaltado.
- **Escritorio → Widgets** es una **galería**: una tarjeta por widget con su interruptor; "Personalizar" abre solo los
  ajustes de ese widget. El **reloj** tiene pestañas (Estilo, Esfera, Manecillas, Fecha, Cita).
- En el **modo edición del escritorio**, cada widget tiene un **engranaje** que abre sus ajustes.
- Páginas nuevas: **Rendimiento** (modo ligero, dibujo, ventanas de otros programas) y **Atajos** (ver abajo). General ahora
  se llama **Sistema**. Las animaciones de ventanas y los fondos animados pasaron a **Apariencia**.
- **Una sola ventana**: Win+I dos veces ya no abre dos.
- Páginas más rápidas: las secciones largas se crean al llegar a ellas; ninguna página tarda más de 150 ms en cambiar.
  Mover un control deslizante ya no hace que toda la interfaz se recargue a cada paso.

### Nuevo: atajos editables
- **Configuración → Atajos:** todos los atajos de ii, con buscador. Los de ii se pueden **cambiar o quitar**; avisa si la
  combinación ya la usa ii, Windows o PowerToys. Ahí también: cuándo ceden los atajos ante juegos, y si ii maneja las
  teclas de volumen y multimedia (antes solo a mano en `shortcuts.ini`).

### Nuevo: Windows
- **Micrófono, cámara y ubicación en uso:** un indicador en la barra, como el de Windows (que ii oculta).
- **Apps que piden atención** (un mensaje, una descarga terminada): su icono rebota en el dock y su punto se enciende.
- **"Windows necesita reiniciar"** para terminar sus actualizaciones: un aviso, y "Actualizar y reiniciar" en el menú de sesión.
- **Poco espacio en el disco:** un aviso (como mucho uno al día) con "Liberar espacio".
- **Ahorro de energía** de Windows en los ajustes rápidos (añádelo en su modo edición).
- **La tienda en el dock** muestra cuántas apps tienen actualización.
- Con **varias pantallas**: barra y dock en todas o solo en la principal (Configuración → Barra / Dock → Pantallas).

### Más liviano
- El seguimiento de ventanas ya no recorre todas las ventanas por cada cambio de título o cada movimiento: **hasta 88 %
  menos CPU** con un navegador abierto y muchas ventanas.
- **Los widgets del escritorio se detienen de verdad cuando una ventana maximizada lo tapa** (antes no se daba cuenta en
  ningún PC: un error al reconocer las pantallas). El reloj con segundos ya no redibuja el fondo detrás del navegador.
- Limpieza automática de cachés y del registro de ii.

### Sin comprobar todavía
- Varias pantallas (solo hubo una a mano).
- Una sesión de 8 horas midiendo la memoria (`tools/dev/soak.ps1`).
- El arranque al iniciar sesión con la versión instalada (objetivo: escritorio usable en menos de 8 s).
- PC con gráfica dedicada y juegos, como en la 0.6.0.
