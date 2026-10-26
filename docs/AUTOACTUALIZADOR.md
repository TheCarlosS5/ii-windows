# Pendiente: actualizador automático

Estado: **sin empezar**. Es una implementación grande que se hará más adelante. Hoy, para actualizar, hay que descargar la versión nueva desde GitHub e instalarla encima (el instalador conserva la configuración y deja la versión anterior como respaldo).

## Qué debe hacer

1. **Revisar** de vez en cuando (al arrancar y una vez al día, nunca durante un juego) si hay una versión nueva en las *releases* del repositorio: `https://api.github.com/repos/TheCarlosS5/ii-windows/releases/latest`.
2. **Avisar** con una notificación de ii ("Hay una versión nueva: 0.x.y — Ver novedades / Actualizar / Más tarde"), nunca actualizar sin permiso. Con opción en Configuración: buscar actualizaciones sí/no y canal estable/beta.
3. **Descargar** solo lo necesario: el `.zip` del paquete (no el instalador con asistente), a una carpeta temporal propia, con reanudación si se corta la red.
4. **Verificar** antes de tocar nada:
   - el SHA-256 publicado en la release (hay que empezar a publicarlo: `release-check.md` ya lo calcula);
   - la firma Authenticode de los programas, cuando estén firmados (`docs/PUBLICAR.md`, plan 1.4);
   - el `payload.manifest` del paquete (el instalador ya lo exige).
5. **Instalar** con lo que ya existe: `ii-runtime.ps1` copia la versión a `versions\<id>`, la deja *pendiente* y la activa al siguiente arranque; si no arranca, `ii-launcher` vuelve sola a la anterior. Es decir, la parte delicada (cambio atómico y vuelta atrás) ya está hecha y probada (`test-runtime`, `test-install-flow`).
6. **Reiniciar ii** cuando el usuario quiera (no en medio de su trabajo), y mostrar las novedades después.
7. **Limpiar** las versiones viejas (`Remove-IiOldVersions`, se conservan dos).

## Dónde vive

- La comprobación y la descarga: en `ii-host` (C++, WinHTTP: ya hay `http.cpp`) o en un `ii-update.ps1` lanzado por él. Mejor en `ii-host`: no abre una consola y respeta las reglas de juegos.
- El aviso y el botón: en la shell (notificación de ii y Configuración > Acerca de).
- La instalación: el `install.ps1` del paquete descargado en modo silencioso, o directamente las funciones de `ii-runtime.ps1`.

## Cuidados

- Nunca descargar ni ejecutar nada que no venga de las releases del repositorio oficial y no pase las verificaciones.
- Sin servicios ni permisos de administrador: todo por usuario, como el resto de ii.
- Respetar conexiones medidas (no descargar con datos móviles salvo que el usuario lo pida).
- Si algo falla, quedarse en la versión actual y decirlo; nunca dejar ii a medias.
- Pruebas: un servidor local que simule la API de GitHub (release nueva, hash incorrecto, descarga cortada, versión que no arranca).
