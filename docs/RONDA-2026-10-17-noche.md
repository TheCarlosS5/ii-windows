# Ronda nocturna (2026-10-17)

Carlos se fue a dormir y pidió trabajo autónomo: probar como usuario, corregir, mejorar, y sobre todo
responder **"¿por qué alguien lo instalaría si en PCs lentos no inicia rápido?"**. Rama `ux/noche-2026-10-17`
(sale de `ux/visual-polish`). Nada se sube a GitHub sin preguntar.

## Bitácora

- 01:05 Estado encontrado: ii **no estaba corriendo** (última sesión terminó con el atajo de pánico el 16/10 21:34).
  Instalada: 0.3.0-20261016-c794259 (verificada).
- Arranque medido en los registros:
  - en caliente (relanzar): cubierta 9,7 s; QML listo ~1,5 s después de lanzar quickshell.
  - **primer inicio de una versión nueva**: el árbol QML copia 980 archivos (1,3 s) y compila (~2,5 s).
  - **al encender el PC (16/10 16:21)**: 28 s hasta "listo". quickshell.exe tardó **10,6 s solo en abrir**
    (cargar Qt desde un disco ocupado por el arranque de Windows), y el host pasó 14 s decodificando el fondo
    (eso ya se arregló en c794259 con `cover-cache.bin`).

## Pendiente (orden)

1. Medir el arranque en frío reproduciendo la caché vacía (copia sin búfer con `robocopy /J`) y ver qué fase pesa.
2. Reducir el trabajo de arranque (DLL, QML que se crea al inicio, servicios que pueden esperar).
3. Recorrido de usuario por todo el entorno: lo que falta / lo que molesta.
4. Ideas de otras shells (Caelestia, Noctalia, DankMaterialShell, HyprPanel): `docs/IDEAS-OTRAS-SHELLS.md`.
