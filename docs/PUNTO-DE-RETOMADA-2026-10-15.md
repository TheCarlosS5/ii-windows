# Punto de retomada (2026-10-15, tarde)

Rama `ux/feedback-round` (repo ii-windows) y rama `windows` del fork `quickshell` (commit de la batería). **No subido a GitHub ni publicado.** Lo hecho está en `docs/RONDA-2026-10-15.md`. En el PC de Carlos corre instalada la 0.3.0 (`5b1d7b3`), con la 0.3.0 `eb3b60a` y la 0.2.0 como vuelta atrás.

## Pedido de Carlos para la siguiente iteración (sin hacer)

1. **Vista general / tecla Windows:** conservar la franja de escritorios de arriba (le gusta tal cual) y el buscador. **Quitar** las ventanas abiertas en grande y la maqueta del escritorio (`OverviewWidget`). Al pulsar Windows debe verse directamente la **rejilla de aplicaciones** (la que hoy sale con el botón "Mostrar aplicaciones", `AppGrid.qml`), no las ventanas. Win+Tab puede seguir mostrando ventanas si se quiere (decidir).
2. **Recomendadas / usadas con frecuencia:** sección encima de la rejilla con las apps más usadas (guardar contador de lanzamientos en `Persistent.states`, p. ej. `launcher.counts`; sumar al lanzar desde buscador, rejilla o dock; mostrar las 6–8 primeras; opción en Ajustes → Paneles para ocultarla o vaciarla).
3. **La tienda anclada al dock** como un icono fijo más (como el de la vista general): entrada especial en `DockApps.qml` (`entries`, como `LAUNCHPAD`) que abre `qs -p <shell>/store.qml`; icono `storefront`; que no cuente como app en ejecución.
4. **"Detalles que ajustar en algunos elementos":** pasar otra vez por capturas cada superficie (dock, vista general, ajustes, tienda, panel derecho/izquierdo, escritorio, recorrido) en escala 1,0 / 1,25 / 1,5 y pulir.
5. **BUG: desbordamiento de la bandeja (iconos de apps en segundo plano)** — al hacer clic en la flecha se abre el popup, pero al bajar el ratón hacia los iconos el popup **se cierra**; al subir vuelve a abrirse. Resultado: no se puede hacer clic derecho en un icono ni fijarlo a la barra. Reproducir, y arreglar para que el popup se mantenga abierto mientras el cursor esté sobre él (o sobre el botón) y se cierre solo al hacer clic fuera / Esc. Mirar `overlay/ii/bar/SysTrayItem.qml`, `build/ii/modules/ii/bar/SysTray.qml` (popup/overflow, hover, `HyprlandFocusGrab`) y la región de entrada del popup en el fork (`quickshell/src/core/region.cpp`, el cierre por "focus grab" y por salir del hover). Probar con ratón real (`tools/dev/mouse.ps1`) y comprobar también clic derecho (menú nativo) y la opción de fijar/ocultar con clic central.

## Archivos clave para esos cambios

- `overlay/ii/modules/ii/overview/Overview.qml` (layout, botón de apps y de tienda, `showApps`), `SearchWidget.qml` (resultados), `AppGrid.qml` (rejilla). El parche `patch_ii_ux2.py` oculta el número gigante del `OverviewWidget`; si se quita el widget del layout, esa edición puede quedarse inofensiva o borrarse.
- `overlay/ii/modules/ii/dock/DockApps.qml` y `DockAppButton.qml` (slot `isLaunchpad`, copiar para la tienda).
- `overlay/ii/modules/ii/store/` y `store.qml`.

## Pendiente de antes (ver también RONDA-2026-10-15.md)

Prueba en portátil real; Gemini con clave real; nombre del entorno; subir rama y publicar 0.3.0 (preguntar antes); Wallpaper Engine; actualizador incremental; atajo propio para la tienda.

## Cómo trabajar

`pwsh tools/dev/redev.ps1 [-Scale 1.5]` (para ii, prepara el QML, comprueba que carga, arranca en el runtime privado; rehacer `make-devrt.ps1` tras compilar C++). Capturas con `tools/dev/screenshot.ps1`, ratón con `mouse.ps1`/`click.ps1`. Parches en `tools/port/patch_ii_ux*.py`, `patch_ii_settings2.py`, `patch_ii_store.py` (escribirlos con la herramienta Write, no con heredocs). Memoria: `ii-windows-ux-round.md`.
