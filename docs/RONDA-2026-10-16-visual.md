# Ronda visual (2026-10-16)

Rama `ux/visual-polish`. Se probó todo el entorno en el PC de Carlos (escala 100 % y 125 % emulada) panel por panel, con capturas.

## Arreglado

- **Vidrio esmerilado** detrás de los paneles translúcidos (`overlay/ii/modules/common/widgets/WallpaperBlur.qml`): Windows no desenfoca lo que hay detrás de una ventana translúcida, así que el fondo y los widgets del escritorio se veían nítidos a través de los paneles y costaba leer. Ahora se dibuja el fondo desenfocado justo donde está el panel (como Mica). Paneles laterales, hoja de atajos, vista general, selector de fondos, teclado en pantalla, tarjeta multimedia y avisos de notificación. Opción: Configuración → Apariencia → "Desenfocar el fondo detrás de los paneles" (`appearance.transparency.blurBehind`).
- **Rejilla de apps empujada hacia abajo** después de usar Win+Tab: el Loader de la vista de ventanas guardaba su altura (~570 px) estando inactivo.
- **Vista de ventanas a 125 %**: su caja pasaba por debajo de los botones de abajo; ahora la escala se limita al espacio libre.
- **Barra**: nombre amigable de la app ("Terminal") en vez del AppUserModelID; una ventana minimizada ya no es "la ventana de este escritorio".
- **Textos en inglés**: "Now/Yesterday" de las notificaciones, días del calendario, fecha del reloj, hoja de atajos completa (descripciones, categorías, teclas `1 … 0`, `← / →`, `F4`, `.`), lugares del selector de fondos (y una línea en vez del botón "---"), tarjeta multimedia vacía (hablaba de MPRIS), etiqueta "Minimizada" en la vista general.
- **Hoja de atajos** tan ancha como sus columnas (hasta 90 % de la pantalla).
- **Configuración**: etiqueta de deslizador cortada ("Volumen de la inte…").
- **Tienda**: íconos sobre una placa clara (GitHub, Epic… eran negros sobre negro), botones alineados aunque no haya papelera, ícono correcto de Firefox.

Parches: `tools/port/patch_ii_visual.py` (último en `stage-ii.ps1`).

## Segunda parte (misma noche): arranque, GPU dedicada, instalación desde cero

- **Pantalla "Bienvenido"** (`host/src/splash.cpp`): Windows quita su propia pantalla de bienvenida en cuanto arranca el Explorador; alargarla de verdad exige cambiar `Winlogon\Shell` (riesgo de pantalla negra al iniciar sesión, imposible de probar sin cerrar sesión). En su lugar, ii-host pone **una igual**: la misma imagen que usa Windows detrás de su inicio de sesión (`ii-shim lockscreen-image`: Destacado, la imagen propia de bloqueo o la predeterminada), desenfocada y oscurecida, con la foto de la cuenta, el nombre, los puntitos y "Bienvenido". Aparece 15 ms después de que arranca ii-host (antes 1,4 s), queda **por encima de todo** (40 s máx., 70 s la primera vez) y se va de una vez cuando ii escribe `%LOCALAPPDATA%\ii-windows\shell-visual-ready` (barra, dock, widgets e iconos listos). La imagen sale de una copia pequeña desenfocada guardada (`cover-cache.bin`): el arranque del 16/10 a las 16:21 pasó 14 s congelado decodificando el fondo en el hilo principal.
- **Ping asíncrono** al shell: la espera bloqueante de 250 ms por vuelta congelaba el hilo del host (y la animación) mientras ii cargaba.
- **GPU dedicada**: el instalador forzaba "ahorro de energía" en todos los equipos; en un PC con tarjeta dedicada y la integrada activa, ii dibujaba en la integrada (sin pantalla) y Windows copiaba cada cuadro: fondo que se pausa, colores que tardan. Ahora `ii-host --gpu-policy` (DXGI) solo lo permite cuando la GPU de ahorro maneja la pantalla; si no, no se fuerza y se borra el valor que puso una versión anterior. Las GPU quedan en `host.log` al arrancar. **No se pudo probar con una tarjeta dedicada real.**
- **Vidrio esmerilado sin shaders**: `ii-shim blurwall` + `services/BlurredWallpaper.qml`; los paneles dibujan una imagen ya desenfocada (igual en cualquier GPU). Se apaga en Configuración → Apariencia → "Desenfocar el fondo detrás de los paneles".
- **Instalación desde cero** (Sandbox, `tools/sandbox/tests/fresh-ui.ps1` y `test-install.ps1` actualizado: 0 fallos):
  - el recorrido esperaba 7 s fijos y salía encima de la ventana "¡Hola! Primero lo primero…": ahora espera a que se cierre;
  - el selector de fondos mostraba las carpetas internas de ii porque `Imágenes\Wallpapers` no existía: se crea, con el fondo de ii dentro;
  - aviso "Empty desktops…" en inglés en el primer arranque: ya no sale en instalaciones nuevas;
  - Windows Terminal fijado en el dock aunque no esté instalado (ícono vacío): se omite;
  - la barra decía "quickshell" en las ventanas de ii; el widget de carpeta decía "Downloads".
