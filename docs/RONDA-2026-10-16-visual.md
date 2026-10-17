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
