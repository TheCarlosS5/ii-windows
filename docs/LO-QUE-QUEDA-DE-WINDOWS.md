# Lo que todavía se ve de Windows (plan 2.3)

Inventario del 24 de octubre de 2026. Regla de siempre: solo se reemplaza lo que se puede hacer **por usuario, sin
inyectar nada en Explorer ni en otros procesos y de forma reversible** (con copia y restauración en la salida, el atajo
de pánico, el guardián, `ii-rescue` y el desinstalador). Lo que no cumple eso queda de Windows y se explica aquí.

| Elemento de Windows | Estado | Cómo / por qué |
| --- | --- | --- |
| Barra de tareas | ✅ Reemplazada | Oculta mientras ii corre; vuelve sola si ii falla (latido, D23). |
| Iconos del escritorio | ✅ Reemplazados | Escritorio propio de ii (D15, D20). |
| Menú Inicio (Win, Ctrl+Esc) | ✅ Reemplazado | Búsqueda/cuadrícula de ii. Con un juego al frente, o si ii no puede mostrarse, se abre el de Windows (nunca se pierde la tecla). |
| Búsqueda (Win+S) | ✅ Reemplazada | Búsqueda de ii. |
| Configuración rápida (Win+A) | ✅ Reemplazada | Barra lateral de ii. |
| Centro de notificaciones (Win+N) | ✅ Reemplazado | Barra lateral derecha de ii. |
| Avisos (toasts) de las apps | ✅ Reemplazados | ii los lee y apaga los banners de Windows por app mientras su lector funciona (D12, R01). |
| Widgets (Win+W) | ✅ Reemplazados | Barra lateral izquierda de ii. |
| Menú Win+X | ✅ Reemplazado | Menú de sesión de ii. Las herramientas del sistema de ese menú siguen en Configuración. |
| Aviso de volumen | ✅ Reemplazado | ii toma las teclas de volumen y muestra el suyo (`shortcuts.ini [audio] volumekeys=windows` lo devuelve). |
| Captura (Impr Pant, Win+Shift+S) | ✅ Reemplazada | Selector de región de ii. |
| Animación de minimizar | ✅ Reemplazada | Hacia el dock, de ii (2.2). La de Windows se apaga solo en memoria; es el mismo ajuste que sus animaciones de maximizar y restaurar, que también se apagan. Restaurar no tiene animación de ii (la ventana real vuelve al instante y una copia encima se veía doble). |
| Aviso de Bloq Mayús / cargador | ✅ Propio | Píldora de ii (1.5). |
| Vista de tareas (Win+Tab) | ✅ Reemplazada | Vista general de ii. |
| Alt+Tab | ✅ Reemplazado | El selector de ii: mantener Alt, Tab avanza (Mayús+Tab o ← retrocede), soltar elige, Esc cancela; miniaturas en vivo en orden de uso, y el dock visible mientras tanto. Encima de un juego que hace ceder los atajos, o si la shell no responde, sigue siendo el de Windows. Ctrl+Alt+Tab es de Windows. |
| Aviso de brillo (portátiles) | ⛔ Se queda | Las teclas de brillo las procesa el firmware/driver y Windows muestra su aviso. No hay forma documentada y por usuario de apagarlo sin tocar el sistema. |
| Aviso multimedia (play/pausa) | 🟡 Opcional | Con `shortcuts.ini [audio] mediakeys=ii`, ii toma play/pausa, siguiente y anterior, los manda a su reproductor activo y su píldora dice qué suena (sin el aviso de Windows). Por defecto siguen siendo de Windows: con varios reproductores, o uno que no se anuncia a Windows, su manejo es más fiable. Con un juego al frente siempre son de Windows. |
| Proyectar (Win+P) | ⛔ Se queda | Es una función del sistema (pantallas y proyectores); no hay nada de ii que la iguale. |
| Game Bar (Win+G) | ⛔ Se queda | Útil para grabar en juegos; ii no la sustituye. |
| Pantalla de bloqueo (Win+L) | ⛔ Se queda | La única segura es la de Windows (R03). |
| Ctrl+Alt+Supr, Ctrl+Mayús+Esc | ⛔ Se quedan | No llegan a ningún programa / Administrador de tareas. |
| Explorador de archivos (Win+E) | ⛔ Se queda | Es una aplicación, no parte de la shell. |
| Accesibilidad (Win+U, Win+H, Narrador…) | ⛔ Se quedan | Funciones del sistema que no conviene interceptar. |
