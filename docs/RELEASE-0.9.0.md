## ii-windows 0.9.0

> Arregla los cierres de ii al ver videos en el navegador, trae las **actualizaciones automáticas** y una Configuración
> nueva, y suma lo que llamamos "el Plus": buscar todo con la tecla Windows, modos, el panel Hoy y que ii siga la
> accesibilidad de Windows. **Es la última versión que hay que instalar a mano**: desde esta, ii avisa de las nuevas y se
> actualiza solo.

**Instalar:** descarga `ii-windows-Setup-0.9.0-….exe`, ábrelo y sigue Siguiente → Acepto → Instalar. Windows avisará de
que el instalador no está firmado (aún no lo está): "Más información → Ejecutar de todas formas". Todo se instala solo
para tu usuario y se puede deshacer (Rescate de ii: Ctrl+Alt+Mayús+R; desinstalar desde Configuración → Aplicaciones).
Se instala encima de la 0.6.0 conservando tu configuración.

### Arreglado: ii se cerraba solo al navegar
- **Ver videos en el navegador (X, Shorts, YouTube) cerraba y reabría ii una y otra vez.** Era la parte de multimedia:
  Windows a veces responde "sin datos" sobre lo que suena y ii lo leía igual. Existía desde la 0.1.3. Probado con miles de
  sesiones de video apareciendo y desapareciendo: ningún cierre (antes, a los 2–3 minutos).
- Si algo vuelve a fallar, ii **guarda un informe** y, si una misma parte falla tres veces, **arranca sin ella** en vez de
  reiniciarse sin fin; a la cuarta, en **modo seguro**. Te avisa con botones: "Ver detalles", "Reportar", "Reactivar todo".
- El inicio automático podía quedar roto al actualizar desde una versión vieja (la tarea antigua tenía el mismo nombre que
  la carpeta nueva).

### Se actualiza solo
- ii busca versiones nuevas cada 6 horas (nunca durante un juego) y avisa: **Actualizar**, **Novedades**, **Más tarde**.
  También un puntito en la barra y **Configuración → Actualizaciones**. Tras actualizar, un aviso con las novedades.
- La descarga se reanuda si se corta, va solo por Wi-Fi o cable y **se comprueba con una firma**. Si la versión nueva no
  arranca, **vuelve sola a la anterior**; también puedes volver a mano.

### Buscar todo, modos y el panel Hoy
- **Tecla Windows:** apps, ventanas abiertas, ajustes de ii y de Windows, acciones ("vaciar la papelera", "modo juego",
  "grabar la pantalla"), cuentas, unidades, monedas y la hora en otras ciudades.
- **Modos** Clase/Trabajo, Juego, Presentación y Noche: cambian No molestar, el tema, la luz nocturna y más, y lo devuelven
  todo al terminar. A mano, por horario, al abrir una app o cuando Windows presenta (PowerPoint). Al terminar uno con No
  molestar, un resumen de los avisos que llegaron.
- **Panel Hoy** (a la izquierda) y **horario de clases** con aviso y botón "Unirme".

### Configuración
- **Buscador** (Ctrl+F) que lleva al ajuste resaltado; **galería de widgets** con un engranaje en el modo edición; páginas
  nuevas **Rendimiento**, **Atajos** (cámbialos o quítalos, con aviso de choques) y **Modos**; una sola ventana; páginas
  más rápidas.

### Más para el día a día
- **Notificaciones:** No molestar con horario, apps que pasan igual y **buscar** en el historial.
- **Según el día:** la imagen del día de Bing o una carpeta tuya que rota; tema claro de día y oscuro de noche (por horario
  o con el sol).
- **Bienestar:** límites diarios por app, descanso de la vista y resumen semanal.
- **Capturas y colores:** fijar una captura encima de todo; el selector de color recuerda los últimos.
- **Portapapeles:** fragmentos guardados, pegar como texto plano y copiar el texto de una imagen.
- **Audio:** batería de los audífonos Bluetooth (aviso bajo el 20 %) y **Win+Mayús+A** silencia el micrófono.
- **Dock:** papelera, número de notificaciones por app, rebote de las apps que piden atención y actualizaciones de la tienda.
- **Ajustes rápidos:** HDR, frecuencia de pantalla (144 ↔ 60 Hz) y ahorro de energía de Windows.
- **Windows:** indicador de micrófono/cámara/ubicación en uso; avisos de "Windows necesita reiniciar" y de poco espacio;
  barra y dock en todas las pantallas o solo en la principal; convive con StartAllBack, PowerToys, Windhawk y otras.

### Accesibilidad
- ii sigue el **tema de contraste**, el **tamaño del texto** y las **animaciones** de Windows. El **Narrador** lee los
  botones, interruptores, dock y notificaciones. Todo se recorre con **Tab** (anillo de foco) y se pulsa con Enter o Espacio.

### Más liviano
- Hasta **88 % menos CPU** siguiendo ventanas con un navegador abierto; los widgets del escritorio **se detienen de verdad**
  cuando una ventana lo tapa; limpieza automática de cachés y del registro de ii.

### Sin comprobar todavía
- Una presentación real de PowerPoint y un tema de contraste de Windows activado (se probaron con señales simuladas).
- Varias pantallas, la revisión a 150 %, una sesión de 8 horas midiendo la memoria y el arranque instalado.
- PC con gráfica dedicada y juegos, como en la 0.6.0.
