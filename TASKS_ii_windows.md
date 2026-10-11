# TASKS — ii-windows: corrección, rendimiento e interfaz propia

**Destinatario:** agente que vaya a trabajar en ii-windows y su fork de Quickshell.  
**Solicitante:** Carlos.  
**Documento preparado:** 10 de octubre de 2026.  
**Base:** auditoría de código del 9 de octubre de 2026; análisis continuado el 10 en UTC.  
**Estado de este documento:** especificación de trabajo; ninguna tarea aquí descrita se ha implementado por redactarlo.

## 1. Mandato y resultado esperado

Implementar por fases una experiencia ii rápida, fluida, recuperable y coherente sobre Windows. Priorizar los fallos que pueden dejar el escritorio oculto, perder avisos, informar un bloqueo inexistente o eliminar datos ajenos. Después eliminar trabajo innecesario del hilo de interfaz, mejorar arranque y reposo, cerrar rutas habituales hacia la UI de Windows e integrar Wallpaper Engine/Lively. Cambiar el logo textual de Fastfetch por una identidad «ii» comprensible.

El usuario quiere que los atajos, paneles, menús, selectores y operaciones habituales del entorno se resuelvan dentro de ii. No basta con cambiar iconos, esconder botones, bloquear combinaciones sin una acción útil o sustituir una dependencia Linux por un comando que siempre devuelve éxito.

**Límite del producto que debe conservarse en la implementación:** ii sigue funcionando sobre Windows, DWM, Explorer y Winlogon. No se promete una pantalla de autenticación segura QML, interceptar Ctrl+Alt+Supr, reemplazar todos los menús de aplicaciones ajenas ni suprimir universalmente OSD de fabricantes. La solución de bloqueo de este plan es autenticación real de Windows, estado WTS correcto, transiciones ii e imagen estática sincronizada cuando el sistema lo permita.

Este archivo especifica qué debe hacer un agente al recibir el encargo de implementar. Su creación no autoriza ahora cambios en los repositorios. Durante una futura ejecución, preparar código, pruebas y paquetes de revisión; publicar releases, subir cambios a terceros, consumir servicios de pago o modificar la sesión personal del usuario requiere el alcance correspondiente en esa sesión.

### 1.1 Alcance esencial y ampliaciones

- **CORE:** correcciones y trabajo directamente ligado a fiabilidad, optimización, identidad ii, Wallpaper Engine/Lively y Fastfetch. Ejecutar en el orden de dependencias.
- **PARIDAD:** funcionalidades concretas recomendadas para completar rutas presentes o prestaciones del original. Desarrollar después de estabilizar CORE; no retrasar un paquete correctivo P0 para meter un grabador completo.
- **IDEA:** ampliaciones propuestas a partir de otros entornos. Mantener como backlog, sin instalarlas ni habilitarlas todas por el hecho de aparecer aquí.
- **VALIDACIÓN:** instrumentación, pruebas de integración y cierre. Necesarias para acreditar las tareas que correspondan al alcance ejecutado.

Prioridades: **P0** antes de confiar en la base; **P1** siguiente iteración de estabilidad/rendimiento/coherencia; **P2** completar integración/paridad; **P3** ampliaciones. Prioridad y fase son distintas: una tarea de instrumentación puede preceder a un P0 aunque no arregle por sí misma un fallo.

Los nombres de servicios, claves de configuración, mensajes IPC, presets y documentos nuevos que propone este archivo son **diseños por crear**, no afirmaciones de que ya existan. El agente debe adaptar nombres a las convenciones reales, registrar su decisión y conservar los contratos públicos de QML que sigan teniendo consumidores.

## 2. Base de código y reglas para comenzar

| Árbol | Revisión auditada | Función |
| --- | --- | --- |
| `TheCarlosS5/ii-windows` | `22dec5487e8482aeb5f150880e2ea24c5014ed1b` | Host, shims, overlay, staging, instalación y pruebas |
| `TheCarlosS5/quickshell-windows` | `39428f7c5fb0fd38f56601ed10f1aa93aa8950c0` | Motor Qt/QML y backends Windows |
| `end-4/dots-hyprland` | `33f31a08caddd41422a2d97670adeeb52b4f1e7c` | Upstream fijado para construir ii |
| Release consultada | `v0.1.3`, publicada el 9 de octubre de 2026 | ZIP no ejecutado en la auditoría |

Las referencias anteriores son evidencia histórica, no una orden de volver HEAD hacia atrás. Antes de editar, comparar el checkout actual con ellas y reclasificar hallazgos ya resueltos. No hacer `reset --hard`, borrar cambios del usuario ni revertir mejoras posteriores para reproducir el informe.

En esta revisión los árboles temporales están en `/workspace/scratch/ec8b47dad74e/ii-windows`, `/workspace/scratch/ec8b47dad74e/quickshell`, `/workspace/scratch/ec8b47dad74e/upstream` y `/workspace/scratch/ec8b47dad74e/audit-staged`. Son ubicaciones de la revisión, no rutas que deban codificarse en el producto. El agente siguiente debe descubrir sus checkouts y rutas Windows reales.

Convenciones de rutas en las fichas:

- **ii:** ruta relativa a ii-windows.
- **qs:** ruta relativa al fork quickshell-windows.
- **up:** ruta relativa a `dots/.config/quickshell/ii` del upstream.
- **nuevo:** archivo/servicio sugerido, cuya ubicación exacta se decide al ejecutar la tarea.

El QML ejecutable se obtiene de **upstream intacto + overlay + parches de staging**. Revisar `tools/dev/stage-ii.ps1` y su orden vigente. La auditoría ejecutó los 12 parches Python de la ruta normal con éxito en una copia temporal. Para enviar una corrección, editar el overlay o el parche responsable, no solo `build/ii` ni esta copia auditada. Los parches deben fallar de manera visible si deja de coincidir la base esperada; regenerar desde cero debe reproducir el resultado.

### 2.1 Trabajo existente que debe preservarse

Ya hay caché QML con archivos reales y timestamps conservados; scanner de rutas corregido; paletas Material Color Utilities nativas; tamaño de decodificación del wallpaper relacionado con pantalla/DPR; índice inicial de apps/iconos en worker; pausa de varias animaciones al cubrir escritorio; eventos de cursor con respaldo de 250 ms; retención temporal de popups; hook de teclado en hilo separado; guardián, job, watchdog y rescate; suspensión crítica propia desactivada por defecto; transporte IA POST/streaming y listado de chats/prompts nativos; DPAPI para claves de IA; traducción de texto, cuentagotas, portapapeles y emojis; movimiento de ventanas/escritorios mediante COM interno; dos perfiles de Windows Terminal/Fastfetch; escritura atómica `QSaveFile` por defecto en FileView.

No presentar estos elementos como ausentes ni sustituirlos sin un beneficio medido. No cambiar automáticamente al render loop threaded, desactivar VSync, forzar WARP/software, borrar cachés en cada inicio, añadir sondeo de 16 ms ni subir todos los procesos a prioridad alta para obtener una aparente mejora.

La auditoría fue estática y en Linux. No hay mediciones nuevas de Windows, FPS o batería. Los 114 archivos de tests encontrados no acreditan que 114 tests pasaran. Tampoco se demostró que el ZIP publicado fuera Debug o que su consumo actual fuera el histórico de PROGRESS.md.

## 3. Contratos comunes que guían todas las tareas

### 3.1 Capacidad, estado, error y fallback

Crear un catálogo central para acciones de entorno. Cada acción debe describir su identificador estable, texto traducible, destino ii, soporte real, razón si no está disponible, coste/activación del servicio, atajos y fallback permitido. Evitar que tiles, launcher, menú, IPC y teclado tengan implementaciones divergentes.

Como contrato propuesto, diferenciar `unsupported`, `permission-required`, `available`, `busy`, `degraded` y `error`. Separar de ese estado la salud del proceso, datos disponibles y confirmación de una operación. Un array vacío no significa «no hay hardware», y un HRESULT/exit code fallido no significa éxito porque la UI haya cambiado de color.

Los mensajes de host↔shell deberán incorporar versión de protocolo, instancia/sesión destinataria e identificador de solicitud. Validar tamaño, tipos, origen/alcance local y respuestas tardías. Un heartbeat acredita vida, no primer frame ni servicio listo. El handshake de notificaciones acredita ese listener concreto, no la shell completa. Añadir plazos y cancelación sin bucles ilimitados.

**Política de UI propuesta por defecto:** las acciones habituales abren ii; si el equivalente no existe, se muestra una explicación dentro de ii. Una acción avanzada puede ofrecer un botón explícito para abrir el componente del sistema, identificándolo como tal. No abrirlo automáticamente al fallar. Excepciones: autenticación/consentimiento protegidos y restauración del escritorio tras fallo del reemplazo. Estas excepciones deben documentarse y observarse; no ocultar avisos o dejar al usuario atrapado para aparentar aislamiento.

### 3.2 Hilos, eventos y recursos

No ejecutar enumeración pesada, Shell thumbnail extraction, HTTP, disco lento o llamadas COM potencialmente bloqueantes en el hilo QML/GUI. Moverlas a workers con apartamento COM correcto, resultados inmutables o modelos actualizados mediante señales queued, cancelación y shutdown verificable. No usar QPixmap como objeto de trabajo indiscriminadamente fuera del hilo GUI; preferir QImage y el proveedor asíncrono adecuado.

Aplicar deltas, coalescer ráfagas y conservar sondeos lentos de reconciliación donde sean necesarios. Reemplazar un timer por un callback que hace el mismo escaneo pesado no cumple. Evitar señales de «todo cambió» si solo cambió foco o un rectángulo. Cada servicio debe declarar quién lo consume, cuándo se activa y cómo libera handles, timers, buffers y suscripciones.

Cargas y peticiones deben tener límites de concurrencia, bytes, tiempo, cola y retención. Los valores se ajustan con la línea base; los defaults del documento son propuestas, no garantías universales. Cambiar estado de batería/cobertura/bloqueo afecta solo recursos visuales opcionales, sin detener una grabación solicitada solo por ocultar su UI ni audio real de otra aplicación; bloqueo/pérdida de fuente siguen la política explícita del grabador.

### 3.3 Configuración, compatibilidad y datos

Versionar el esquema y migrar de forma determinista con backup recuperable. Mantener escritura atómica, guardar última configuración válida como mejora separada y no borrar la inválida sin copia. Importaciones deben validar tipos, rangos, rutas, extensiones y conflictos. Las preferencias viejas no deben reactivar rutas Linux o controles supuestamente deshabilitados.

Registrar la propiedad de cambios externos: valor original, valor aplicado, usuario/sesión/instalación y estado de restauración. Restaurar solo si sigue siendo el cambio propio o si la política acordada lo permite. No pisar una elección posterior del usuario. No borrar fuera de directorios propios, aunque un manifest esté corrupto o contenga una ruta externa.

Secretos en almacén por usuario/DPAPI, sin incluirlos en exportaciones, argumentos, logs ni reportes. DPAPI no vuelve inocuo un log con el contenido de un chat o notificación. Peticiones con texto/imágenes salen a un proveedor solo por una acción explícita, con destino claro.

### 3.4 Qué debe entregar el agente en cada tarea

1. Reproducción o confirmación del hallazgo en HEAD actual; si ya se resolvió, evidencia y estado `YA_RESUELTA`.
2. Cambio mínimo que satisface el comportamiento descrito, con ruta persistente de staging cuando afecta QML.
3. Pruebas pertinentes, al menos una negativa cuando el fallo lo requiera. No escribir tests que solo repitan la implementación ni declarar todos los casos Windows pasados por compilar.
4. Evidencia antes/después: versiones, equipo, escenario, salida y métricas si corresponde; rutas a logs/trazas/capturas sin secretos.
5. Impacto sobre ambos repositorios, configuración, migración y rollback; documentación de capacidades/límites.
6. Commit(s) revisables por unidad de trabajo y registro de pendientes. No publicar ni fusionar sin el alcance de la sesión.

Estados sugeridos para el seguimiento: `TODO` → `EN_CURSO` → `IMPLEMENTADA_SIN_VALIDAR_WINDOWS` o `VERIFICADA`. Además `BLOQUEADA`, `YA_RESUELTA` y `DESCARTADA_CON_MOTIVO`. Escribir el motivo y evidencia de todos los estados excepcionales. Nunca marcar `VERIFICADA` si falta hardware/proveedor/API real necesario. La ausencia de ese hardware no impide continuar con tareas independientes.

## 4. Secuencia de ejecución y puertas de fase

| Fase | Objetivo | Puerta para cerrar |
| --- | --- | --- |
| 0 | Confirmar base, arreglar runner y obtener línea base | Builds/staging identificables; el runner falla de verdad ante errores; evidencia inicial reproducible |
| 1 | Recuperación, datos y estados críticos | R01–R04 verificados; rescate y pruebas negativas no dejan escritorio oculto ni borran datos ajenos |
| 2 | Propiedad, sesión y seguridad de mantenimiento | R05–R11 verificados en el alcance soportado; rollback/compatibilidad/secretos documentados |
| 3 | Arranque, reposo y fluidez | Optimizaciones comprobadas frente a línea base, sin pérdida de entrada ni regresiones visuales |
| 4 | Identidad ii y accesibilidad | Catálogo, atajos y flujos esenciales propios; ninguna apertura Windows automática fuera de excepciones documentadas |
| 5 | Fondos externos y Fastfetch | Etapas A–C del proveedor según capacidades reales; logo legible y wrapper respetando configuración |
| 6 | Completar paridad | Funciones seleccionadas terminadas extremo a extremo; las no elegidas siguen explícitamente pendientes |
| 7 | Empaquetado y cierre | Pareja de commits, matriz de resultados, límites y rollback; sin afirmaciones de validación inventadas |
| 8 | Ideas de producto | Solo tras selección de alcance; no es requisito para cerrar un paquete correctivo |

**Primer bloque de trabajo concreto:** B00 → B01 → B02, después R02/R03/R04/R01. Instrumentar sin esperar a todas las ampliaciones. R01 necesita un contrato de salud compartido con host; no necesita esperar al catálogo visual completo. Las dependencias de las fichas son prerrequisitos mínimos, no una excusa para omitir las puertas de fase. Dentro de una fase, resolver primero los errores P0 y los cambios que habilitan los demás. Si una dependencia ya tiene contrato e implementación y solo falta su prueba física, se puede preparar el código dependiente y dejar ambas verificaciones pendientes. Eso no cierra la fase ni permite afirmar que pasó la integración. Una dependencia técnicamente no resuelta sí bloquea los cambios que necesitan su contrato.

Puede entregarse un paquete correctivo al cerrar fases 1–2 con Q01/Q03 aplicados a ese alcance. No anunciar cumplimiento completo de este documento si PARIDAD o IDEA siguen sin ejecutar. Si falta Windows, entregar implementación y lista exacta de validación pendiente; no certificar una release de rendimiento ni bloquear trabajo independiente por fingir que toda tarea necesita el mismo hardware.

## 5. Índice de tareas

Todas las casillas están pendientes a fecha de redacción. No son resultados de ejecución.

| Estado | ID | Tarea | Fase | Prioridad | Alcance | Dependencias mínimas |
| --- | --- | --- | --- | --- | --- | --- |
| [x] VERIFICADA | B00 | Confirmar HEAD, arquitectura y mapa de reproducción | 0 | P0 | VALIDACIÓN | — |
| [x] VERIFICADA | B01 | Hacer fiable el runner de pruebas | 0 | P0 | VALIDACIÓN | B00 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | B02 | Instrumentar arranque, frames y consumo antes de optimizar | 0 | P1 | VALIDACIÓN | B01 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R01 | Coordinar permisos y salud antes de ocultar notificaciones | 1 | P0 | CORE | B02 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R02 | Lanzar y activar la shell como operación recuperable | 1 | P0 | CORE | B02 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R03 | Corregir el contrato de bloqueo solicitado y confirmado | 1 | P0 | CORE | B02 |
| [x] VERIFICADA | R04 | Limitar desinstalación a datos propiedad de ii | 1 | P0 | CORE | B01 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R05 | Rescatar solo los procesos de la instancia supervisada | 2 | P1 | CORE | R02 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R06 | Hacer autostart independiente por usuario y dueño | 2 | P1 | CORE | R04 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R07 | Instalar y actualizar runtime con activación y rollback | 2 | P1 | CORE | R02, R04 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R08 | Preservar propiedad y decisiones del usuario entre upgrades | 2 | P1 | CORE | R04, R07 |
| [ ] TODO | R09 | Endurecer escritorios privados y limpieza automática | 2 | P1 | CORE | B02 |
| [ ] TODO | R10 | Convertir pruebas existentes en regresiones con assertions | 2 | P1 | VALIDACIÓN | B01, R01, R02, R03, R04 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | R11 | Unificar secretos y limpiar temporales/datos sensibles | 2 | P1 | CORE | B01 |
| [ ] TODO | P01 | Investigar render loop sin perder repintado o entrada | 3 | P1 | CORE | B02, R02 |
| [ ] TODO | P02 | Actualizar miniaturas DWM solo cuando cambian propiedades | 3 | P1 | CORE | B02 |
| [ ] TODO | P03 | Acotar decodificación de fotos y pausar GIF realmente ocultos | 3 | P1 | CORE | B02 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | P04 | Eliminar animación decorativa perpetua del placeholder media | 3 | P1 | CORE | B02 |
| [ ] TODO | P05 | Compartir espectro, estado media y captura de audio | 3 | P1 | CORE | B02 |
| [ ] TODO | P06 | Cargar paneles y pestañas bajo demanda con retención acotada | 3 | P1 | CORE | B02 |
| [ ] TODO | P07 | Actualizar ventanas/escritorios con deltas y cobertura por monitor | 3 | P1 | CORE | B02, R09 |
| [ ] TODO | P08 | Sacar thumbnails e iconos Shell lentos del hilo GUI | 3 | P1 | CORE | B02 |
| [ ] TODO | P09 | Sustituir cachés sin límites/clear-all por presupuestos LRU | 3 | P1 | CORE | P08 |
| [ ] TODO | P10 | Convertir audio/red/Bluetooth en servicios asíncronos y por eventos | 3 | P1 | CORE | B02 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | P11 | Basar temporizadores en tiempo real y limitar refresh visual | 3 | P1 | CORE | B02 |
| [~] EN_CURSO | P12 | Sustituir sondeo redundante y mantener hook barato | 3 | P1 | CORE | B02 |
| [ ] TODO | P13 | Optimizar búsqueda y descartar resultados viejos | 3 | P1 | CORE | B02 |
| [ ] TODO | P14 | Reducir FBO y hacer texto nítido en escalado/DPI | 3 | P1 | CORE | B02 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | P15 | Hacer splash barato y retirarlo por readiness real | 3 | P1 | CORE | R02, B02 |
| [ ] TODO | P16 | Aplicar prioridad y perfiles por estado, sin trucos globales | 3 | P1 | CORE | R02, B02, R08 |
| [~] EN_CURSO | P17 | Conservar caché QML y hacer reproducibles builds Windows Release | 3 | P1 | CORE | B00, B01 |
| [ ] TODO | P18 | Aplicar presupuestos de reposo y demostrar fluidez sostenida | 3 | P1 | VALIDACIÓN | B02, P02, P03, P04, P05, P06, P07, P08, P09, P10, P11, P12, P13, P14, P15, P16, P17 |
| [~] EN_CURSO | U01 | Crear catálogo de acciones/capacidades y política de UI ii | 4 | P1 | CORE | R01, R02, R03 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | U02 | Enrutar atajos completos con política por aplicación | 4 | P1 | CORE | U01, P12, R09 |
| [ ] TODO | U03 | Añadir selector Alt+Tab ii rápido y navegable | 4 | P2 | CORE | U02, P02, P07 |
| [ ] TODO | U04 | Implementar selectores, color y operaciones de archivo propios | 4 | P2 | CORE | U01, P08, P09, R04 |
| [ ] TODO | U05 | Sustituir tiles de sistema con controles y límites reales | 4 | P1 | CORE | U01, P10 |
| [ ] TODO | U06 | Controlar menús propios y recuperación sin mensajes ambiguos | 4 | P1 | CORE | U01, R02, R05 |
| [ ] TODO | U07 | Mantener accesibilidad en todas las superficies reemplazadas | 4 | P1 | CORE | U01 |
| [ ] TODO | U08 | Sincronizar estética de bloqueo hasta el límite soportado | 4 | P2 | CORE | R03, R08, U01 |
| [ ] TODO | U09 | Completar notificaciones, OSD y entradas fuera del teclado | 4 | P2 | CORE | R01, U01, U02, P10 |
| [~] IMPLEMENTADA_SIN_VALIDAR_WINDOWS | C12 | Corregir pin, idiomas y rutas Linux residuales vivas | 4 | P1 | CORE | U01, B00 |
| [ ] TODO | D01 | Versionar configuración, last-good y export/import portable | 4 | P1 | CORE | U01, R04, R08 |
| [ ] TODO | W01 | Etapa A: coexistencia de fondo externo y capas ii | 5 | P1 | CORE | R02, U01, P07 |
| [ ] TODO | W02 | Etapa B: detectar proveedores y seleccionar proyectos desde ii | 5 | P2 | CORE | W01, P08, P09, U04 |
| [ ] TODO | W03 | Etapa C: paletas, pausa, batería, audio y snapshot lock | 5 | P2 | CORE | W02, P05, P16, R08, R03 |
| [ ] TODO | W04 | Etapa D: playlists/propiedades y recuperación del proveedor | 5 | P2 | PARIDAD | W03, R07 |
| [x] VERIFICADA | F01 | Cambiar logo Fastfetch y dejar de imponerlo desde el wrapper | 5 | P2 | CORE | B00 |
| [ ] TODO | C01 | Completar captura de pantalla y anotación dentro de ii | 6 | P2 | PARIDAD | U01, U04, P08 |
| [ ] TODO | C02 | Implementar fuente screen para OCR/traducción sin confundir DWM | 6 | P2 | PARIDAD | C01, R03 |
| [ ] TODO | C03 | Grabar video y audio con un backend Windows completo | 6 | P2 | PARIDAD | C02, P16, U04 |
| [ ] TODO | C04 | Completar búsqueda por imagen y traducción de pantalla | 6 | P2 | PARIDAD | C02, R11, U01 |
| [ ] TODO | C05 | Completar comandos Windows y calculadora avanzada del launcher | 6 | P2 | PARIDAD | P13, U01 |
| [ ] TODO | C06 | Añadir búsqueda de archivos/ventanas indexada y a demanda | 6 | P2 | PARIDAD | P13, U04, P08 |
| [ ] TODO | C07 | Validar IA existente, streaming y herramientas Windows | 6 | P2 | PARIDAD | R11, P06, U01 |
| [ ] TODO | C08 | Añadir adjuntos y render de chat sin trabajo innecesario | 6 | P2 | PARIDAD | C07, U04, P09 |
| [ ] TODO | C09 | Conservar widgets/iconos por monitor y normalizar telemetría | 6 | P2 | PARIDAD | P03, P07, P14, R08 |
| [ ] TODO | C10 | Completar overview/dock con teclado y snapshots minimizados | 6 | P2 | PARIDAD | P02, P07, U03, R09 |
| [ ] TODO | C11 | Acotar galería/clima/red y preservar uso offline | 6 | P2 | PARIDAD | R11, P06, P09, U01 |
| [ ] TODO | C13 | Implementar inactividad/energía/actualizaciones con estados reales | 6 | P2 | PARIDAD | R03, P10, P11, U05 |
| [ ] TODO | Q01 | Preparar paquete identificable y documentación veraz | 7 | P1 | VALIDACIÓN | R07, R08, P17, D01 |
| [ ] TODO | Q02 | Ejecutar matriz integral y recuperación de largo plazo | 7 | P1 | VALIDACIÓN | R10, P18, U02, W03, F01 |
| [ ] TODO | Q03 | Cerrar el trabajo con evidencia y pendientes accionables | 7 | P1 | VALIDACIÓN | Q01, Q02 |
| [ ] TODO | X01 | Integración opcional de tiling, zonas y scratchpad | 8 | P3 | IDEA | U02, P07, R09 |
| [ ] TODO | X02 | Centro de archivos ii completo a partir del picker | 8 | P3 | IDEA | U04, C06 |
| [ ] TODO | X03 | Centro de procesos ii para acciones cotidianas | 8 | P3 | IDEA | U01, P10 |
| [ ] TODO | X04 | Dashboard, escenas y packs con identidad Material ii | 8 | P3 | IDEA | P06, P16, U07, W03 |
| [ ] TODO | X05 | Calendario conectado opcional e ICS offline | 8 | P3 | IDEA | P11, R11, P06 |
| [ ] TODO | X06 | API de extensiones con capacidades y presupuesto | 8 | P3 | IDEA | U01, P06, P09, R11 |
| [ ] TODO | X07 | Instalador/actualizador gráfico con rollback reutilizado | 8 | P3 | IDEA | R07, R08, P17, U07 |
| [ ] TODO | X08 | Reconocimiento de canciones y letras optativos | 8 | P3 | IDEA | P05, R11, U01 |
| [ ] TODO | X09 | Regiones asistidas, zoom y herramientas de captura | 8 | P3 | IDEA | C01, C02, U07 |
| [ ] TODO | X10 | Integraciones opcionales de teléfono, VPN y perfiles de audio | 8 | P3 | IDEA | U01, R11, P10 |

## 6. Especificaciones de las tareas

Las rutas iniciales son puntos de inspección: verificar HEAD antes de editar. Las pruebas enumeradas describen criterios de verificación; ejecutar las pertinentes al cambio y registrar las que requieran equipo/proveedor ausente.


### Fase 0: Base y medición


#### B00 — Confirmar HEAD, arquitectura y mapa de reproducción

**Estado inicial:** TODO. **Prioridad:** P0. **Alcance:** VALIDACIÓN. **Dependencias:** ninguna.

**Fuentes y archivos iniciales:** ii: README.md, PROGRESS.md, docs/DECISIONS.md, docs/INVENTARIO-WINDOWS.md, tools/dev/stage-ii.ps1; qs: BUILD.md, CMakeLists.txt.

**Problema o finalidad:** El informe describe una pareja fija de commits y el inventario contiene estados antiguos. Empezar desde esas conclusiones sin mirar HEAD puede rehacer funciones o reintroducir fallos.

**Implementación requerida:**

Descubrir checkouts y AGENTS.md aplicables; registrar HEAD, dirty state, submódulos/dependencias y diff desde las revisiones auditadas. Crear rama/worktree aislado conservando cambios existentes. Reconstruir QML efectivo desde la receta actual y mapear cada ficha al archivo que realmente produce su conducta. Clasificar rutas Linux residuales por consumidor vivo, compatibilidad válida o código muerto; no eliminar por nombre.
Crear registro de seguimiento nuevo con IDs de este documento, estado, evidencia, commits de ambos repositorios y dependencia pendiente. Registrar las decisiones propuestas adoptadas, sin presentarlas como preferencias ya aprobadas por Carlos.

**Criterios de aceptación:**

- Base y pareja de repos identificables; upstream no modificado.
- Cada hallazgo elegido tiene ubicación actual y se sabe si sigue vigente.
- Staging limpio reproduce el árbol QML; una base incompatible falla con diagnóstico del parche responsable.

**Pruebas y evidencia:**

Verificar git status/diff antes y después; ejecutar staging en destino temporal sin tocar el runtime del usuario. Introducir en una copia un patrón upstream incompatible y comprobar error inequívoco. Entregar manifest de la reproducción, no solo una captura del árbol.


#### B01 — Hacer fiable el runner de pruebas

**Estado inicial:** TODO. **Prioridad:** P0. **Alcance:** VALIDACIÓN. **Dependencias:** B00.

**Fuentes y archivos iniciales:** ii: tools/sandbox/sbx.ps1, tools/sandbox/tests; relación directa con R10.

**Problema o finalidad:** Una prueba puede fallar o agotar plazo y el driver finalizar aparentemente bien. Primero hay que hacer creíble la evidencia futura.

**Implementación requerida:**

Definir resultado por prueba con nombre, inicio/fin, exit code, timeout, assertions y ruta de salida. Propagar fallos de PowerShell y de procesos nativos; distinguir excepciones, salida no cero y timeout. Timeout debe terminar solo el árbol de la prueba y devolver resultado fallido, no hacer break y acabar en cero. El agregador debe salir no cero si cualquier prueba falla; no interpretar una cadena PASS aislada como criterio.
Conservar compatibilidad razonable con scripts existentes y añadir fixtures mínimos de fallo controlado, excepción y proceso colgado.

**Criterios de aceptación:**

- Un test negativo provoca fallo verificable del runner y del agregador.
- Un timeout libera sus recursos y conserva su salida para diagnóstico.
- El resultado exitoso pertenece a la ejecución actual, sin reutilizar logs de otra corrida.

**Pruebas y evidencia:**

Ejecutar fixture éxito, exit 7, throw, assertion fallida y timeout; comprobar códigos desde un proceso padre. Documentar cómo ejecutar un test individual y suite. Estas fixtures acreditan el driver, no los módulos de ii.


#### B02 — Instrumentar arranque, frames y consumo antes de optimizar

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** VALIDACIÓN. **Dependencias:** B01.

**Fuentes y archivos iniciales:** ii: host/src/main.cpp, splash.cpp, herramientas sandbox/report; qs: init/render y servicios; nuevo: manifest de benchmark.

**Problema o finalidad:** No existen mediciones Windows nuevas en la auditoría. Sin línea base no puede afirmarse que una refactorización haga más fluida la interfaz.

**Implementación requerida:**

Medir con reloj monotónico: lanzamiento host, proceso shell, QML listo, primer frame útil por monitor y disponibilidad de entrada/servicios esenciales. Capturar renderer/GPU real, render loop, Hz/DPR, builds, commits, modo energía, caché fría/caliente y módulos activos. Perfilar QML y CPU/GPU de host, shell, DWM y proveedor externo separadamente; conservar trazas de bloqueos > presupuesto de frame.
Automatizar escenarios repetibles del apartado 8, sin convertir logging de cada frame en coste habitual. Benchmarks en build Release comparable; mantener build diagnóstico separada. No introducir envío de telemetría externa.

**Criterios de aceptación:**

- Se pueden comparar dos builds con el mismo escenario y metodología.
- p95/p99 de frame/latencia, dropped frames, working set/private bytes y handles aparecen con duración/muestreo.
- El primer frame de una pantalla no declara listas las demás; caché caliente y fría no se mezclan.

**Pruebas y evidencia:**

Obtener corridas repetidas de referencia en Windows. Validar orden y monotonía de timestamps, medir sobrecoste con instrumentación activada/desactivada y guardar datos brutos. Si solo hay Linux, preparar el harness y marcar la toma real pendiente.


### Fase 1: Fallos críticos


#### R01 — Coordinar permisos y salud antes de ocultar notificaciones

**Estado inicial:** TODO. **Prioridad:** P0. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: host/src/main.cpp, banners.cpp; qs: src/win32/services/notifications.cpp/.hpp; nuevo: handshake del listener.

**Problema o finalidad:** El host oculta banners aunque el listener no tenga permiso o no pueda recibir los avisos de otras apps. Eso puede eliminar el único canal visible.

**Implementación requerida:**

Crear acuerdo entre listener y host con identidad de instancia, permiso, suscripción activa y salud. Aplicar supresión solo tras confirmación operativa; no confundir notificaciones internas propias con recepción del sistema. Revocación, pérdida de worker o timeout deben retirar supresión y mostrar estado propio cuando ii siga disponible. Respetar preferencias originales y restauración condicional.
Evitar que la llamada periódica actual vuelva a ocultar banners mientras el listener está degradado. No forzar permisos ni simular que están concedidos. Explicar dentro de ii por qué hay fallback del sistema en ese estado.

**Criterios de aceptación:**

- Permiso denegado o revocado conserva un canal real de avisos.
- Listener listo produce popup ii sin duplicación ordinaria; la transición no pierde el primer aviso.
- Al salir/fallar, solo se restauran los cambios que ii posee.

**Pruebas y evidencia:**

Primer inicio, aceptar/denegar, revocar durante sesión, detener worker, colgar shell, reiniciar Explorer y reactivar permiso. Emitir notificaciones de una app fixture y confirmar recepción visible, no solo un booleano. Probar que health de otra instancia no activa supresión.


#### R02 — Lanzar y activar la shell como operación recuperable

**Estado inicial:** TODO. **Prioridad:** P0. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: host/src/main.cpp, splash.cpp, taskbar.cpp, desktop.cpp y guard/rescue; qs: punto de readiness.

**Problema o finalidad:** runHost aplica ocultaciones antes de startShell; si CreateProcess falla, el host puede seguir vivo sin restaurar el entorno.

**Implementación requerida:**

Modelar preparación, lanzamiento, espera de readiness, activación, degradación y restauración. Toda salida fallida de lanzamiento o relanzamiento debe limpiar cubierta, handles y modificaciones aplicadas; comprobar y propagar startShell. Readiness debe incluir primer frame útil por monitor y mínimo de entrada/servicios, con timeout explícito y diagnóstico, en lugar de reconocer cualquier HWND por su tamaño.
Hacer rollback idempotente, compartido por salida normal, error y rescate independiente. Limitar reintentos con backoff; no alternar infinito entre pantalla negra y splash. Explorer debe poder recuperarse aunque QML esté colgado.

**Criterios de aceptación:**

- Ejecutable ausente o salida temprana no deja escritorio/barra ocultos.
- Caída después de activación recupera un entorno utilizable o un rescate independiente.
- Fallo de un monitor se conoce; no retirar protección de arranque global por una ventana incidental.

**Pruebas y evidencia:**

Inyectar ruta inexistente, acceso denegado, DLL ausente, proceso que sale antes de QML, QML inválido y relanzamiento fallido. Matar shell/host/guard por separado en entorno de prueba. Verificar estado real de Explorer y ausencia de cubiertas/handles huérfanos.


#### R03 — Corregir el contrato de bloqueo solicitado y confirmado

**Estado inicial:** TODO. **Prioridad:** P0. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** qs: src/win32/compat/wayland.cpp/.hpp y notificaciones WTS; ii: tools/port/patch_ii_lock.py, overlay/ii/modules/common/functions/Session.qml.

**Problema o finalidad:** isSecure devuelve el estado solicitado antes de confirmar el bloqueo. La espera de 450 ms y el retorno no comprobado de LockWorkStation hacen engañoso el contrato.

**Implementación requerida:**

Separar estado solicitado, llamada aceptada, bloqueo confirmado, desbloqueo y error. Derivar secure de información de sesión real, con estado inicial desconocido hasta resolverlo. Revisar recepción WTS de la sesión correcta, inicialización, RDP y reconexión. Una llamada exitosa a LockWorkStation inicia una operación asíncrona; no es confirmación.
Solicitar bloqueo sin demorar la protección por una animación decorativa. Coordinar transición visual con eventos confirmados; cancelar timers viejos y no permitir que un unlock local QML declare autenticación. Mantener disponible la ruta segura del sistema.

**Criterios de aceptación:**

- secure no es true solo porque se pidió bloqueo o empezó la animación.
- Error de API se propaga con información útil y no deja una falsa pantalla protegida.
- Desbloqueo confirmado restaura foco/animaciones sin ejecutar una segunda solicitud vieja.

**Pruebas y evidencia:**

Fixtures de éxito asíncrono, error y eventos tardíos/otra sesión; luego Win+L, bloqueo ii, RDP, suspensión y reanudación reales. Comprobar estado WTS y UI, incluyendo inicio ya bloqueado cuando sea posible. No introducir ni probar contraseñas propias en QML.


#### R04 — Limitar desinstalación a datos propiedad de ii

**Estado inicial:** TODO. **Prioridad:** P0. **Alcance:** CORE. **Dependencias:** B01.

**Fuentes y archivos iniciales:** ii: tools/package/uninstall.ps1, install.ps1 y manifest de instalación.

**Problema o finalidad:** La eliminación de todo LOCALAPPDATA/quickshell sin KeepConfig puede borrar configuraciones ajenas al port.

**Implementación requerida:**

Inventariar directorios concretos de configuración, estado, caché y secretos que ii posee. Desinstalar por propiedad validada, separando mantener configuración y mantener secretos cuando el contrato lo permita. Migrar manifests antiguos sin asumir que todo quickshell es propio. Resolver rutas y rechazar directorios externos, raíces y entradas manipuladas; tratar junctions/symlinks sin recorrer datos ajenos.
Documentar la semántica de KeepConfig y cambios compatibles. Si no puede demostrarse propiedad de un dato, conservarlo e informar, no ampliarla por conveniencia.

**Criterios de aceptación:**

- Otras configuraciones de Quickshell sobreviven con y sin KeepConfig.
- Datos propios elegidos para borrado desaparecen; los preservados siguen utilizables al reinstalar.
- Un manifest corrupto no permite borrar una ruta arbitraria.

**Pruebas y evidencia:**

Sandbox con sentinels ajenos, dos configs, manifest ausente/antiguo/manipulado, junction a una carpeta externa y rutas con espacios. Instalación→upgrade→uninstall y reinstalación KeepConfig. Inspeccionar archivos reales, no solo salida del script.


### Fase 2: Fiabilidad y propiedad


#### R05 — Rescatar solo los procesos de la instancia supervisada

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R02.

**Fuentes y archivos iniciales:** ii: host/src/main.cpp, killProcessesNamed, guard y tools/rescue; scripts que usan Get-Process por nombre.

**Problema o finalidad:** El cierre genérico de quickshell.exe puede terminar instancias que no pertenecen a ii.

**Implementación requerida:**

Sustituir selección solo por nombre por proceso supervisado, ruta de ejecutable, identidad de usuario/sesión, tiempo de creación y pertenencia al job/instancia. Compartir identificadores necesarios con el rescate mediante estado local validado; manejar PID reutilizado y proceso desaparecido. Mantener una herramienta independiente de QML y del event loop del host.
La terminación debe ser acotada, intentar cierre ordenado cuando corresponda y conservar un último recurso para la instancia colgada. No cerrar todo Quickshell para simplificar un relanzamiento.

**Criterios de aceptación:**

- Panic/guard/rescue terminan la instancia afectada y restauran su entorno.
- Una segunda instancia ajena queda intacta.
- PID reutilizado o estado viejo no autoriza terminar el proceso nuevo.

**Pruebas y evidencia:**

Ejecutar ii y una instancia fixture con el mismo nombre/ruta diferente; probar otra configuración del mismo ejecutable, otra sesión si existe, host colgado y PID stale simulado. Registrar objetivos seleccionados sin exponer argumentos sensibles.


#### R06 — Hacer autostart independiente por usuario y dueño

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R04.

**Fuentes y archivos iniciales:** ii: tools/package/autostart-task.ps1, install.ps1, uninstall.ps1.

**Problema o finalidad:** El nombre fijo ii-windows y Register-ScheduledTask -Force pueden sustituir la tarea de otro usuario.

**Implementación requerida:**

Usar identidad estable por SID y carpeta/nombre de tarea propios. Registrar dueño, acción y versión; actualizar/eliminar solo la tarea reconocida. Migrar la antigua si se verifica que pertenece a esta instalación; si no, conservarla y explicar conflicto. Mantener contexto de usuario y privilegios mínimos necesarios, sin elevar toda la shell por defecto.
No guardar nombres de usuario como identificador durable ni mezclar sesiones con acciones que restauren la barra de otro usuario.

**Criterios de aceptación:**

- Instalar para dos usuarios no reemplaza ni borra la tarea ajena.
- Upgrade mantiene una sola tarea propia activa.
- Desinstalar retira exclusivamente su autostart y conserva tareas con el mismo nombre pero distinto dueño.

**Pruebas y evidencia:**

Dos cuentas de prueba, cambio rápido de usuario, tarea antigua válida, tarea homónima externa y perfil con ruta no ASCII. Revisar XML/propiedades y ejecución en logon; no afirmar multiusuario validado con una única cuenta.


#### R07 — Instalar y actualizar runtime con activación y rollback

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R02, R04.

**Fuentes y archivos iniciales:** ii: tools/package/install.ps1, make-package.ps1, scripts deploy y resolución de runtime del host.

**Problema o finalidad:** robocopy /MIR sobre la instalación activa puede dejar mezcla de versiones ante interrupción; backup del registro no revierte binarios.

**Implementación requerida:**

Preparar versión en carpeta propia distinta; verificar hashes, estructura, pareja de commits y dependencias antes de activarla. Diseñar mecanismo de selección activa atómico en el sistema de archivos soportado, con journal recuperable y versión anterior retenida. No usar cambios de enlace/ruta sin resolver restricciones reales de permisos y archivos en uso.
Probar health/readiness del nuevo runtime en ambiente seguro o primera activación controlada. Fallo de copia/verificación/arranque debe volver a la versión anterior y restaurar cambios propios. Evitar borrar fallback hasta completar verificación. Migración de config debe permitir rollback compatible o restaurar backup.

**Criterios de aceptación:**

- La instalación activa nunca contiene mitad de dos paquetes.
- Una interrupción deja una versión válida seleccionable.
- Fallo del nuevo runtime devuelve un entorno operativo y diagnóstico del intento.

**Pruebas y evidencia:**

Inyectar disco lleno, copia interrumpida, archivo bloqueado, hash incorrecto, binario incompatible y fallo antes/después de cambiar puntero. Reiniciar proceso de instalación y verificar recuperación del journal. Entregar procedimiento de rollback probado.


#### R08 — Preservar propiedad y decisiones del usuario entre upgrades

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R04, R07.

**Fuentes y archivos iniciales:** ii: tools/package/install.ps1/uninstall.ps1, host/src/theme.cpp, cambios GPU/cursor/fuentes/banners.

**Problema o finalidad:** gpuPreference pierde propiedad al reinstalar si el valor ya existe; restauraciones ciegas también pueden pisar cambios posteriores.

**Implementación requerida:**

Migrar el manifest previo conservando valor original, aplicado y dueño de cada cambio. Comparar tipos y contenido antes de restaurar; si el usuario lo cambió después, conservar su elección y registrar el conflicto. Aplicar a GPU preference y revisar tema, cursor, fuentes y banners con el mismo criterio.
Distinguir recursos compartidos de archivos realmente instalados por ii. No tomar un valor ya creado por ii como si fuera un valor original nuevo en cada upgrade; tampoco eliminar un valor ajeno por coincidir con el recomendado.

**Criterios de aceptación:**

- Install→upgrade→uninstall restaura el original cuando sigue siendo propio.
- Un cambio posterior del usuario sobrevive.
- Repetir instalación/desinstalación es idempotente y no acumula respaldos incoherentes.

**Pruebas y evidencia:**

Matriz valor ausente/preexistente/propio/externo-modificado, tipos de registro diferentes, upgrade antiguo y fuentes compartidas. Comparar estado inicial/final real. Probar manifests incompletos y restauración interrumpida.


#### R09 — Endurecer escritorios privados y limpieza automática

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: host/src/vdesk.cpp, overlay/ii/services/DesktopCleanup.qml, HyprlandData.qml; qs: virtualdesktops.cpp, compat/hyprland.cpp.

**Problema o finalidad:** Un probe de conteo no acredita todos los métodos privados en builds futuros. La limpieza usa índices y una vista retrasada sin comprobar vacío al ejecutar.

**Implementación requerida:**

Separar capacidades read/switch/create/remove/move/pin por combinación de build e interfaz realmente probada. Retener aislamiento de llamadas, añadir resultados estructurados, plazos, backoff y desactivación de la operación fallida. No aceptar todos los builds >=26100 como garantía. No abrir Task View automáticamente al fallar.
Recomendar limpieza automática opt-in; migrar el default cuidadosamente e informar el cambio. Usar GUID estable, respetar nombres/pins y reconsultar ventanas/estado justo antes de eliminar. Cancelar si cambia inventario, orden o destino; reconocer que no hay transacción pública perfecta y favorecer no borrar en ambigüedad.

**Criterios de aceptación:**

- Cada acción refleja su capacidad real, sin éxito visual ficticio.
- No se elimina un escritorio ocupado, fijado o identificado por un índice viejo.
- Fallo/incompatibilidad conserva navegación y explica la limitación en ii.

**Pruebas y evidencia:**

Builds Windows soportados, Explorer reiniciado, crear/cerrar ventana durante los 800 ms, reordenar/cambiar desktop, ventana pinned, última pantalla y llamada privada fallida. Registrar GUID/resultado sin datos personales. Compatibilidad futura queda desconocida hasta probarla.


#### R10 — Convertir pruebas existentes en regresiones con assertions

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** VALIDACIÓN. **Dependencias:** B01, R01, R02, R03, R04.

**Fuentes y archivos iniciales:** ii: tools/sandbox/tests, sbx.ps1; cobertura de cambios R y escenarios de entrada/recuperación.

**Problema o finalidad:** El runner fiable no vuelve completas las pruebas existentes; muchas rutas necesitan verificación de resultado y efectos.

**Implementación requerida:**

Revisar tests relacionados con tareas ejecutadas y exigir observables concretos: estado de Explorer, recepción real de aviso, datos preservados, proceso correcto y estado WTS. Añadir solo regresiones significativas de fallos críticos, reutilizando fixtures/harness. Separar pruebas de lógica, integración Windows y hardware; declarar skips con motivo y nunca contarlos como PASS.
Hacer que la suite pueda seleccionar módulos/escenarios y no dependa de sleeps arbitrarios donde existe señal de finalización. Conservar salida suficiente para reproducir errores intermitentes.

**Criterios de aceptación:**

- La regresión falla contra la conducta defectuosa y pasa con la corrección.
- PASS significa assertions terminadas en la corrida actual.
- Resultados incluyen omitidos/no disponibles y requisitos pendientes.

**Pruebas y evidencia:**

Ejecutar suite relevante antes/después o introducir fault injection equivalente. Probar la selección por módulo y agregación de skips/fallos. No es necesario expandir toda la suite por cada cambio visual menor.


#### R11 — Unificar secretos y limpiar temporales/datos sensibles

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B01.

**Fuentes y archivos iniciales:** ii: host/src/secrettool.cpp, airequest.cpp, tools/port/patch_ii_ai.py y parche/config de galería; qs: notifications.cpp; tools/rescue/ii-report.ps1.

**Problema o finalidad:** IA ya usa DPAPI, pero credencial Gelbooru sigue en JSON; hay cuerpos temporales de chat y logs con contenido personal.

**Implementación requerida:**

Migrar la clave de galería al almacén por usuario existente, sin borrar el valor antiguo hasta comprobar escritura/lectura segura. Actualizar UI y mensajes que indican editar config en claro. Gestionar archivos request.instance.json durante éxito, error y cancelación; limpiar huérfanos propios con TTL y límite sin tocar otros archivos.
Redactar headers/tokens, chat, texto OCR y resumen de notificación en logs/report por defecto; permitir detalle local explícito con advertencia concreta. Exportar configuración sin secretos. Revisar permisos de archivos y no poner keys en argumentos de proceso.

**Criterios de aceptación:**

- No queda una segunda copia activa de la clave migrada en config/export.
- Cancelar/error no acumula cuerpos sensibles; limpieza no borra archivos ajenos.
- El reporte normal no contiene fixtures de secretos ni contenido privado de avisos/chats.

**Pruebas y evidencia:**

Migración con error DPAPI/IO, perfil diferente, valor antiguo corrupto, request cancelada/crash y temporales ajenos. Usar tokens/textos sentinel y comprobar su ausencia en config, logs y reportes. No emplear claves reales ni llamar servicios pagados para esta prueba.


### Fase 3: Rendimiento y arranque


#### P01 — Investigar render loop sin perder repintado o entrada

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02, R02.

**Fuentes y archivos iniciales:** qs: src/win32/init.cpp, native.cpp y panel windows; Qt Quick render loop.

**Problema o finalidad:** El loop basic es un workaround por stalls de ventanas layered/click-through. Cambiarlo sin reproducción puede dejar la shell sin pintar hasta mover el ratón.

**Implementación requerida:**

Perfilar primero basic con cambios de contenido sin input. Localizar trabajo GUI bloqueante y el fallo específico de invalidación/rendering. Preparar flag experimental reversible para threaded solo si permite reproducir y comparar. Separar comportamiento de ventanas opacas, transparentes, layered y click-through; documentar backend/Qt/GPU del resultado.
Conservar basic predeterminado hasta demostrar estabilidad. No usar software, spin continuo, QSG_NO_VSYNC ni forced updates permanentes para esconder el fallo.

**Criterios de aceptación:**

- Cambios de UI se pintan sin depender de movimiento del ratón.
- El modo elegido no empeora hit testing, transparencias ni reposo.
- Cualquier cambio de default tiene evidencia repetida en GPU/DPI/ventanas soportadas y rollback simple.

**Pruebas y evidencia:**

Idle sin input, reloj/notificación por evento, popup, arrastre, cubierta por app, lock/resume, RDP y dos monitores. Comparar frame tails y CPU/GPU con loop actual. Si threaded sigue fallando, entregar reproducción/diagnóstico y mantener workaround; no marcar el cambio de default como completado.


#### P02 — Actualizar miniaturas DWM solo cuando cambian propiedades

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** qs: src/win32/compat/wayland.cpp/.hpp, DWM thumbnail callbacks/timers; overview/dock consumidores.

**Problema o finalidad:** Timer de 33 ms, afterAnimating y frameSwapped pueden actualizar la misma miniatura; la comparación ocurre después de DwmUpdateThumbnailProperties.

**Implementación requerida:**

Guardar estado efectivo de rectángulo, clip, opacidad y visibilidad y comparar antes de llamar DWM. Coalescer cambios una vez por frame cuando esté visible; suscribirse a geometría de fuente/destino en vez de sondear indiscriminadamente. DWM ya mantiene contenido vivo: no necesita repetir propiedades por cada frame de la app.
Liberar registros al cerrar/destruir fuente y destino; limitar retries y conservar retención de popups sin handles ilimitados. Documentar que live/cursor y screenSource actuales no equivalen a captura de textura. Separar snapshots de minimizadas en C10.

**Criterios de aceptación:**

- Fuente estática/destino estático no dispara actualizaciones periódicas inútiles.
- Animación/movimiento actualiza geometría sin tearing visual ni clip incorrecto.
- Ocultar/cerrar libera recursos y una fuente desaparecida no crea un bucle de error.

**Pruebas y evidencia:**

Instrumentar contador de calls antes/después: idle, 30 miniaturas, arrastre, resize, minimized, HWND destruido y 100 aperturas. Comprobar contenido vivo aun sin repetir properties, clips en varios DPR y ausencia de crecimiento de DWM handles.


#### P03 — Acotar decodificación de fotos y pausar GIF realmente ocultos

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: overlay/ii/modules/ii/background/widgets/photo/PhotoWidget.qml; servicio de metadata nuevo si hace falta.

**Problema o finalidad:** Todas las fotos usan AnimatedImage con tamaño natural no limitado. GIF no considera toda la cobertura/bloqueo y efectos multiplican buffers.

**Implementación requerida:**

Distinguir imagen estática y animada; obtener dimensiones naturales para layout sin realimentar sourceSize hacia dimensiones del widget. Definir tamaño de decodificación por tamaño visible y DPR con techo razonado; usar metadata separada para evitar el binding loop citado en el código.
Pausar GIF al cubrir escritorio, bloquear sesión, ocultar monitor/widget o aplicar perfil batería/reducir movimiento. Mantener último frame/placeholder y reanudar sin reiniciar repetidamente el archivo. Acotar FBO de máscara/sombra al rectángulo útil; respetar recorte y edición existentes.

**Criterios de aceptación:**

- Foto 8K en widget pequeño no mantiene innecesariamente decode 8K.
- No hay binding loop ni salto de tamaño al cambiar escala/imagen.
- GIF oculto no decodifica frames continuamente y al reaparecer sigue correcto.

**Pruebas y evidencia:**

JPEG/PNG 8K, GIF grande/corrupto, orientación EXIF, reemplazo del archivo, escalas 0.3–4 y DPR mixto. Comparar RAM/GPU/frame time visible y cubierto. Verificar detección de formato sin depender solo de extensión.


#### P04 — Eliminar animación decorativa perpetua del placeholder media

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: overlay/ii/modules/ii/background/widgets/media/MediaWidget.qml y configuración del widget.

**Problema o finalidad:** El placeholder visible sin música sigue rotando/morphing y obliga a repintar un escritorio que podría estar quieto.

**Implementación requerida:**

Hacer estático el estado idle por defecto, con transición breve al entrar o cambiar estado. Ofrecer decoración continua como opción explícita y respetar perfiles/reducir movimiento/cobertura/bloqueo. Migrar valores viejos sin dejar una animación oculta activa por una preferencia retirada.
Conservar controles, carátula y espectro útiles durante reproducción; no convertir todos los widgets en estáticos por una optimización genérica.

**Criterios de aceptación:**

- Escritorio sin reproducción no emite frames por ese placeholder.
- Cambiar play/pause o carátula conserva transición y controles.
- Decoración opt-in se pausa donde corresponda y no afecta a audio real.

**Pruebas y evidencia:**

Medir idle con widget visible antes/después y comparar estado música. Probar configuración antigua, reducir movimiento, cubrir/descubrir y lock/resume; comprobar que no quedan NumberAnimations/timers activos cuando no aportan imagen.


#### P05 — Compartir espectro, estado media y captura de audio

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: host/src/cava.cpp; up: modules/ii/mediaControls/MediaControls.qml; overlay/parches media; qs: mpris.cpp.

**Problema o finalidad:** MediaControls puede mantener Cava activo sin reproducción; IPC modifica Loader.active y rompe el binding al estado global. Hay procesamiento/text parse por frame.

**Implementación requerida:**

Definir un único estado de apertura y consumidores visibles del espectro. Compartir captura WASAPI/FFT por endpoint con refcount; ejecutar solo si existe consumidor que lo necesita y estado compatible. Cerrar último consumidor debe liberar captura sin pausar música de la app. Usar generación para cambiar endpoint y descartar callbacks viejos.
Evaluar salida/modelo nativo y backpressure en vez de crear arrays JS desde texto a 60 FPS por consumidor. Proponer 30 FPS decorativos configurables, limitado por presupuesto real; mantener barras en cero/último estado apropiado al pausar. Revisar deduplicación/selección GSMTC sin asumir que todos los reproductores anuncian estado igual.

**Criterios de aceptación:**

- Barra/widget/panel simultáneos comparten un pipeline en el alcance posible.
- IPC y atajo abren/cierran la misma UI sin perder bindings.
- Ninguna vista, sesión bloqueada o música pausada libera trabajo opcional y no corta reproducción externa.

**Pruebas y evidencia:**

Media en 1/3 vistas, play/pause, endpoint unplug, múltiples reproductores, cerrar panel desde IPC/teclado y 100 ciclos. Medir procesos, WASAPI handles, FFT y JS allocations. Incluir sesión que no reporta playing y fallback explícito, sin asumir silencio total.


#### P06 — Cargar paneles y pestañas bajo demanda con retención acotada

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** up: SidebarLeft.qml, panelFamilies/PanelLoader.qml, tabs IA/traductor/galería; ii: overlay/parches equivalentes.

**Problema o finalidad:** Panel izquierdo y varias pestañas se crean al inicio; keepLoaded y SwipeView pueden mantener servicios/red activos nunca vistos.

**Implementación requerida:**

Separar modelos persistentes de vistas pesadas. Cargar cada pestaña al primer uso y detener tareas no solicitadas cuando se oculta; conservar borradores/chat/scroll en un modelo duradero. Usar Loader asíncrono o creación por etapas con presupuesto; prewarm opcional solo después de primer frame útil, durante tiempo libre.
Definir retención LRU/TTL con presión de memoria, sin destruir popups en cada hover. No empezar red de galería/IA para una pestaña nunca abierta. Evitar blank flash y restaurar foco con placeholder propio inmediato.

**Criterios de aceptación:**

- Inicio no instancia todos los módulos pesados ni hace peticiones ajenas al uso.
- Primera apertura tiene feedback inmediato y no bloquea animación.
- Cerrar/reabrir preserva datos; la retención no crece ilimitadamente.

**Pruebas y evidencia:**

Perfil de instanciación/red al iniciar, primera/segunda apertura, cambio rápido de tabs, 100 ciclos y presión de memoria. Probar chat con borrador y traducción en curso cancelable. Comparar cold/warm startup y p99 de apertura.


#### P07 — Actualizar ventanas/escritorios con deltas y cobertura por monitor

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02, R09.

**Fuentes y archivos iniciales:** qs: src/win32/toplevels.cpp, virtualdesktops.cpp; ii: overlay/ii/services/HyprlandData.qml, DesktopCover.qml.

**Problema o finalidad:** Ráfagas WinEvent pueden terminar en EnumWindows y consultas completas; QML reconstruye listas cada segundo y hay búsquedas cuadráticas.

**Implementación requerida:**

Mantener índice HWND con identidad/lifetime y dirty flags por propiedades; cachear metadata de proceso/app que no cambia por ubicación. Tratar foco/MRU separadamente de inventario; coalescer geometría y actualizar modelos por inserción/cambio/removal. Reconciliar completo a frecuencia baja o tras pérdida de eventos, no eliminar todo fallback.
Calcular cobertura desde el mismo modelo, por monitor y escritorio, contemplando minimized/cloaked/occluded. Evitar múltiples filtrados completos en JS para cada consumidor. Mantener sincronización y shutdown seguros; no convertir HWND reutilizado en la ventana antigua.

**Criterios de aceptación:**

- Mover una ventana no reconstruye metadatos y listas de todas.
- Foco, cierre y cambio de desktop reflejan estado correcto sin esperar un segundo.
- Cobertura de un monitor no pausa widgets de otro visible.

**Pruebas y evidencia:**

100 ventanas fixture, ráfagas move/resize/name/focus, creación/destrucción rápida, HWND reuse simulado, Explorer restart y dos monitores. Medir enumeraciones, COM calls, JS allocations y latencia; cotejar modelo final contra reconciliación completa.


#### P08 — Sacar thumbnails e iconos Shell lentos del hilo GUI

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** qs: src/core/iconimageprovider.cpp, winapps.cpp/.hpp; consumidores fileIcon/appIcon.

**Problema o finalidad:** QQuickImageProvider síncrono puede llamar IShellItemImageFactoryGetImage y extensiones Shell lentas durante una carga visible.

**Implementación requerida:**

Introducir proveedor asíncrono compatible con QML y workers COM inicializados en el apartamento requerido. Extraer QImage/bytes fuera del GUI; gestionar respuesta, cancelación y lifetime al destruir el delegate. Limitar concurrencia, priorizar elementos visibles y deduplicar requests por identidad/tamaño.
Política de miniaturas cache-only/placeholder cuando un archivo nube/UNC no tiene contenido local; no hidratar archivos solo por enseñarlos ni recorrer shares al arrancar. Conservar el trabajo inicial de indexado de apps que ya está en background.

**Criterios de aceptación:**

- Un extractor lento no congela input/animación.
- Respuestas de delegates cerrados no se aplican a otro elemento.
- Offline/cloud placeholder conserva ruta y permite una acción explícita posterior.

**Pruebas y evidencia:**

Fixture extractor lento/error, OneDrive placeholder real si disponible, UNC desconectada, archivo borrado y scroll rápido. Comparar p99 de frame y verificar COM init/shutdown, límites de cola, no hidratación inesperada y ninguna manipulación insegura de QPixmap en worker.


#### P09 — Sustituir cachés sin límites/clear-all por presupuestos LRU

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** P08.

**Fuentes y archivos iniciales:** qs: src/core/winapps.cpp y caches image providers; ii: descargas/galería/carátulas donde comparten recursos.

**Problema o finalidad:** File memo se vacía entero al superar 512 entradas; app memo y disco pueden crecer sin presupuesto. Cantidad de entradas no representa bytes.

**Implementación requerida:**

Definir budgets CPU/GPU/disco separados, LRU por bytes y protección de recursos visibles. Incluir tamaño físico/DPR, mtime o versión/identidad en clave; invalidar un archivo cambiado sin purgar todo. Limitar variantes y descargar recursos con cuotas de tamaño/concurrencia/retención. Mantener último dato válido ante offline.
No imponer una cifra universal sin medir: proponer defaults por perfil y permitir diagnóstico/ajuste. Evitar que widgets pidan continuamente una dimensión distinta por animación y llenen cache de variantes casi iguales.

**Criterios de aceptación:**

- Sobrepasar presupuesto expulsa gradualmente recursos no usados.
- Mismo recurso en varias vistas no duplica innecesariamente decode/request.
- Cambiar archivo/DPR devuelve imagen actual y almacenamiento se mantiene acotado.

**Pruebas y evidencia:**

Scroll de miles de resultados, variantes DPI, modificación de archivo, cache corrupta, disco lleno y reapertura. Medir hit rate, bytes, churn y latencia; verificar que una expulsión no borra archivos del usuario ni deja delegates sin fallback.


#### P10 — Convertir audio/red/Bluetooth en servicios asíncronos y por eventos

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** qs: src/win32/services/pipewire.cpp, network.cpp, bluetooth.cpp, hardware_async.hpp.

**Problema o finalidad:** Rescans Core Audio cada 1500 ms y refresco de red cada 5 s ejecutan consultas GUI. WLAN inicial puede no recuperarse si el servicio estaba apagado.

**Implementación requerida:**

Usar callbacks/notificaciones del sistema para dispositivo/sesión/red, con workers y apartamentos correctos. Consolidar snapshots y enviar deltas al GUI; reconciliar lento, más frecuente solo con panel visible cuando haga falta. Inicialización no debe bloquear primer frame. Implementar reintento/backoff para servicio WLAN ausente al inicio, hotplug y varios adaptadores, sin asumir que el primero es el relevante.
Separar desconocido/sin permiso/sin adaptador/apagado/error. Asegurar unsubscribe, cancelación y destrucción de workers para evitar callbacks a objetos muertos. En el cambio de default audio privado, comprobar resultado por rol y declarar capacidad limitada.

**Criterios de aceptación:**

- Abrir/cerrar panel modifica la frecuencia de trabajo sin perder eventos reales.
- Un servicio que aparece después del inicio se detecta.
- Error de API no cambia un toggle a éxito falso ni bloquea QML.

**Pruebas y evidencia:**

Callback storms, endpoint USB unplug, servicio WLAN off→on, dos adaptadores, red desconectada, Bluetooth sin radio y worker shutdown. Usar hardware real para acreditar operaciones; mocks solo prueban actualización de estado/error. Comparar stalls GUI y calls/segundo.


#### P11 — Basar temporizadores en tiempo real y limitar refresh visual

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** up: services/TimerService.qml, pomodoro/uptime/resources; ii: parches/widgets correspondientes.

**Problema o finalidad:** Cronómetro a 10 ms y pomodoro a 200 ms pueden seguir refrescando ocultos. Contar ticks introduce deriva y comportamiento incierto al dormir.

**Implementación requerida:**

Definir semántica por timer: cronómetro usa fuente monotónica adecuada; pomodoro conserva deadline y regla explícita sobre suspensión. Propuesta: pomodoro continúa por tiempo transcurrido incluyendo suspensión y emite una sola finalización al volver; cronómetro también cuenta tiempo transcurrido incluyendo suspensión mientras no se pause manualmente; verificar y documentar que la fuente Windows elegida cumple esa regla. Evitar usar reloj civil cambiante como contador sin tratamiento de ajustes.
Calcular valores desde timestamps, actualizar texto solo visible y al ritmo de precisión presentada. Hacer persistencia de transiciones, no escritura por tick. Revisar clamps de intervalos; no confundir valores iniciales breves de recursos/uptime con el intervalo final configurado de 3 s.

**Criterios de aceptación:**

- Ocultar UI reduce refresh sin alterar duración real.
- Reanudación produce estado coherente y una sola alarma.
- Cambio de reloj/fuso no genera contador negativo, spam ni deriva por ticks perdidos.

**Pruebas y evidencia:**

Pause/resume/reset, cerrar panel, dormir más que deadline, ajustar reloj y reabrir config persistida. Comparar tiempo contra referencia; si la fuente monotónica elegida excluye suspensión, usar otra fuente/compensación validada para cumplir la regla propuesta, sin cambiarla silenciosamente.


#### P12 — Sustituir sondeo redundante y mantener hook barato

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** qs: src/win32/native.cpp, keyboardlayout.cpp y AppBar/InputRegions; ii: host/src/keyboard.cpp, main.cpp.

**Problema o finalidad:** Persisten sondeos de foco/layout, AppBar y host. El callback de teclado debe mantenerse por debajo de los límites del sistema incluso bajo carga.

**Implementación requerida:**

Inventariar cada timer: función, coste, consumidor y señal disponible. Usar eventos de sesión/display/layout/Explorer/config donde sean fiables; conservar watchdog de reconciliación lento y adaptativo. No quitar el fallback actual de cursor de 250 ms sin demostrar cobertura de eventos.
En hook usar estado mínimo cacheado/atómico, seguimiento down/up de modificadores y despacho asíncrono; no COM, IO, enumeración ni GetWindowRect repetido pesado. Revisar el uso de GetAsyncKeyState antes de actualizar la tecla actual según documentación. Limpiar estados al perder sesión/foco y preservar rescue independiente.

**Criterios de aceptación:**

- Menos wakeups en reposo sin pérdida de detección/entrada.
- Hook no espera al hilo UI y no necesita aumentar timeout del sistema.
- Click-through, hover y áreas interactivas siguen correctos con mouse/touch donde se soporte.

**Pruebas y evidencia:**

Traza de timers y duración callback bajo carga, teclas down/up, tecla Win sola, alt-tab rápido, lock/resume, input inyectado y Explorer restart. Probar fallo de un evento para acreditar reconciliación; medir 100 ciclos de popup/hit testing.


#### P13 — Optimizar búsqueda y descartar resultados viejos

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** up: services/LauncherSearch.qml, AppSearch.qml; ii: overlay/parche y host/src/shim.cpp para cálculo.

**Problema o finalidad:** Se crean objetos por consulta, fuzzy recorre todo y dedup puede ser cuadrático. Calculadora puede arrancar aunque no sea una consulta matemática.

**Implementación requerida:**

Crear índice/modelo estable cuando cambian apps, no en cada tecla; deduplicar con claves indexadas. Limitar candidatos/resultados visibles y virtualizar delegates. Evaluar ranking/fuzzy nativo o algoritmo acotado manteniendo calidad de búsqueda. Cada consulta tiene generación/cancelación; publicar solo la última, incluidos resultados externos.
Detectar intención matemática antes de llamar cálculo; usar debounce medido para IO/proveedores y respuesta inmediata para opciones locales. No afirmar fuga por createObject sin demostrarla, pero controlar lifetime y allocations. No filtrar ejecutando comandos automáticamente.

**Criterios de aceptación:**

- Escritura rápida no presenta resultados de una consulta anterior.
- Índice de miles de apps responde sin stalls perceptibles medidos.
- Consulta ordinaria no genera procesos de cálculo/HTTP innecesarios.

**Pruebas y evidencia:**

Índice grande fixture, typos, acentos, apps Store/Win32 duplicadas, borrar query y consultas concurrentes lentas. Medir p95/p99 tecla→resultado y allocations por 1000 consultas. Comprobar foco/Enter ejecuta el elemento actual.


#### P14 — Reducir FBO y hacer texto nítido en escalado/DPI

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B02.

**Fuentes y archivos iniciales:** ii: widgets/card/WidgetEditFrame y efectos; up: componentes Styled*; qs: ventanas/panel geometry.

**Problema o finalidad:** Sombras/blur/masks offscreen y transform scale pueden multiplicar memoria GPU y desenfocar texto; snap lógico no siempre coincide con píxel físico.

**Implementación requerida:**

Inventariar layers/effects y limitar su región, resolución y lifetime al contenido visible. Cachear lo estático sin invalidación continua, con presupuesto; no quitar toda sombra o estilo para declarar optimizado. Renderizar texto al tamaño/font/layout final en vez de escalar una textura cuando sea viable.
Alinear geometría al píxel físico considerando DPR y anchors para evitar jitter; no redondear indiscriminadamente coordenadas de animación. Mantener identidad Material, clipping, hit testing y proporciones de widgets en edición.

**Criterios de aceptación:**

- Texto es legible en 125/150/175 % y escala de widget sin doble blur.
- UI cubierta no conserva FBO gigantes activos sin consumidor.
- Reducción de efectos mantiene diseño, tamaño y interacción correctos.

**Pruebas y evidencia:**

Capturas comparables 1080p/4K, DPR mixto y escalas 0.3–4; perfil GPU/FBO de paneles abiertos/cerrados. Comprobar clipping, drag handles, tooltip, font grande y reducir movimiento. Documentar tradeoff visual específico si un efecto se modifica.


#### P15 — Hacer splash barato y retirarlo por readiness real

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R02, B02.

**Fuentes y archivos iniciales:** ii: host/src/splash.cpp, main.cpp; qs: señal de primer frame útil.

**Problema o finalidad:** Decode previo y bitmap completo por WM_PAINT/33 ms pueden retrasar shell y repintar fondos que no cambiaron; el timeout no mide readiness.

**Implementación requerida:**

Lanzar shell cuanto antes; decodificar/cargar cubierta de manera acotada y reutilizar bitmap/backbuffer por monitor. Invalidar solo indicador/rectángulos cambiados o usar presentación eficiente compatible con el diseño. Evitar convertir splash en segundo compositor con captura continua del escritorio.
Retirar por confirmación de primer frame y entrada esencial por monitor; registrar fallback/timeout. Mantener cubierta mientras el reemplazo aún no está listo sin prolongar artificialmente inicio. No esconder pantallas no listas por haber detectado otra ventana.

**Criterios de aceptación:**

- Cubierta quieta no recrea un bitmap full-screen cada tick.
- Tiempo proceso→interactivo mejora o coste queda cuantificado.
- Multi-monitor y launch fallido salen sin parpadeo propio evitable ni cubierta huérfana.

**Pruebas y evidencia:**

Cold/warm, 4K dual, wallpaper enorme/ausente, monitor lento, ready parcial y QML que no renderiza. Comparar fases temporales y CPU durante startup. No prometer eliminar la UI de Winlogon previa al inicio del host.


#### P16 — Aplicar prioridad y perfiles por estado, sin trucos globales

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R02, B02, R08.

**Fuentes y archivos iniciales:** ii: host/src/main.cpp y manifest GPU; qs: init/input; nueva política de perfiles visuales.

**Problema o finalidad:** Boost de arranque por 60000 ms y exclusiones globales EcoQoS pueden continuar cuando ya no son necesarias. Preferencia iGPU no siempre beneficia todos los equipos.

**Implementación requerida:**

Terminar boost al readiness con timeout de seguridad; usar prioridad normal para trabajo habitual y proteger el hilo de hook según necesidades medidas. Definir perfiles Normal/Estudio/Juego/Batería para efectos, espectros, fondos y prewarm, sin modificar Defender/servicios globales ni pausar funciones solicitadas.
Evaluar GPU integrada/discreta por equipo/monitor; conservar propiedad de preferencia con R08. Registrar renderer real, no deducirlo de una clave. EcoQoS/throttling en workers decorativos debe ser medido y reversible, no impuesto al camino de input/render.

**Criterios de aceptación:**

- Pasado startup no queda boost alto sin motivo.
- Cambiar perfil reduce trabajo opcional y mantiene respuesta/acciones esenciales.
- Una GPU externa/híbrida no se fuerza ciegamente a una ruta peor.

**Pruebas y evidencia:**

Portátil batería/AC, external display, carga CPU, reproducción y grabación activa; medir latencia y consumo. Verificar prioridad real por thread/proceso y cambios de perfil repetidos. No adjudicar mejora energética sin medición de hardware.


#### P17 — Conservar caché QML y hacer reproducibles builds Windows Release

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** B00, B01.

**Fuentes y archivos iniciales:** qs: CMakeLists.txt, src/core/qmltree.cpp, scan.hpp, CI Windows nueva; ii: deploy.ps1, make-package.ps1, README.

**Problema o finalidad:** Caché real ya funciona, pero receta/build/dependencias y CI heredada Linux no garantizan un paquete Windows Release reproducible.

**Implementación requerida:**

Definir presets Windows explícitos con toolchain soportada, configuración Release, opciones Linux desactivadas donde corresponda, versión Qt/Qt private fijada y dependencias MCU resueltas. En generadores multi-config verificar --config Release; no depender de CMAKE_BUILD_TYPE para ellos. Identificar artefactos deploy adecuados y URLs crash del fork.
Conservar timestamps/identidad de QML y evitar copia innecesaria de árbol/assets mediante manifest incremental seguro. Invalidar caché solo ante cambios reales/compatibilidad de Qt; QS_NO_QMLTREE queda diagnóstico. Guardar commits, flags, dirty state, dependencias y hashes en paquete. Añadir comprobación de build Windows si infraestructura permite, sin afirmar que CI Linux lo verifica.

**Criterios de aceptación:**

- Desde entorno documentado se obtiene paquete identificable con configuración explícita.
- Arranque caliente reutiliza caché y cambios QML sí la invalidan.
- Ayuda/crash no envía al upstream equivocado; dependencias/licencias están inventariadas.

**Pruebas y evidencia:**

Build limpio y repetido, runtime limpio sin SDK, cambio de QML, upgrade de Qt y caché corrupta. Revisar manifest/artefactos realmente empaquetados. No afirmar que la release anterior era Debug solo por un default de CMake.


#### P18 — Aplicar presupuestos de reposo y demostrar fluidez sostenida

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** VALIDACIÓN. **Dependencias:** B02, P02, P03, P04, P05, P06, P07, P08, P09, P10, P11, P12, P13, P14, P15, P16, P17.

**Fuentes y archivos iniciales:** ii/qs: todos los componentes tocados; harness de rendimiento y perfiles.

**Problema o finalidad:** Mejorar componentes aislados no demuestra un entorno fluido ni que los recursos se estabilicen con uso largo.

**Implementación requerida:**

Comparar todos los escenarios con baseline, perfiles y presupuesto por componente. Objetivo de frames interactivos: ajustarse al Hz real, no limitar todo a 60; decoración puede tener frecuencia menor. Un escritorio estático sin cambios útiles no debe repintarse por animaciones innecesarias. Mantener VSync y registrar frame tails/input latency.
Usar metas orientativas del apartado 8 para negociar presupuestos según equipo. Medir drift de RAM, handles, subscriptions, procesos y DWM thumbnails con 100 ciclos/soak. Corregir regresiones atribuibles; si una hipótesis no mejora, documentarla/revertirla de forma selectiva sin borrar otros cambios.

**Criterios de aceptación:**

- Informe antes/después compara build y escenario equivalentes con datos brutos.
- No se gana FPS a costa de pérdida de input, popups, calidad o servicios.
- No hay crecimiento monotónico sin límite de recursos en los ciclos relevantes.

**Pruebas y evidencia:**

Suite de frames/startup/idle y soak definidos abajo; batería/hardware si disponible. Presentar p95/p99 y outliers, no solo promedio/FPS máximo. Un caso no ejecutado mantiene estado pendiente, incluso si los restantes pasan.


### Fase 4: Identidad ii y configuración


#### U01 — Crear catálogo de acciones/capacidades y política de UI ii

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R01, R02, R03.

**Fuentes y archivos iniciales:** ii: host/src/keyboard.cpp, shim.cpp, sidebar.cpp; overlay/ii/services/HyprlandKeybinds.qml y acciones QML; nuevo: catálogo compartido.

**Problema o finalidad:** Tiles, menús y shortcuts tienen rutas divergentes hacia ms-settings, taskmgr, Paint o UI Shell. Ocultar una opción no resuelve sus otras entradas.

**Implementación requerida:**

Inventariar todos los puntos de apertura de UI del entorno: shortcuts, tiles, launcher, IPC, menús, errores, FileDialog/ChooseColor y shims. Resolverlos con catálogo central y capacidades del apartado 3. Las capas pueden compartir manifest generado o contratos tipados, sin duplicar fuentes editables.
Introducir política explícita de identidad ii y allowlist de excepciones protegidas/recuperación. Para función no implementada, mostrar estado/razón y acción externa solo tras elección; jamás fallback automático. Generar chuleta/editor/help desde ese catálogo. Migrar preferencias antiguas y quitar rutas Linux activas sin receptor.

**Criterios de aceptación:**

- Una misma acción tiene resultado consistente desde cualquier entrada.
- No hay ms-settings/diálogo nativo automático en un flujo normal soportado.
- Controles no disponibles explican causa y no simulan éxito ni desaparecen silenciosamente.

**Pruebas y evidencia:**

Auditoría estática rg de protocolos/ejecutables/diálogos, y tracing runtime de activaciones. Ejecutar cada entrada del apartado 7 bajo éxito/error. Lista de excepciones documentada y test de ruta que falla sin lanzar UI externa.


#### U02 — Enrutar atajos completos con política por aplicación

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** U01, P12, R09.

**Fuentes y archivos iniciales:** ii: host/src/keyboard.cpp, configuración/IPC shortcuts; overlay/ii/services/HyprlandKeybinds.qml.

**Problema o finalidad:** Fullscreen geométrico desactiva rutas ii incluso en un navegador maximizado. Faltan varios shortcuts y algunos se bloquean sin acción.

**Implementación requerida:**

Separar ocultación de paneles, permiso para mostrar overlay y enrutamiento de teclas. Default mantiene identidad ii aunque una app llene pantalla; perfil de juego puede ceder combinaciones elegidas por regla explícita. Conservar panic independiente. Manejar down/up, modificadores, tecla Win sola, combinaciones desconocidas y HKL/OEM sin dejar teclas presionadas.
Aplicar la matriz del apartado 7, preservando las acciones existentes útiles; hacer Win+B foco bandeja, Win+T navegación dock, Win+I ajustes ii, Win+R comandos y Win+X herramientas. Acciones sin subsistema muestran límite propio; no inventar un gestor/proceso listo. Evitar apropiarse de Ctrl+Alt+End remoto; map configurable.

**Criterios de aceptación:**

- Maximizar navegador no vuelve Win solo a Inicio Windows.
- Ningún atajo definido se consume sin feedback/acción útil.
- Editor/chuleta reflejan bindings efectivos y conflictos por layout/app; rescue siempre disponible.

**Pruebas y evidencia:**

US/ES, layouts OEM, autorepeat, Win down→otra tecla→up, fullscreen borderless, juego opt-out, elevación/UIPI, RDP y lock/resume. Capturar destinos reales. No interceptar SAS ni romper accesibilidad porque una función no tiene reemplazo.


#### U03 — Añadir selector Alt+Tab ii rápido y navegable

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** U02, P02, P07.

**Fuentes y archivos iniciales:** ii: acciones overview/dock y overlay nuevo para switcher; qs: modelo de ventanas/MRU y foco.

**Problema o finalidad:** Alt+Tab sigue abriendo selector de Windows; overview no reemplaza su interacción de mantener Alt y soltar para activar.

**Implementación requerida:**

Crear selector liviano con modelo MRU del mismo tracker, evitando reenumeración/thumbnail blocking al abrir. Mantener abierto mientras Alt, Tab avanza, Shift+Tab retrocede y soltar Alt activa una vez. Escape cancela al foco original; cerrar/cambiar ventana durante selección actualiza índice por identidad estable.
Ofrecer ámbito escritorio actual/todos según capacidades, filtrando cloaked/tool windows y manteniendo minimizadas elegibles con snapshot/placeholder. No capturar toda pantalla a 60 FPS para esta vista; reutilizar políticas de cache y retención.

**Criterios de aceptación:**

- Primera respuesta visual inmediata y p95/p99 medidos.
- Cancelar no cambia foco ni ejecuta doble activación.
- Cerrar una ventana seleccionada no activa otra por índice obsoleto.

**Pruebas y evidencia:**

1/100 ventanas, minimizadas, Store/Win32, Shift reverse, Escape, tecla Alt liberada tras lag, ventana destruida y dos monitores. Comparar MRU/foco real y probar navegación sin ratón; mantener fallback explícito si hook está desactivado por regla del usuario.


#### U04 — Implementar selectores, color y operaciones de archivo propios

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** U01, P08, P09, R04.

**Fuentes y archivos iniciales:** ii: host/src/fileops.cpp, switchwall.cpp, desktop.cpp; PhotoWidget/WallpaperSelector/DesktopMenu; nuevo: picker/progreso QML compartido.

**Problema o finalidad:** FileDialog, ChooseColorW, IContextMenu, SHMultiFileProperties y IFileOperation con UI pueden introducir diálogos Windows.

**Implementación requerida:**

Crear picker ii compartido con directorio actual, breadcrumbs, búsqueda acotada, filtro MIME/extensión, multi-select según acción, recientes y rutas pegadas. Soportar Known Folders, UNC y nube sin hidratar solo por preview. Picker de color reutiliza tokens y cuentagotas existente.
Operaciones frecuentes usan backend Windows con UI nativa suprimida donde la API lo soporte, progress sink y modelo ii de colisiones, permisos, cancelar, parciales/reintentar y papelera. No deshabilitar consentimiento protegido ni pretender que un flag resuelve todos los errores. Menú propio cubre abrir/cortar/copiar/pegar/renombrar/eliminar/propiedades básicas/abrir con apps soportadas. Menús extensiones de terceros opt-in identificados; no prometer recrear owner-drawn.

**Criterios de aceptación:**

- Foto/fondo/color/operación habitual no abre un diálogo ajeno a ii.
- Colisiones y errores no pierden datos ni reportan operación completa parcialmente fallida.
- Teclado/foco/lector y rutas Windows reales funcionan; cancelación es verificable.

**Pruebas y evidencia:**

Nombre acentuado/apóstrofo, ruta larga/UNC, nube offline, permisos, destino lleno, colisión, cancelación y reciclaje. Verificar bytes/archivos reales y progreso. Usar archivos fixture, nunca reorganizar datos personales para la prueba.


#### U05 — Sustituir tiles de sistema con controles y límites reales

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** U01, P10.

**Fuentes y archivos iniciales:** ii: tools/port/patch_ii_sidebar.py/settings.py, host/src/sidebar.cpp, brightness.cpp, nightlight*; overlay sidebarRight.

**Problema o finalidad:** Varias acciones abren Ajustes aunque existe OSK propio; otras tienen capacidad parcial de audio/red/energía/display.

**Implementación requerida:**

Hacer tile teclado abrir OSK ii existente; modo juego activar perfil ii; audio mostrar endpoints/roles/sesiones y resultados; red/Bluetooth abrir panel propio con estado y acciones reales. Luz nocturna gamma SDR solo donde soportada: HDR/unsupported debe informar, no cambiar un toggle ficticio.
Pantallas: ofrecer modos/topología soportados con preview y reversión por timeout propuesto de 15 s; no imponer DPI/reinicio sin informar restricciones. Energía: listar planes/perfiles que realmente existan, sin fallback ms-settings. Cuentas/Hello/Windows Update avanzados tienen límites explícitos, no formularios engañosos. Mantener llamadas privilegiadas como excepción visible.

**Criterios de aceptación:**

- Cada tile normal conduce a un panel ii y confirma su resultado.
- Estado desconocido/error es distinto de apagado/no hardware.
- Cambio display fallido o no confirmado revierte sin dejar al usuario sin imagen.

**Pruebas y evidencia:**

Adaptador ausente, endpoint cambiado, Bluetooth pairing/PIN, WMI/DDC soportado/no soportado, HDR y modos display fixture/reales. Validar timeout de display en equipo de prueba. No modificar planes/políticas del usuario para acreditar un toggle.


#### U06 — Controlar menús propios y recuperación sin mensajes ambiguos

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** U01, R02, R05.

**Fuentes y archivos iniciales:** ii: DesktopMenu.qml, DockContextMenu.qml, SysTrayItem.qml, host error paths; qs: tray.cpp; nuevo: rescate mínimo independiente.

**Problema o finalidad:** Menús Shell/tray y MessageBox del host pueden aparecer; no todas las acciones de una app ajena tienen representación pública.

**Implementación requerida:**

Unificar popup/menu/confirmación de las superficies ii: foco, Escape, selección teclado, cierre fuera y estilo. Exponer acciones estándar del tray donde la API lo permita; para menús propietarios declarar límite y ofrecer apertura explícita. No reescribir ni inspeccionar sin contrato el owner-drawn de otra app.
Diseñar rescate mínimo independiente del proceso QML principal con reintentar/abrir diagnóstico/restaurar/salir. Debe funcionar ante QML inválido o host degradado y dejar siempre acceso utilizable. Si esa UI mínima falla, restaurar Explorer es más importante que esconder toda señal Windows.

**Criterios de aceptación:**

- Menús de ii nunca delegan silenciosamente el diseño al Shell.
- Límite de una app de bandeja queda visible y no se pierde acceso a sus funciones.
- Error fatal no deja escritorio atrapado porque el diálogo dependía de QML fallido.

**Pruebas y evidencia:**

Tray apps con menús estándar/owner-drawn, teclado, clic fuera, elevadas/no elevadas y proceso que desaparece. Inyectar QML inválido y recursos del rescate faltantes. Verificar restauración y que el fallo no genera spam de mensajes.


#### U07 — Mantener accesibilidad en todas las superficies reemplazadas

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** U01.

**Fuentes y archivos iniciales:** ii/up: componentes common, launcher, overview, picker, settings, widgets y diálogos nuevos.

**Problema o finalidad:** Reemplazar UI Windows puede reducir funciones de teclado/lectura si se evalúa solo apariencia.

**Implementación requerida:**

Definir focus order, roles/nombres Accessible, foco visible, Escape/cancelar, activación Enter/Space y restauración del foco de origen. Aplicar texto grande, contraste suficiente y reducir movimiento global a widgets/overlays/fondos propios sin preferencias dispersas. No depender del color como único indicador de error.
No interceptar Narrador/lupa/dictado para dejarlos inútiles. Mostrar herramienta propia solo si existe equivalente; preservar una salida de accesibilidad explícita al sistema. Probar OSK, touch y zoom con targets adecuados. Los diálogos propios deben conservar lectura de ruta/progreso/errores.

**Criterios de aceptación:**

- Flujos esenciales completables sin ratón.
- Lector anuncia controles y estados significativos.
- Texto grande/alto contraste/reducir movimiento no recorta acciones ni mantiene animación oculta.

**Pruebas y evidencia:**

Navegación completa y lector real, 200 % texto, alto contraste, reducción de movimiento, picker multiselect, Alt+Tab y error de archivo. Evaluación manual de accesibilidad registrada; no darla por pasada por existir propiedades Accessible.


#### U08 — Sincronizar estética de bloqueo hasta el límite soportado

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** R03, R08, U01.

**Fuentes y archivos iniciales:** ii: lock patch, wallpaper/session services; qs: sesión WTS; nuevo: integración imagen lock por usuario.

**Problema o finalidad:** El usuario desea lock propio; el contrato actual no crea una superficie segura QML. Prometerlo sería incorrecto.

**Implementación requerida:**

Implementar transición ii que acompaña la solicitud/retorno real sin retrasar bloqueo. Investigar la API de imagen de bloqueo disponible en la edición/build/paquete real y exponer capacidad; guardar imagen estática optimizada y propiedad de preferencia cuando sea modificable/restaurable. Si políticas impiden cambio, explicar dentro de ii y conservar configuración previa.
Fondo externo utiliza snapshot/preview estático obtenido al seleccionar, con W03; no captura continua ni animación en escritorio seguro. Credenciales, reloj/UI dibujados por Windows y SAS quedan fuera. Retirar cualquier formulario PAM/Polkit placeholder de una ruta que aparente autenticar Windows.

**Criterios de aceptación:**

- La UI describe honestamente transición/imagen sincronizada, no login QML.
- Lock real nunca depende de renderizar ni de un timer decorativo.
- Denegación no altera políticas y cambios propios restauran cuando corresponde.

**Pruebas y evidencia:**

API/política permitida y denegada, imagen ausente/corrupta, Win+L directo, bloqueo ii, desbloqueo y proveedor externo. Comprobar imagen efectiva y WTS. Un overlay privacidad opcional no se etiqueta secure ni sustituye esta tarea.


#### U09 — Completar notificaciones, OSD y entradas fuera del teclado

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** R01, U01, U02, P10.

**Fuentes y archivos iniciales:** qs: notifications.cpp, tray.cpp, keyboardlayout.cpp, native input; ii: barra, notificaciones, OSD, clipboard/emojis.

**Problema o finalidad:** Historial inicial, DND, acciones de aviso, OSD doble y gestos/IME pueden romper la coherencia aunque los atajos simples funcionen.

**Implementación requerida:**

Poblar centro con avisos existentes sin mostrar todos como nuevos popups. Separar DND propio y estado sistema accesible; verificar APIs reales, no asumir que un registro privado ofrece sincronización universal. Acciones de toast solo cuando exista destino público/real; no reconstruir botones privados con clicks simulados.
Unificar OSD volumen/brillo/micro y política de supresión donde se soporte, declarar OSD fabricante no controlable. Auditar touchpad/touch/bordes/botones OEM; no fingir que el hook los cubre. Conservar clipboard/emojis implementados y comprobar foco/paste/cancelación, límites de formatos/historial y layout/IME. No suprimir composición IME o recuperación accesible para ocultar Windows.

**Criterios de aceptación:**

- Inicio no genera avalancha de popups viejos.
- DND/OSD reflejan capacidades reales y sin doble notificación en escenarios soportados.
- Paste/emoji/layout conservan foco y no producen teclas pegadas o entrada duplicada.

**Pruebas y evidencia:**

Avisos nuevos/viejos/rich/acciones, permiso perdido, DND, volumen por teclas/hardware, HDR brillo, IME y múltiples HKL; gestos reales si hay equipo. Registrar superficies Windows inevitables o aún pendientes por dispositivo, sin prometer aislamiento universal.


#### C12 — Corregir pin, idiomas y rutas Linux residuales vivas

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** U01, B00.

**Fuentes y archivos iniciales:** up: SidebarLeft.qml togglePin, services/Translation.qml; ii: parches/sidebar/translation y HyprlandXkb.

**Problema o finalidad:** togglePin usa hyprctl cursorpos y el scanner de traducciones sigue invocando find/basename Unix.

**Implementación requerida:**

Pin debe modificar estado QML directamente y preservar foco/posición sin mover cursor ni invocar compositor. Enumerar JSON de traducciones mediante Qt/native folder APIs, normalizar locale y fallback; mantener español/variantes donde existan. Missing keys usan fallback legible y log una vez; cambios de idioma no recargan todos los servicios.
Auditar consumidores Linux activos listados en B00: retirar init sin consumidor, adaptar comandos tipados o declarar unsupported. Corregir warnings por undefined/null de forma puntual; no silenciar todos los logs. Actualizar settings/inventario según rutas efectivas, no textos heredados.

**Criterios de aceptación:**

- Pin funciona con mouse/teclado sin shim cursorpos.
- Selector idioma muestra archivos reales y no depende de find.exe Unix.
- Config vieja no reactiva proceso Linux inexistente ni warning repetido sin fin.

**Pruebas y evidencia:**

Pin/unpin rápido, teclado/foco, idioma válido/ausente/malformado, es-CO/es-MX fallback según archivos disponibles y cambio en caliente. Staging desde cero y scan de rutas residuales con lista de excepciones justificadas.


#### D01 — Versionar configuración, last-good y export/import portable

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** U01, R04, R08.

**Fuentes y archivos iniciales:** ii: configuración/editor/widgets y loader de config; qs: src/io/fileview.cpp QSaveFile existente.

**Problema o finalidad:** Escritura atómica ya está activa, pero no resuelve config inválida, migración fallida ni import de datos de otra máquina.

**Implementación requerida:**

Definir schema/version y validar tipos/rangos antes de cargar. Migrar conservando copia anterior; archivo inválido se preserva y se ofrece last-good/default temporal. Guardar last-good solo tras carga validada/escritura exitosa, no por tick. Separar config portable de ownership manifest externo.
Exportar tema/widgets/atajos/perfiles sin claves/chats/avisos/tokens/temp por defecto. Import preview/merge/conflictos y mapea monitores/rutas; nunca ejecutar scripts ni escribir fuera de dirs propios desde un pack. Aplicar tamaño/rango/path limits y atomía existente. Dos escritores requieren resolución/serialización sin perder cambios silenciosamente.

**Criterios de aceptación:**

- Export/import conserva datos portables y excluye secretos sentinel.
- Corrupción/disco lleno no reemplaza config activa por parcial.
- Monitor/ruta ausente tiene recuperación y cancel import no deja cambios.

**Pruebas y evidencia:**

Schema antiguo, tipos/rangos inválidos, archivo truncado, last-good ausente, permisos/disk full, dos writers, cancel y pack/path traversal si se admiten. Verificar archivos actual/backup y recuperación; no afirmar que QSaveFile estaba ausente.


### Fase 5: Fondos externos y Fastfetch


#### W01 — Etapa A: coexistencia de fondo externo y capas ii

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** CORE. **Dependencias:** R02, U01, P07.

**Fuentes y archivos iniciales:** ii: wallpaper/background/desktop services y host/src/desktop.cpp; qs: panel windows/native.cpp; nuevo: contrato de proveedor.

**Problema o finalidad:** Wallpaper Engine/Lively no tienen soporte integrado. El problema inicial es z-order/WorkerW/hit testing, no solo enviar pause.

**Implementación requerida:**

Crear proveedor estático existente más adaptadores externos detectados, con estado por identidad estable de monitor. Cuando proveedor externo renderiza, ii no dibuja wallpaper opaco encima ni reproduce/captura su video de nuevo: mantiene widgets/iconos interactivos sobre la capa correcta. Definir orden y ownership de HWND/WorkerW, actualización al recrearse Explorer y exclusión de fuentes propias para evitar feedback.
Permitir configuración/reversión dentro de ii. No instalar/comprar proveedor, tocar cuenta Steam ni inyectar código. Si no está disponible, usar fondo estático y explicación. Probar coexistencia antes de añadir catálogo, playlist o recolor.

**Criterios de aceptación:**

- Fondo externo visible con widgets/iconos ii y clics que llegan al destino correcto.
- Fullscreen/cobertura por monitor funcionan sin ocultar otra pantalla.
- Salir/restaurar no mata procesos externos ni cambia preferencias ajenas indiscriminadamente.

**Pruebas y evidencia:**

Wallpaper Engine y Lively disponibles, single/dual-monitor, arrastre/widget edición, menú escritorio, fullscreen, provider exit y Explorer restart. Registrar z-order e input real; captura bonita sin interacción no acredita etapa A.


#### W02 — Etapa B: detectar proveedores y seleccionar proyectos desde ii

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** W01, P08, P09, U04.

**Fuentes y archivos iniciales:** nuevo: adaptadores Wallpaper Engine/Lively y biblioteca QML; ii: selector wallpaper existente.

**Problema o finalidad:** Faltan descubrimiento de instalación real, catálogo local y selección coherente por pantalla.

**Implementación requerida:**

Detectar Steam/bibliotecas y variantes Lively Store/standalone sin una ruta del autor. Consultar versión/capacidades; contrastar CLI con documentación oficial vigente de esa versión. Parsear metadata/preview local con schema tolerante y límites; catálogo asíncrono, lazy thumbnails, filtros y favoritos. Sin descargas Workshop ni compras automáticas.
Ejecutar comandos con argumentos tipados y quoting correcto, sin shell concatenada. Registrar solicitud, esperar confirmación/consulta de estado cuando exista y tratar exit 0 como aceptación si no acredita el resultado. Mapear monitor estable a identificador del proveedor y revalidar tras hotplug. No anunciar pausa por monitor si solo hay control global.

**Criterios de aceptación:**

- Elegir proyecto local desde ii cambia el monitor esperado y actualiza estado real.
- Rutas con espacios/Unicode funcionan sin ejecutar contenido de metadata.
- Versión no compatible o proveedor ausente da error propio y fallback estático explícito.

**Pruebas y evidencia:**

Bibliotecas Steam fuera de C:, projects corruptos/desaparecidos, provider ocupado/no ejecutándose, Store/standalone y monitores reordenados. Tests de quoting con caracteres especiales fixtures. Confirmar comandos reales de versiones usadas; mocks no acreditan integración comercial.


#### W03 — Etapa C: paletas, pausa, batería, audio y snapshot lock

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** W02, P05, P16, R08, R03.

**Fuentes y archivos iniciales:** nuevo: política/paleta proveedor y snapshots; ii: Material You, DesktopCover, session/profile services.

**Problema o finalidad:** Una integración sin política puede recalcular colores/capturar cada frame, pausar todos los monitores o cambiar preferencias ajenas.

**Implementación requerida:**

Usar preview representativa primero; si hace falta, obtener un snapshot al seleccionar/terminar transición con timeout y sin contenido UI propio. Cachear paleta por proyecto/variante/mtime/monitor cuando relevante; aplicar cambios de colores coalescidos. Actualización continua solo opt-in lenta con umbral, nunca recolor por frame.
Coordinar pausa/cobertura/fullscreen/lock/batería/RDP con capacidades y política previa del proveedor. No enviar global pause por un monitor cubierto si otro visible necesita reproducción; definir fallback global explícito. Guardar estado previo y restaurar solo cambios propios. Exponer mute/volumen donde soporte y decidir si espectro incluye audio del wallpaper. Snapshot estático conecta con U08.

**Criterios de aceptación:**

- ii no añade reproducción/captura continua al proveedor.
- Transiciones/perfil/lock restauran play/pause de forma consistente sin pisar al usuario.
- Colores permanecen estables y snapshot no incluye paneles/avisos de ii.

**Pruebas y evidencia:**

Proyecto animado/audio, dual visible/cubierto, pause manual antes/durante ii, batería/AC, lock/resume y RDP. Medir consumo ii/DWM/proveedor separado y número de capturas/recolor. Comprobar política limitada de comandos globales y ausencia de estado que oscile entre dos controladores.


#### W04 — Etapa D: playlists/propiedades y recuperación del proveedor

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** W03, R07.

**Fuentes y archivos iniciales:** nuevo: adapters/profile controls; ii: wallpaper selector y ciclo Explorer/monitor.

**Problema o finalidad:** Playlists/perfiles y cambios de provider pueden dejar selección obsoleta, capa negra o workers huérfanos.

**Implementación requerida:**

Añadir playlists, siguiente/anterior y propiedades solo cuando la CLI/capacidad instalada lo permita. Identificar propiedad editable, tipo/rango/default y versión; preview/cancelar debe restaurar lo cambiado. No presentar todos los campos de metadata como configurables.
Reconciliar provider crash/update, WorkerW nuevo, display hotplug y D3D device lost. Rehacer únicamente ventanas/registros propios; static fallback rápido preserva widgets/config. Retener selección por monitor ausente sin aplicarla al que herede su índice. Limitar reintentos y explicar degradación, sin arrancar en bucle el programa externo.

**Criterios de aceptación:**

- Playlist/propiedades producen estado comprobable o error propio.
- Reinicio Explorer/proveedor no deja pantalla negra persistente.
- Monitor reconectado recupera su configuración sin robar otra.

**Pruebas y evidencia:**

Provider crash y versión incompatible, Explorer restart, GPU reset donde sea reproducible, hotplug/rotación, property inválida y playlist vacía. 100 cambios de proyecto con métricas de handles/memoria. No alterar configuración externa no propiedad de ii.


#### F01 — Cambiar logo Fastfetch y dejar de imponerlo desde el wrapper

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** CORE. **Dependencias:** B00.

**Fuentes y archivos iniciales:** ii: extras/fastfetch/ii-logo.txt, ii.jsonc, fastfetch.cmd y instalación/perfiles Windows Terminal.

**Problema o finalidad:** El logo es una chispa/cruz de bloques Unicode con marcador de color $1; el wrapper fuerza --logo y puede anular cambios en JSON.

**Implementación requerida:**

Crear default textual compacto claramente legible como «ii», con variante simple si Unicode/color no funciona. El monograma es una propuesta inicial razonable; no atribuir al usuario una mascota/imagen aprobada. Conservar módulos útiles y mejorar nombre/versión del port sin falsear la identificación del sistema.
Definir precedencia: opciones explícitas del usuario > configuración seleccionada > default instalado. Wrapper resuelve rutas propias y no fuerza siempre el logo viejo; validar help y paso de argumentos. PNG/Sixel queda opción explícita según capacidad real de Fastfetch/terminal, no obligación ni supuesto universal. Mantener perfiles de Terminal existentes y no editar globalmente AutoRun/perfiles de PowerShell que ralenticen scripts.

**Criterios de aceptación:**

- Un vistazo al logo default permite reconocer ii.
- Cambiar logo en config o CLI funciona, sin override silencioso.
- Fastfetch ausente/error no impide abrir una terminal normal ni genera bucle.

**Pruebas y evidencia:**

CMD/PowerShell, Windows Terminal/host clásico, espacios/Unicode en instalación, color/plain y override CLI/config. Revisar visualmente alineación legible; comprobar perfiles previos preservados. No requiere generar ni elegir una imagen AI para completar la variante textual.


### Fase 6: Paridad funcional


#### C01 — Completar captura de pantalla y anotación dentro de ii

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** U01, U04, P08.

**Fuentes y archivos iniciales:** ii: host/src/capture.cpp, overlay/ii/modules/common/utils/ScreenshotAction.qml, TempScreenshotProcess.qml; nuevo: anotador.

**Problema o finalidad:** Captura/recorte ya existen, pero edición abre app externa y círculo visual no garantiza máscara de salida.

**Implementación requerida:**

Unificar shortcut/tile/launcher en captura ii con región, monitor, copiar y guardar. Aplicar coordenadas físicas/DPR y orientación correctas; círculo produce alpha real en formato compatible y opción explícita para fondo en formato opaco. Añadir anotador bajo demanda: recrop, flechas, formas, texto, blur/máscara y undo/redo, sin abrir Paint automáticamente.
Conservar original durante edición, escribir salida atómicamente y mostrar errores/cancelación. Blur para ocultar datos debe producir píxeles realmente transformados, no una capa decorativa separada en export. Portapapeles y archivo resultantes deben corresponder a preview.

**Criterios de aceptación:**

- Cada entrada usa selector/anotador ii y archivo/copy correctos.
- Deshacer/rehacer/cancelar no destruye original.
- Export círculo/blur contiene resultado real, comprobado fuera del editor.

**Pruebas y evidencia:**

Multi-monitor/DPI negativo, PNG alpha/JPEG, ruta inválida/llena, cancelar y clipboard pegado en fixture. Comparar píxeles/crop dimensions y aplicar anotaciones/undo. No capturar contenido personal ni subir imágenes para demostrar el flujo.


#### C02 — Implementar fuente screen para OCR/traducción sin confundir DWM

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** C01, R03.

**Fuentes y archivos iniciales:** qs: src/win32/compat/wayland.cpp/.hpp, screenSource/ScreencopySurface; ii: capture/OCR.

**Problema o finalidad:** Miniatura DWM dibujada sobre Qt no es una textura screenSource; hoy el contrato admite menos fuentes de las que asume el original.

**Implementación requerida:**

Definir adaptador de captura de imagen con WGC o Desktop Duplication según API/versión soportada. Entregar imagen/texture realmente consumible, identidad fuente, dimensiones físicas, timestamp y estado/error; política de cursor explícita. Capturar a demanda para OCR y mantener recursos solo si un consumidor continuo real lo pide.
Tratar ventana protegida, minimizada, pantalla bloqueada, permiso/capacidad HDR y device lost con resultado claro; no devolver negro como éxito OCR. Detectar idiomas/engine Windows OCR instalados y explicar ausencia; no instalar Python/Tesseract automáticamente.

**Criterios de aceptación:**

- Fuente screen/region devuelve píxeles correctos y sus coordenadas.
- Contenido protegido/no disponible falla de forma visible y acotada.
- Cerrar/cancelar libera captura/D3D sin poll continuo.

**Pruebas y evidencia:**

Monitor/ventana/región, DPR mixto, rotate/HDR, fuente desaparecida, lock y salida OCR en idiomas instalados. Fixture de error y texto conocido; Windows real para acreditar API/píxeles. Documentar limitaciones de minimizadas/protected content.


#### C03 — Grabar video y audio con un backend Windows completo

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** C02, P16, U04.

**Fuentes y archivos iniciales:** ii: host/src/capture.cpp y acción crop record; nuevo: recorder/encoder y UI de estado.

**Problema o finalidad:** Los scripts/rutas de grabación no forman un pipeline operativo con audio, mux, stop y recuperación.

**Implementación requerida:**

Implementar región/monitor con captura soportada y encoder Media Foundation o FFmpeg como dependencia explícita y versionada. Elegir codec/container/FPS/calidad y hardware encoding por capacidad, con fallback medido. WASAPI loopback/micro seleccionables, timestamps compartidos y sincronización A/V; mostrar indicador propio siempre mientras graba.
Estados idle/preparing/recording/paused si soportado/stopping/error. Stop finaliza container y libera recursos; error/cierre conserva recuperación del archivo parcial cuando técnicamente posible. Manejar resize/display removal/device lost/lock por política documentada sin continuar capturando sesión protegida. Nunca iniciar grabación por abrir overlay.

**Criterios de aceptación:**

- Archivo reproducible contiene región/audio elegidos, duración y sincronía correctas.
- Cancelar antes de iniciar no crea un archivo engañosamente exitoso.
- Stop/error deja recursos liberados y resultado recuperable o error explícito.

**Pruebas y evidencia:**

Grabación corta/larga de fixture con reloj/sonido sincronizado, mic on/off, disco lleno, stop rápido, crash controlado, hotplug y lock. Verificar archivo con herramienta independiente y drift A/V; no marcar hardware encoding validado sin usarlo. Probar consumo/frames también con UI cerrada.


#### C04 — Completar búsqueda por imagen y traducción de pantalla

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** C02, R11, U01.

**Fuentes y archivos iniciales:** ii: capture/search, trans.cpp, http/airequest; QML traductor/overlay; scripts Cloud heredados.

**Problema o finalidad:** crop search/Lens y rutas Cloud/OAuth no tienen un recorrido Windows completo. Traducción de texto existente no equivale a traducción de pantalla.

**Implementación requerida:**

Separar OCR local, traducción de texto y subida/búsqueda de imagen como acciones/proveedores distintos. Elegir adaptador documentado, autenticación real y límites; para Google Cloud investigar OAuth/JWT/HTTP con bibliotecas nativas y no fingir soporte sustituyendo una URL. Exigir acción explícita antes de enviar píxeles/texto e identificar destino.
Mapear bloques OCR y traducciones a coordenadas físicas y overlay ii; busy/cancel/error/rate limit y offline. Mantener proveedor Google de texto que ya funciona; nuevos engines/offline solo si hay implementación real seleccionada. No crear un venv por cada búsqueda ni descargar modelos sin alcance.

**Criterios de aceptación:**

- Recorte elegido llega al proveedor seleccionado solo al confirmar la acción.
- Cancelar no deja uploads/reintentos ilimitados.
- Traducción overlay mantiene posiciones y muestra error real si faltan credenciales/idioma/proveedor.

**Pruebas y evidencia:**

Fixtures HTTP/OAuth, chunk/timeout/429, texto vacío y bloques DPI mixto; proveedor real solo con credenciales y autorización disponible. No afirmar Lens/Cloud validado por construir enlace. Documentar costes/requisitos como pendientes si no hay cuenta.


#### C05 — Completar comandos Windows y calculadora avanzada del launcher

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** P13, U01.

**Fuentes y archivos iniciales:** ii: host/src/shim.cpp, launcher/custom actions; nuevo: proveedores Windows/cálculo.

**Problema o finalidad:** El shim bash solo cubre subconjunto y qalc es básico. Ejecutar .ps1 como .exe o concatenar texto Shell no equivale a un proveedor correcto.

**Implementación requerida:**

Separar búsqueda, cálculo y ejecución explícita. Comandos especifican intérprete PowerShell/cmd, argumentos, cwd y modo consola; usar APIs/procesos con quoting propio de Windows e intérprete según extensión. No ejecutar al escribir, no instalar WSL ni interpretar todo como bash. Cancelar solo el proceso/árbol lanzado; comunicar salida, código y timeout.
Calculadora avanzada requiere engine seleccionado y probado para unidades/conversiones/errores. Monedas distinguen cotización cacheada/fecha y necesitan proveedor si se adoptan; offline conserva último dato y no promete precio actual. No descargar dependencias/red para una suma simple.

**Criterios de aceptación:**

- Rutas/args especiales se ejecutan como los valores solicitados, sin inyección accidental.
- Scripts admitidos usan intérprete correcto; formatos no soportados informan.
- Cálculo devuelve unidades/error coherente y query vieja no pisa resultado actual.

**Pruebas y evidencia:**

Rutas con espacios, comillas, apóstrofo, ampersand, Unicode, cwd y script que falla/cuelga; fixtures sin datos reales. Cálculos dimensionales correctos/incorrectos, cero division, cotización offline y generación de consultas. Revisar no ejecución automática de sugerencias.


#### C06 — Añadir búsqueda de archivos/ventanas indexada y a demanda

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** P13, U04, P08.

**Fuentes y archivos iniciales:** ii: LauncherSearch/AppSearch adaptados; nuevo: proveedor Windows Search y ventanas.

**Problema o finalidad:** El launcher busca apps pero no tiene un proveedor Windows Search completo. Un scan de todo el disco al iniciar dañaría arranque y reposo.

**Implementación requerida:**

Integrar índice Windows Search con consultas acotadas/paginadas, cancelación, acceso autorizado y resultados virtualizados. Mostrar origen/fecha/tipo y abrir/previsualizar mediante acciones del catálogo. Fallback si índice ausente: búsqueda limitada a carpetas elegidas, con límite de profundidad/tiempo y progreso; no rastrear todo perfil/unidades en background.
Añadir ventanas desde el tracker ya existente sin segundo EnumWindows. Mantener recientes/frecuencia opcionales con borrado y exclusiones; no filtrar paths privados a logs/report.

**Criterios de aceptación:**

- Query devuelve resultados actuales y respeta cancelación/limitación.
- No hay scan global al logon ni hidratación de nube por preview.
- Índice deshabilitado/offline da estado/fallback propio y no una lista vacía engañosa.

**Pruebas y evidencia:**

Servicio Search activo/desactivado, índice grande, acceso denegado, UNC, nube, ruta movida y query rápida. Medir tecla→resultado y coste idle; verificar click/Enter abre el path/ventana correcto sin cargar todos los thumbnails.


#### C07 — Validar IA existente, streaming y herramientas Windows

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** R11, P06, U01.

**Fuentes y archivos iniciales:** ii: host/src/airequest.cpp, tools/port/patch_ii_ai.py; up: servicios/proveedores IA y QML tabs.

**Problema o finalidad:** POST/streaming y DPAPI existen, pero falta demostrar cada proveedor, cancelar correctamente y eliminar supuestos Linux/null iniciales.

**Implementación requerida:**

Definir matriz proveedor→endpoint/auth/modelos/stream/tools/errores; proteger acceso a modelo/strategy inicialmente indefinidos. Parsear SSE/NDJSON por bytes, UTF-8 fragmentado, eventos parciales y backpressure; limitar cuerpo/tiempo y descartar respuestas de chat cerrado. Ollama descubre /api/tags nativamente y distingue server inaccesible/modelo ausente.
Adaptar herramientas a acciones tipadas Windows con validación, alcance, cancelación y el flujo de aprobación existente; no ejecutar bash arbitrario ni eliminar autorización de tool calls. Get/set config usa schema y escritura atómica/rollback. Mostrar errores auth/rate-limit/network sin contaminar historial con un éxito falso.

**Criterios de aceptación:**

- Streaming no pierde Unicode/eventos y cancelar termina transporte.
- Proveedor/modelo no disponible se comunica sin crash ni loop.
- Tool call no ejecuta acción sin su autorización requerida y falla si argumentos no válidos.

**Pruebas y evidencia:**

Fixtures OpenAI/Gemini/Mistral/Ollama según adapters elegidos: chunks, 401/429, disconnect, NDJSON, tool args inválidos y cancel. Integración real solo con cuenta disponible y solicitud autorizada. Informar cobertura exacta; no prometer todos los proveedores por un POST genérico.


#### C08 — Añadir adjuntos y render de chat sin trabajo innecesario

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** C07, U04, P09.

**Fuentes y archivos iniciales:** ii: UI/servicios IA, airequest/multipart; nuevo: renderer syntax/LaTeX opcional.

**Problema o finalidad:** Adjuntos se rechazan explícitamente y parte de highlighting/LaTeX es placeholder. Render pesado puede arruinar scroll o arranque.

**Implementación requerida:**

Adjuntos por capacidad del proveedor: MIME/tamaño/número validado, preview local, remove/cancel y upload multipart/resumible cuando la API lo requiera. Secretos fuera de temp/args; cleanup y límites de retención. No presentar attachment como enviado hasta confirmar la operación.
Syntax highlighting real incremental y seguro para texto no confiable; cargar renderer solo al necesitarlo y virtualizar conversaciones largas. LaTeX se considera subentregable opcional con engine nativo/bundled compatible y límites, no ejecutar scripts HTML/web. Mantener fallback texto legible si renderer no disponible.

**Criterios de aceptación:**

- Provider que no soporta adjunto no ofrece upload engañoso.
- Cancelación/error no deja temporales sensibles o UI eternamente busy.
- Chat largo con code/math no bloquea input/scroll y el contenido no ejecuta código.

**Pruebas y evidencia:**

MIME falso/extensión engañosa, archivo grande/borrado/locked, provider sin capacidad, cancel upload y respuestas code/math malformadas. Medir scroll/RAM con chat fixture largo. No descargar engine/modelos ni usar credenciales reales por defecto.


#### C09 — Conservar widgets/iconos por monitor y normalizar telemetría

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** P03, P07, P14, R08.

**Fuentes y archivos iniciales:** ii: DesktopIcons/FolderWidget, editor/widgets/resources; host/src/desktop.cpp; qs: battery/display/models.

**Problema o finalidad:** Ubicación de iconos/layout puede depender de índices/pantalla actual; Public Desktop usa suposición de ruta y algunos datos desconocidos se muestran como reales.

**Implementación requerida:**

Guardar layout por identidad estable de monitor con esquema migrable, coordenadas normalizadas o físicas bien definidas y clamp de área útil. Restaurar al reconectar; ofrecer reset/bring-into-view y no duplicar todos los iconos por monitor sin política. Usar Known Folders para desktop usuario/público y respetar redirección/OneDrive. Mostrar estado cut según formatos clipboard compatibles.
Recursos: etiquetar RAM física/commit/swap correctamente; salud de batería/sensor desconocido es desconocido, no 0/100 % inventado. GPU/temperaturas opcionales requieren proveedor real y solo sondeo visible/budget. No añadir driver/kernel ni servicio privilegiado para decorar un widget.

**Criterios de aceptación:**

- Cambio monitor/DPR no pierde widgets ni los deja fuera de alcance.
- Carpetas redirigidas muestran los datos correctos sin copiar/mover originales.
- Valores/soporte de sensores se distinguen de una lectura válida de cero.

**Pruebas y evidencia:**

Dual-monitor reordenado/desconectado/rotado, resolución menor, perfil migrado, desktop OneDrive/público y cut/paste. Batería health no soportado/sensor ausente y etiquetas de memoria contra fuente Windows. Comparar estado preservado tras reiniciar.


#### C10 — Completar overview/dock con teclado y snapshots minimizados

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** P02, P07, U03, R09.

**Fuentes y archivos iniciales:** ii: overview/DesktopStrip y dock; qs: thumbnails/tracker; nuevo: cache snapshot de ventana.

**Problema o finalidad:** Ya hay foco/cierre/movimiento entre desktops, pero minimizadas y navegación necesitan un recorrido más sólido.

**Implementación requerida:**

Mantener último snapshot válido acotado para ventana que luego se minimiza, sin prometer contenido vivo de una app minimizada. Placeholder cuando no exista; purgar al destruir/cambiar identidad. Reutilizar en dock/overview/switcher sin captura duplicada y respetar contenido protegido.
Añadir navegación espacial/teclado, foco visible y selección por identidad; mover ventana confirma GUID/resultado real. Arrastrar no reconstruye listas ni cierra por stale index. Mantener por monitor/contexto seleccionado y reglas explícitas de pinned/MRU.

**Criterios de aceptación:**

- Minimizada muestra snapshot/placeholder honesto y se restaura al activar.
- Teclado puede seleccionar/focar/cerrar/mover donde sea soportado.
- Desktop/ventana desaparecida cancela operación sin afectar otro elemento.

**Pruebas y evidencia:**

Minimize sin snapshot, protected window, app cerrada mientras pointer/keyboard selecciona, 30 previews y desktops que cambian. Probar frame/memoria/handles con 100 aperturas y posición DPI/monitor mixto. No duplicar el switcher de U03.


#### C11 — Acotar galería/clima/red y preservar uso offline

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** R11, P06, P09, U01.

**Fuentes y archivos iniciales:** ii: host/src/http.cpp, weather.cpp, randomwall.cpp; parches net/p0; QML galería/clima/fondos.

**Problema o finalidad:** Proveedores/downloads necesitan cancelación/cuotas/cache; disponibilidad de un servicio externo no es una garantía del proyecto.

**Implementación requerida:**

Compartir transporte y política de red con límites de tamaño/concurrencia/tiempo/retry, HTTP status y MIME validado. Peticiones solo por consumidor/acción real; tab nunca abierto no dispara fetch. Cache con TTL/bytes y última respuesta válida; offline muestra fecha/estado, no datos inventados.
Galería/adaptadores verifican capacidades actuales, credencial DPAPI y descarga atómica a ubicación elegida. Cancelar query vieja y download parcial; validar path y formato sin ejecutar metadata. Clima separa ubicación manual/servicio autorizado y no transmite ubicación sin acción/configuración explícita.

**Criterios de aceptación:**

- Cuota/retry acotados evitan loops y descargas ilimitadas.
- Offline conserva dato útil con fecha y error visible.
- Cambiar búsqueda/tab no publica resultado viejo ni deja descarga huérfana.

**Pruebas y evidencia:**

HTTP 404/429/5xx, respuesta grande/MIME erróneo, timeout, desconexión, disco lleno y cache corrupta. Fixtures para proveedores; prueba real declarada por proveedor solo si existe acceso. Medir red startup y tab oculta.


#### C13 — Implementar inactividad/energía/actualizaciones con estados reales

**Estado inicial:** TODO. **Prioridad:** P2. **Alcance:** PARIDAD. **Dependencias:** R03, P10, P11, U05.

**Fuentes y archivos iniciales:** ii: Session.qml, battery/power settings, host shims; nuevo: idle Windows y proveedor de updates.

**Problema o finalidad:** hypridle/checkupdates Linux no equivalen a contratos Windows. Suspensión crítica ya está desactivada por defecto y debe conservarse.

**Implementación requerida:**

Usar GetLastInputInfo u API aplicable para inactividad en la sesión, con políticas AC/batería, inhibición y reglas explícitas. Bloquear antes de suspender cuando se solicite: distinguir confirmación/timeout sin fingir protección; no saltarse políticas corporativas ni requisitos de firmware. Conservar safeguard actual de batería crítica y validar lecturas.
Actualizaciones distinguen Windows Update (WUA/capacidad pertinente) de apps winget; consultar bajo demanda/cache, no instalar/reiniciar por abrir tile. Mostrar reboot requerido y límites/permisos reales. No automatizar cambio de contraseña, BIOS, servicios o descarga masiva para completar una pantalla.

**Criterios de aceptación:**

- Idle respeta actividad/inhibición y no suspende por un dato desconocido.
- Error de lock/sleep se muestra y mantiene estado coherente.
- Updates reportan proveedor/fecha/resultado; check no dispara instalación ni reboot.

**Pruebas y evidencia:**

AC/batería, lock fail, input reciente, app inhibidora, tapa/resume y firmware no soportado. Fixtures WUA/winget sin updates/error/offline y prueba consulta Windows autorizada. No probar suspensión automática en la sesión personal ni ejecutar upgrades reales.


### Fase 7: Validación y entrega


#### Q01 — Preparar paquete identificable y documentación veraz

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** VALIDACIÓN. **Dependencias:** R07, R08, P17, D01.

**Fuentes y archivos iniciales:** ii: make-package.ps1, README/PROGRESS/inventario/relevo; qs: BUILD/docs; manifests/logs.

**Problema o finalidad:** Una fuente corregida no acredita que el paquete distribuido lleve ambos cambios o dependencias correctas.

**Implementación requerida:**

Construir paquete local de revisión con pareja de commits, dirty flag, Qt/toolchain/flags, hashes y licencias de terceros. Verificar rutas/config/launch desde instalación limpia sin SDK. Actualizar inventario con estados implementado/verificado/limitado/pendiente, no porcentajes inventados. Documentar migraciones, nueva política de UI, atajos efectivos, fallbacks y rollback.
Eliminar contradicciones de ayuda/crash/upstream según P17. Incluir guía de rescate accesible fuera de QML. No subir ZIP, publicar release, PR o issue automáticamente: dejar resultado revisable si publicación no está en el encargo.

**Criterios de aceptación:**

- Paquete local corresponde a la pareja declarada y arranca sin dependencias del entorno de desarrollo.
- Docs explican límites seguros del bloqueo/COM privado/proveedores.
- Datos/secretos/cache de la máquina de build no se incluyen accidentalmente.

**Pruebas y evidencia:**

Instalar paquete en entorno limpio; inspeccionar contenido/dependencias/metadatos y ejecutar smoke/rollback. Comparar catálogo/docs contra bindings reales. Para paquete correctivo, informar alcance parcial sin atribuirle fases no ejecutadas.


#### Q02 — Ejecutar matriz integral y recuperación de largo plazo

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** VALIDACIÓN. **Dependencias:** R10, P18, U02, W03, F01.

**Fuentes y archivos iniciales:** ii/qs: harness, escenarios Windows/hardware; datos brutos de benchmark.

**Problema o finalidad:** Solo pruebas unitarias o un demo corto no acreditan coherencia, reposo y recuperación del conjunto.

**Implementación requerida:**

Ejecutar matriz del apartado 8 sobre el alcance implementado, incluyendo fault injection, multimonitor, proveedores y entrada. Repetir warm/cold según protocolo, ciclos y soak; medir diferencias y comprobar invariantes visuales/de datos. Clasificar no ejecutado por equipo/proveedor, no como PASS.
Cuando el paquete sea solo correctivo, aplicar esta misma metodología a tareas incluidas y dejar sus dependencias futuras pendientes: no alterar fichas para dar por terminado el programa completo. Resolver regresiones encontradas o bloquear promoción con evidencia concreta.

**Criterios de aceptación:**

- Resultados separan passed/failed/skipped/unverified por escenario.
- Recuperación deja escritorio útil y no datos/procesos ajenos alterados.
- Informe de rendimiento incluye distribución y recursos sostenidos, no un FPS aislado.

**Pruebas y evidencia:**

Windows real; Sandbox más hardware físico cuando corresponda. Adjuntar environment manifest, trazas/logs redactados y reproducción de fallos. Una sesión sin Wallpaper Engine, GPU híbrida o touch no certifica esos escenarios.


#### Q03 — Cerrar el trabajo con evidencia y pendientes accionables

**Estado inicial:** TODO. **Prioridad:** P1. **Alcance:** VALIDACIÓN. **Dependencias:** Q01, Q02.

**Fuentes y archivos iniciales:** nuevo: resumen de entrega/progress; ii/qs: commits y documentación.

**Problema o finalidad:** El siguiente agente necesita saber exactamente qué se corrigió y qué falta, sin heredar afirmaciones vagas de todo terminado.

**Implementación requerida:**

Actualizar cada ID trabajado con commits, pruebas, estado y evidencia. Resumir comportamiento antes/después, cambios de configuración, riesgos materiales y pasos de rollback. Listar tareas no elegidas y límites de plataforma/proveedor separados de bugs.
Entregar paquete y reporte revisables con instrucciones exactas para reproducir tests/benchmarks. Continuar los cambios independientes del alcance mientras exista trabajo autorizado; no detenerse tras un plan o una compilación. Si falta una decisión externa real, describir lo preparado y el bloqueo concreto, sin pedir confirmaciones genéricas.

**Criterios de aceptación:**

- Ninguna tarea está VERIFICADA sin evidencia requerida.
- Otra persona puede reproducir build/staging/test con versiones declaradas.
- La entrega no dice UI 100 % aislada, bloqueo QML seguro o compatibilidad universal si no son ciertos.

**Pruebas y evidencia:**

Revisión cruzada ID→cambio→prueba→paquete→doc; comprobar enlaces/paths, secrets y resultados. Validar que el resumen final refleje scope ejecutado y no toda la lista de ideas.


### Fase 8: Ideas opcionales


#### X01 — Integración opcional de tiling, zonas y scratchpad

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** U02, P07, R09.

**Fuentes y archivos iniciales:** nuevo: adaptador GlazeWM/zonas; ii: overview/window actions.

**Problema o finalidad:** Organización avanzada es viable en Windows, pero Quickshell no se convierte por ello en Hyprland ni los desktops nativos en workspaces por monitor.

**Implementación requerida:**

Elegir entre zonas propias acotadas o integración opcional GlazeWM según alcance. Un adaptador central coordina hotkeys, reglas, foco y ventanas; ii conserva barra/UI sin instalar otra barra. Fijar versión/protocolo/licencia y no duplicar un gestor ya activo.
Scratchpad conserva ventana/estado previo y restaura por identidad, sin cerrar/reabrir la app. Reglas excluyen juegos/diálogos/modal/elevadas cuando sea necesario. Si se desea workspace por monitor, diseñar modelo propio y sus límites, no etiquetar Virtual Desktop global como independiente.

**Criterios de aceptación:**

- Win+Z/zones tienen acción real dentro de ii cuando se habilita.
- Dos gestores/hotkeys no compiten por la misma ventana.
- Desactivar integración recupera el comportamiento previo sin perder apps.

**Pruebas y evidencia:**

Apps Win32/Store, elevated/UIPI, modal, resize constraints, multi-DPI, fullscreen y gestor ausente. Comparar foco/ubicación después de habilitar/deshabilitar; no instalar un gestor en el equipo del usuario por defecto.


#### X02 — Centro de archivos ii completo a partir del picker

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** U04, C06.

**Fuentes y archivos iniciales:** nuevo: navegador de archivos ii; reutilizar picker/ops/cache.

**Problema o finalidad:** Win+E solo deja de abrir Explorer como aplicación si existe un navegador suficientemente funcional; un picker no lo reemplaza.

**Implementación requerida:**

Reutilizar proveedores/modelos de U04 para navegación, tabs opcionales, recientes/favoritos, búsqueda indexada, previews, papelera y operaciones con resultado. Cargar bajo demanda, no al logon. Definir mínimo de compatibilidad: Known Folders, UNC, nube, drag/drop y archivos ocultos según elección.
Separar abrir un documento en su app de gestión del entorno. Extensiones Shell/propiedades avanzadas quedan explícitas por capacidad; no prometer paridad universal Explorer ni instalar handlers globales sin alcance.

**Criterios de aceptación:**

- Win+E abre centro ii cuando se selecciona esta ampliación.
- Operaciones comunes conservan datos y feedback propio.
- App cerrada libera sus recursos pesados y mantiene tabs/config sin secretos.

**Pruebas y evidencia:**

Recorridos de carpetas fixture, UNC/nube offline, miles de archivos, search/papelera/undo disponible y cancelación. Comparar cold open/idle/RAM. Sin este módulo, documentar Win+E como pendiente o apertura externa explícita.


#### X03 — Centro de procesos ii para acciones cotidianas

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** U01, P10.

**Fuentes y archivos iniciales:** nuevo: lista/detalle de procesos; ii: menú Win+X y Ctrl+Shift+Esc.

**Problema o finalidad:** Task Manager sigue siendo ruta Windows. Un reemplazo cotidiano puede ser ligero si no sondea a alta frecuencia estando cerrado.

**Implementación requerida:**

Enumerar procesos y métricas a demanda en worker con identidad PID+creation time. Lista virtualizada, filtros y refresh adaptable solo visible; no introspección de procesos protegidos por defecto. Ofrecer cierre normal antes de terminate, confirmación/resultado y límites de permisos.
Detalle/servicios/startup avanzado quedan fuera del MVP. Autorización del sistema si realmente requerida; no elevar la shell completa ni terminar procesos esenciales para aparentar eficiencia. Reutilizar identificación segura de R05.

**Criterios de aceptación:**

- Shortcut abre una vista ii funcional cuando está habilitada.
- Seleccionar un PID viejo no termina el proceso reutilizado.
- Cerrado no mantiene muestreo rápido de todo el sistema.

**Pruebas y evidencia:**

Proceso normal/colgado/elevado/protegido fixture, PID reuse y lista grande. Verificar cierre/terminate y error access denied. Medir consumo visible/cerrado, sin terminar apps personales ni procesos críticos.


#### X04 — Dashboard, escenas y packs con identidad Material ii

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** P06, P16, U07, W03.

**Fuentes y archivos iniciales:** nuevo: dashboard/scene model; ii: configuración/widgets/themes.

**Problema o finalidad:** Caelestia/HyDE/Noctalia sugieren acciones, perfiles y movimiento coherentes; mezclar cinco shells añadiría UI/costes innecesarios.

**Implementación requerida:**

Crear dashboard bajo demanda para favoritos, actividad y estado real. Escenas combinan tema, widgets, fondo y perfil por monitor con preview, cancelar y restauración. Packs visuales solo datos versionados/recursos acotados, sin scripts arbitrarios ni comandos Linux.
Usar tokens y componentes Material existentes, navegación/ranking de Noctalia como inspiración y transiciones coordinadas de Caelestia. No copiar código/assets sin revisar licencia. Mantener reducir movimiento global y límites de cache/instanciación.

**Criterios de aceptación:**

- Preview/cancel no deja medias configuraciones ni cambia secretos.
- Escena conserva identidad de monitor y funciona offline con recursos locales.
- Dashboard cerrado no añade polling/red permanente.

**Pruebas y evidencia:**

Pack inválido/antiguo, archivo grande, monitor faltante, preview cancelado y retorno a escena anterior. Perfilar primera apertura/idle y revisar accesibilidad. No afirmar superioridad de rendimiento respecto a dotfiles Linux.


#### X05 — Calendario conectado opcional e ICS offline

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** P11, R11, P06.

**Fuentes y archivos iniciales:** nuevo: proveedor calendario; ii: CalendarCard/calendario/tareas.

**Problema o finalidad:** Calendario/tareas locales existen; sincronización externa necesita cuenta, permisos y semántica de conflictos.

**Implementación requerida:**

Comenzar por import/subscription ICS explícita, con timezone, recurrencias y cache local acotada. Proveedor OAuth adicional separado con consentimientos/capacidades reales. Sincronizar fuera del GUI y solo para fuente configurada; indicar última sync/error.
Definir read-only o edición bidireccional antes de implementar; si read-only, no presentar cambios locales como guardados en servidor. Mantener tareas/pomodoro locales y borrado/desconexión que retire credenciales propias.

**Criterios de aceptación:**

- Eventos se muestran a hora correcta incluso offline.
- Desconectar detiene sync y no borra eventos del proveedor remoto.
- No hay acceso a cuentas por defecto ni duplicación de eventos por refresh.

**Pruebas y evidencia:**

ICS fixture con recurrencia/DST/malformado, conflictos, HTTP timeout y cache. Cuenta real solo si seleccionada/autorizada; no enviar invitaciones ni crear eventos remotos al probar.


#### X06 — API de extensiones con capacidades y presupuesto

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** U01, P06, P09, R11.

**Fuentes y archivos iniciales:** nuevo: plugin API/manifest/runtime; ii: loader y settings.

**Problema o finalidad:** Extensiones pueden ampliar el entorno, pero un proceso/timer/red por widget puede reproducir todos los problemas de rendimiento.

**Implementación requerida:**

Definir manifest versionado con recursos, permisos, capacidades, lifecycle y budget; carga solo al habilitar/mostrar. Reutilizar servicios compartidos y no permitir cada plugin sondear/redibujar todo. Aislamiento debe corresponder a la amenaza: QML en proceso no es sandbox seguro; declarar confianza o usar proceso restringido diseñado y probado.
Instalación/importación revisa licencia/integridad y no ejecuta script automáticamente. Crash/deshabilitar debe liberar recursos y restaurar layout. Mantener API pequeña, sin dar claves globales a plugins.

**Criterios de aceptación:**

- Plugin deshabilitado no mantiene timers/proceso/captura.
- Error/budget excedido tiene diagnóstico y no derriba necesariamente el entorno.
- Modelo de confianza y permisos es explícito, sin prometer sandbox inexistente.

**Pruebas y evidencia:**

Plugin fixture con loop/IO/error/resource leak y manifest incompatible. Medir aislamiento/shutdown y límites; no instalar extensiones externas desconocidas para probar la arquitectura.


#### X07 — Instalador/actualizador gráfico con rollback reutilizado

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** R07, R08, P17, U07.

**Fuentes y archivos iniciales:** nuevo: frontend instalación/update; ii: herramientas package existentes.

**Problema o finalidad:** Una UI gráfica puede completar identidad ii, pero no debe introducir un segundo motor de instalación con semántica distinta.

**Implementación requerida:**

Frontend ii llama el backend transaccional existente, muestra progreso, permisos, datos preservados y rollback. Check de update identifica canal/versión/commits/hashes; descargar en staging, verificar integridad y activar con R07. Firma solo si proyecto dispone de material/proceso real; no declarar firmado por incluir un campo.
Separar check, download y install/restart; no actualizar al abrir settings sin elección. UAC queda excepción. Mantener acceso al modo consola/rescate cuando frontend no arranque; no publicar ni cambiar canal por defecto sin alcance.

**Criterios de aceptación:**

- UI y scripts generan idéntica propiedad/restauración.
- Paquete corrupto/incompatible no reemplaza runtime operativo.
- Actualización interrumpida tiene vuelta atrás probada.

**Pruebas y evidencia:**

Instalación limpia/upgrade/cancel, offline/hash errado, disco lleno, permiso denegado y nuevo runtime fallido. Usar paquetes fixture/locales; no subir releases ni consumir certificados automáticamente.


#### X08 — Reconocimiento de canciones y letras optativos

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** P05, R11, U01.

**Fuentes y archivos iniciales:** nuevo: song recognition/provider; ii: media UI.

**Problema o finalidad:** La ruta songrec Linux no es un backend Windows completo y los servicios de reconocimiento/letras pueden tener requisitos/licencias.

**Implementación requerida:**

Capturar muestra WASAPI explícita y acotada, seleccionar proveedor real y documentar condiciones/coste/capacidad. No grabar micrófono ni subir audio por mostrar un widget. Cancelación detiene captura/request y borra temporales; cache de resultados por identidad.
Letras solo si fuente permitida/seleccionada, con indicador de disponibilidad y sincronía cuando exista. Reutilizar media state; sin polling de reconocimiento permanente ni dependencia obligatoria al iniciar.

**Criterios de aceptación:**

- Acción reconocible confirma captura/destino y devuelve resultado/error.
- Cancelar no deja captura ni archivo sensible.
- Sin proveedor, controles media existentes siguen funcionando.

**Pruebas y evidencia:**

Audio fixture conocido/silencio, endpoint cambiado, timeout/429 y cancel. Integración real requiere acceso autorizado; no fingir Shazam implementado por invocar una URL. Revisar licencia antes de empaquetar SDK/datos.


#### X09 — Regiones asistidas, zoom y herramientas de captura

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** C01, C02, U07.

**Fuentes y archivos iniciales:** nuevo: detector local de regiones/zoom/history; ii: captura/anotador.

**Problema o finalidad:** Detección de regiones original usa herramientas Linux; puede adaptarse con algoritmo local limitado sin convertirlo en modelo pesado siempre activo.

**Implementación requerida:**

Implementar detector opt-in sobre captura solicitada, con límites de tiempo/memoria y selección manual siempre disponible. Historial de capturas con retención/export/borrar y sin indexar imágenes personales por defecto. Zoom/lupa propia respeta accesibilidad y no bloquea herramienta del sistema si falta capacidad.
No anunciar OCR/región perfecta ni descargar modelos automáticamente. Imagen/cancelación/error siguen pipeline de C01/C02 y privacidad R11.

**Criterios de aceptación:**

- Detección falla de manera útil y conserva selección manual.
- Historial tiene límites/borrado verificable y no sube imágenes.
- Herramienta se descarga al cerrar sin captura continua oculta.

**Pruebas y evidencia:**

Layouts densos, contraste bajo, 4K/HDR, timeout y cancel. Medir duración/RAM, inspeccionar almacenamiento/retención y probar teclado/reducir movimiento.


#### X10 — Integraciones opcionales de teléfono, VPN y perfiles de audio

**Estado inicial:** TODO. **Prioridad:** P3. **Alcance:** IDEA. **Dependencias:** U01, R11, P10.

**Fuentes y archivos iniciales:** nuevo: adaptadores por servicio seleccionado; ii: settings/media/network.

**Problema o finalidad:** Son ideas útiles, pero dependen de servicios/APIs y no deben convertirse en dependencias del logon.

**Implementación requerida:**

Tratar cada integración como subproyecto con proveedor y alcance elegidos. Teléfono/clipboard requiere pairing/consent y formato/retención; VPN usa capacidades reales del cliente/API y nunca guarda passwords en JSON; perfiles audio guardan roles/volumen/endpoints estables y explican dispositivo ausente.
Conexión/sync a demanda, credenciales protegidas, cache/error/offline y botón desconectar. No detectar/probar sesiones o cuentas personales automáticamente ni declarar soporte universal de todos los clientes.

**Criterios de aceptación:**

- Cada proveedor habilitado tiene contrato y pruebas propias.
- Ausente/desconectado no degrada arranque ni genera reintentos ilimitados.
- Desactivar restaura solo cambios propios y retira accesos locales cuando se elige.

**Pruebas y evidencia:**

Fixtures provider absent/error, endpoint ausente y cancel; pairing/conexión reales solo en entorno autorizado. No enviar archivos/mensajes, activar VPN personal ni sincronizar clipboard sensible para completar tests.


## 7. Matriz obligatoria de entradas y fugas de UI

Esta matriz es el inventario inicial que el agente debe ampliar al leer HEAD. «Actual» describe la revisión auditada, no un resultado de pruebas Windows. Una acción que depende de un módulo opcional sigue pendiente de reemplazo completo hasta que ese módulo esté implementado. No anunciar aislamiento total por haber cambiado el binding.

| Entrada | Actual auditado | Destino/contrato esperado | Tarea |
| --- | --- | --- | --- |
| Win solo, Ctrl+Esc | Búsqueda ii si shellActive lo permite | Búsqueda ii, incluso navegador fullscreen salvo regla explícita | U02 |
| Win+S | Búsqueda ii | Conservar, mismo catálogo/modelo | U02/P13 |
| Win+Q | Cerrar activa | Conservar con identidad/resultado/error | U02/P07 |
| Win+Tab | Overview ii | Mantener, completar navegación y miniaturas | C10 |
| Alt+Tab, Alt+Shift+Tab | Selector Windows | Selector ii MRU; soltar Alt activa; Escape cancela | U03 |
| Win+X | Menú Windows | Herramientas ii con capacidades reales | U01/U02 |
| Win+I | Settings Windows | Ajustes ii | U02/U05 |
| Win+R | Ejecutar Windows | Paleta ii, intérprete/args explícitos | U02/C05 |
| Win+E | Explorer | Centro archivos ii si se adopta; mientras tanto límite/apertura externa explícita | X02/U01 |
| Win+P | Proyección Windows | Selector ii de modos soportados, rollback | U05 |
| Win+Space | Selector sistema | Layout ii; conservar composición IME y límites | U09 |
| Win+B | Sidebar izquierdo | Foco en bandeja ii, navegación teclado | U02/U06 |
| Win+T | Bloqueado sin acción | Navegar dock/ventanas ii | U02/C10 |
| Win+W, Win+Alt+D | Paneles ii | Conservar destino consistente en catálogo | U02 |
| Win+D | Mostrar escritorio propio | Conservar restauración/foco/estado | U02/P07 |
| Win+1…0 | Cambiar escritorios | Mantener con capacidad y GUID correctos | R09/U02 |
| Win+Shift+1…0 | Mover ventana | Mantener; confirmar resultado | R09/C10 |
| Win+Ctrl+D, flechas, F4 | Rutas no unificadas | Crear/cambiar/cerrar desktop por acción ii y capacidad | R09/U02 |
| Win+V, Win+. | Clipboard/emojis ii | Conservar, foco/paste/cancel/layout | U09 |
| Print, Ctrl+Print | Sin mapping ii completo | Capturar/copiar/guardar según configuración explícita | C01/U02 |
| Win+Shift+S | Selector ii | Unificar tile/launcher con misma ruta | C01 |
| Win+G y combos Xbox | G redirigido; política secundaria incompleta | Overlay/recorder ii según disponibilidad, límites por app | U02/C03 |
| Win+K | Teclado ii | Conservar y usar también desde tile | U05 |
| Ctrl+Shift+Esc | Task Manager | Centro de procesos si se adopta; límite propio mientras falte | X03/U01 |
| Volumen/brillo/media | OSD parcialmente duplicable | Acción/OSD ii donde soporte, no supresión universal inventada | U09 |
| Win+Z, gestos snap | UI organización Windows | Zonas/gestor opcional; límites mientras falte | X01/U09 |
| Win+U/H, lupa/Narrador | Accesibilidad/dictado sistema | Equivalente real o salida accesible explícita, nunca bloqueo inútil | U07 |
| Alt+Space, Shift+F10 | Menú app/Shell | Menú ii en superficies ii; terceros fuera del control universal | U06 |
| Ctrl+Alt+End | Menú sesión ii, conflicto RDP | Configurable; no sustituir secuencia remota protegida | U02 |
| Win+L, Ctrl+Alt+Supr | Seguridad Windows | Excepción de sistema; estado confirmado/transición ii | R03/U08 |
| Ctrl+Alt+Shift+R | Panic independiente | Disponible incluso en modo juego/atajos suspendidos | R05/U02 |
| Ctrl+Win+R, Ctrl+Win+T y variantes existentes | Reload/wallpaper según tabla actual | Conservar tras validar bindings reales; no duplicarlos en nueva tabla | U02/W02 |
| Touchpad/touch/bordes/botones OEM | Fuera de cobertura garantizada del hook | Inventario por hardware y política explícita | U09 |

### 7.1 Recorridos visuales que deben auditarse extremo a extremo

| Flujo | Resultado propio requerido | Casos negativos/límite |
| --- | --- | --- |
| Elegir fondo/foto/color | Picker ii + preview/cancel | Archivo corrupto/nube/permisos; no FileDialog/ChooseColor automático |
| Archivo copiar/mover/borrar/rename | Progreso, conflicto y error ii | Parcial, cancel, permisos, papelera; consentimiento protegido si necesario |
| Menú desktop/dock | Popup ii | Extensiones terceros solo elección explícita |
| Tray | Acciones representables en ii | Owner-drawn ajeno declarado; no prometer reconstrucción universal |
| Audio/micro | Endpoints/roles/sesiones y resultado ii | IPolicyConfig privado fallido, device removal, permiso |
| Red/Bluetooth | Estado/selección/acciones ii | PIN/consent del sistema puede ser protegido; hardware desconocido distinto de off |
| Pantallas/brillo/night light | Selector/OSD ii y capacidad | HDR/gamma/DDC no soportado, display rollback |
| IA/galería/translator | Busy/cancel/error ii | Auth/429/offline; no terminal invisible que falla silenciosamente |
| Capturar/editar/grabar | Selector/estado/anotador ii | Protected content/encoder/disk/full/lock |
| Lock/unlock | Bloqueo real y transición/imagen | Autenticación sistema sigue protegida; no campo QML sustituto |
| Crash/launch failure | Restauración y rescate independiente | Nunca exigir QML operativo para recuperar |
| Instalación/update | Backend seguro; frontend opcional | UAC explícito, no copiar sobre versión activa a medias |

Las APIs privadas, diálogos OEM y menús de otra aplicación no deben convertirse en promesas universales. Si Carlos exige también ocultar toda UI interna de cualquier programa que abra, ese es un alcance diferente y no lo satisface este port. Anotar cada excepción real por escenario, no usar esta limitación para dejar sin corregir rutas ii que sí son controlables.

## 8. Protocolo de rendimiento y validación Windows

### 8.1 Environment manifest

Por corrida guardar: ID, fecha, commits ii/qs/upstream, dirty flag, package hash, Qt/toolchain/configuración, edición/build Windows, CPU/GPU/driver y renderer real, RAM, pantallas/identidades/resolución/DPR/Hz/HDR, alimentación/perfil energía, loop Qt, módulos/widgets activos, proveedor externo/versión/config, configuración ii y estado de caché. No incluir claves, nombre de usuario, rutas personales ni texto de avisos/chats; usar fixtures o rutas redactadas.

La comparación utiliza el mismo equipo/configuración/escenario. Declarar calentamiento, duración, herramienta, sampling rate y normalización del porcentaje CPU. Una medición en Sandbox, VM/RDP o software renderer no se mezcla con GPU física como si fueran equivalentes.

### 8.2 Métricas y objetivos propuestos

| Métrica | Qué medir | Criterio |
| --- | --- | --- |
| Startup | Host→shell→QML→primer frame por monitor→interactivo | Reducir coste demostrado sin adelantar readiness falsamente |
| Input | Tecla/clic→feedback y resultado utilizable | Distribución p50/p95/p99, outliers y corrección del destino |
| Frame | Duración presentada/CPU/GPU según herramienta, dropped frames | Presupuesto del Hz real, no solo FPS medio |
| Reposo | CPU, wakeups, GPU, render requests, timers | Trabajo útil mínimo, sin decoración oculta perpetua |
| Memoria | Private bytes/working set, buffers CPU/GPU/cache | Plateau tras calentamiento, budgets conocidos y sin crecimiento ilimitado |
| Recursos | Handles, GDI/USER, DWM thumbnails, subscriptions, threads/procesos | Liberación al cerrar; no drift repetido |
| Red/disco | Peticiones/bytes/escrituras, activación de pestañas | Ninguna descarga de tab nunca usado ni escritura por tick |
| Energía | Consumo/batería en hardware comparable | Medición real; CPU menor no prueba por sí sola mejor autonomía |

Presupuesto ideal por frame: 60 Hz ≈16.67 ms; 75 Hz ≈13.33 ms; 144 Hz ≈6.94 ms. La animación interactiva intenta cumplir el Hz disponible, mientras espectros/efectos decorativos pueden limitarse a 30 FPS. Estas cifras no garantizan el frame final: medir también stalls, composición y presentación.

**Metas iniciales orientativas**, a confirmar tras baseline: shell propia cerca de 0.5–1 % CPU en escritorio sencillo quieto y sin fondo animado; memoria de un perfil básico del orden de 350–500 MiB; arranque caliente esencial ~1–2 s y frío ~3–5 s en equipo adecuado. No son mediciones actuales, SLAs ni límites universales. Si el equipo/Qt/perfil hace inviable una cifra, establecer budget justificado por componentes y mostrar mejora real. No alcanzar una meta quitando funciones sin declarar el cambio.

Con Wallpaper Engine visible, atribuir consumo del proveedor, DWM e ii separadamente. GPU total cero no es objetivo sensato mientras se reproduce un wallpaper animado. Sí lo es evitar que ii lo capture o renderice por segunda vez.

### 8.3 Escenarios reproducibles

| ID | Escenario y duración propuesta | Observables |
| --- | --- | --- |
| M01 | Al menos 5 cold launches y 10 warm launches comparables | Tiempos por fase, first frame de todas las pantallas y readiness |
| M02 | 10 min escritorio quieto sin reproducción | CPU/GPU/wakeups/render requests/memoria/cache |
| M03 | 10 min escritorio totalmente cubierto, luego descubrir | Pausa de decoraciones, correcto resume, input y no acumulación |
| M04 | Launcher: escribir/borrar/ejecutar sobre índice grande fixture | p95/p99, allocations, cancelación y resultado vigente |
| M05 | 100 aperturas/cierres de launcher/overview/dock/panel/tab | Handles, memoria, foco, stale bindings y flicker |
| M06 | Overview con 30–100 ventanas fixture, mover/minimizar/cerrar | Calls DWM, tracking/deltas, MRU, frame tails |
| M07 | Foto 8K/GIF grande y widgets escalados; cubrir/lock | Decode/FBO/cache, pause y nitidez |
| M08 | Media en barra/widget/panel, play/pause/endpoints | Capturas compartidas, FFT, parses y estado canónico |
| M09 | Dos monitores 1080p/4K, DPR mixto/60–144 Hz, hotplug | Layout, snapping físico, cobertura por monitor y z-order |
| M10 | Lock/resume/sleep/hibernación/RDP/cambio usuario | WTS real, restauración, callbacks y permisos |
| M11 | Permisos notificaciones admitido/denegado/revocado | Recepción visible, no pérdida y fallback explicado |
| M12 | WE/Lively: selection/audio/playlist/pausa/Explorer restart | Un render, consumo separado, policy ownership y recuperación |
| M13 | Instalación/upgrade/uninstall/faults con sentinels | Datos ajenos, journal, versiones/registry y rollback |
| M14 | IO/HTTP lento, offline, disco lleno y config inválida | UI responsiva, límites/cancelación, last-good y no falsos éxitos |
| M15 | Teclado/lector/alto contraste/texto grande/touch/IME | Accesibilidad y cero rutas Windows automáticas en flujos soportados |
| M16 | Soak final 8–24 h según alcance/infraestructura | Plateau de recursos, servicios dormidos y estabilidad |

«Cold» debe especificar qué está frío: proceso, caché QML, disco o logon tras reboot. Solo limpiar cachés propias de un perfil de pruebas cuando el escenario lo requiera; no borrar las del usuario cada arranque ni limpiar todo el sistema. Reboots/sleep y pruebas con hardware se realizan en equipo de pruebas, no durante una sesión personal sin alcance.

Las repeticiones largas pertenecen al cierre de una iteración amplia. Para un cambio reversible pequeño, ejecutar verificación proporcional y pruebas relacionadas, no repetir toda la matriz por rutina. Ampliar ante regresiones, nueva incertidumbre o un cambio del sistema que lo justifique.

### 8.4 Fault injection mínima para correcciones críticas

- **Lanzamiento:** exe/DLL ausente, acceso denegado, early exit, QML inválido, timeout readiness parcial.
- **Procesos:** shell/host/guard muerto o colgado; instancia ajena con mismo nombre; estado PID reutilizado.
- **Notificaciones:** autorización denegada/revocada; worker sin health; eventos acumulados al inicio.
- **Archivos/datos:** disco lleno, error de rename/copy, manifest manipulado, junction externa, upgrade interrumpido.
- **Sesión/hardware:** API lock falla, evento WTS tardío/ajeno, service WLAN aparece tarde, endpoint/monitor desaparece.
- **Proveedores:** CLI aceptada pero resultado no aplicado, versión incompatible, HTTP timeout/429, respuesta parcial.

Cada test debe indicar qué invariante comprueba. Se permiten mocks para ordenar eventos/errores y validar parsers, pero la conducta visual, GPU, permisos, DWM, firmware o proveedor real se acredita en Windows. No escribir «funciona» cuando solo se comprobó que no hubo excepción.

## 9. Diseños transversales y decisiones que el agente debe registrar

### 9.1 Lifecycle del host y readiness

Propuesta de estados: preparing → launching → awaiting-ready → active; cualquier error → restoring → recovered/error visible. Stop normal también pasa por restoring. Es una propuesta de diseño, no los nombres actuales del código. Readiness combina instancias/versiones correctas, primer frame útil por monitor y entrada esencial; puede exponer readiness parcial con plazo. No utilizar presencia de proceso, rectángulo HWND o heartbeats como sustituto de render disponible.

Todas las operaciones de ocultación requieren ownership, resultado y rollback. Repetir restoring debe ser seguro, incluso si Explorer se reinició o ya se restauró por guard. Un frontend de error no debe impedir el rollback si sus recursos faltan.

### 9.2 Autoridad de estados

| Estado | Fuente autoritativa | Nunca inferir únicamente de |
| --- | --- | --- |
| Shell lista | Handshake versionado + frame/entrada observados | PID vivo/ventana del tamaño esperado |
| Notificaciones soportadas | Permiso y listener operativo confirmado | Shell viva/notificación interna creada |
| Sesión segura | Información/eventos reales de sesión aplicables | Animation started/mLocked solicitud/API accepted |
| Desktop actual/movimiento | GUID/resultado backend validado | Índice en lista anterior |
| Audio default | Reconsulta/resultado por rol | Toggle visual o HRESULT ignorado |
| Provider wallpaper activo | Estado/resultado verificable disponible | CreateProcess ok/exit 0 genérico |
| Archivo copiado/grabación guardada | Resultado final y salida comprobable | Progreso 100 % o detener animación |
| Red/Bluetooth disponible | Capacidad/permisos/adaptadores reales | Lista vacía/timer terminó |
| Update instalado | Estado backend/verificación de activación | ZIP descargado |

### 9.3 Identidad y lifetime

HWND y PID pueden reutilizarse; acompañarlos de datos de creación/generación apropiados. Los monitores necesitan ID persistente mapeado al provider, no su índice temporal. Desktop debe usar GUID cuando se opera. Cada request/cache/suscripción lleva consumidor/versión de datos y cancelación; una respuesta tardía no se aplica a un objeto que ahora representa otro elemento.

Escritorios Windows son globales en la sesión en esta arquitectura. Workspace independiente por monitor exige un modelo/gestor diferente, por lo que no debe aparecer como opción de una API privada no probada.

### 9.4 Migración y política de defaults

Defaults recomendados: identidad ii en flujos soportados, placeholder media estático, decoración continua opt-in, limpieza de desktops opt-in, prewarm después de readiness, servicios de red/vistas a demanda y fallback seguro cuando falla reemplazo. El agente debe documentar qué defaults adopta y cómo migra instalaciones existentes. Una preferencia explícita del usuario puede conservarse cuando es válida; si es peligrosa/incompatible, explicar la migración y guardar respaldo.

No activar automáticamente IDEA, providers externos ausentes, capture/mic, plugins, importación de calendarios ni cambios globales del shell. No manipular Winlogon/LSA, desactivar UAC/Defender, almacenar passwords para un falso login ni instalar drivers para sensores cosméticos.

### 9.5 Tradeoffs que requieren evidencia, no adivinación

- Basic frente a threaded: conservar workaround si el candidato no repinta correctamente.
- Retención frente a RAM: TTL/LRU medidos, preservando estado de usuario y evitando churn de hover.
- Callbacks frente a sondeo: callbacks baratos y reconciliación lenta para pérdidas reales.
- Decoración frente a reposo: opt-in/profile y pausas por consumidor, sin quitar controles útiles.
- Captura de pantalla frente a DWM thumbnail: contratos distintos, no reutilización nominal.
- API pública frente a privada: capabilities/build gates/error/rollback; no compatibilidad futura implícita.
- Integración proveedor frente a control total: commands/capacidad instalada, respetando políticas previas.
- UI propia frente a autenticación: límite protegido explícito; apariencia no es garantía de seguridad.

### 9.6 Contrato mínimo propuesto para host↔shell

Elegir transporte local coherente con el proyecto actual; si se crean named pipes, ACL por SID/instancia y rechazo de mensajes ajenos. No confiar en nombre de proceso como autenticación. Este ejemplo muestra campos necesarios, no un archivo ya existente ni un protocolo impuesto sobre el que tenga HEAD.

~~~json
{
  "protocolVersion": 1,
  "instanceId": "opaque-instance-id",
  "sessionId": 1,
  "requestId": "opaque-request-id",
  "messageType": "service-state",
  "service": "notifications",
  "state": "available",
  "permission": "granted",
  "subscribed": true,
  "observedAtMonotonicMs": 12345,
  "error": null
}
~~~

- Negociar versión major y capacidades. Versión desconocida: no activar supresión/acciones peligrosas; explicar y restaurar entorno si impide funcionar.
- El host calcula caducidad con su reloj/tiempo de recepción. No restar timestamps monotónicos de procesos con origen distinto sin establecer conversión. PID/session del payload deben contrastarse con la identidad observada del canal.
- Readiness usa mensaje distinto: monitorId, firstFramePresented, inputReady y essentialServicesReady por pantalla. No inferir esos campos del mensaje de notificaciones.
- Estado lock usa fuente WTS y sesión confirmada, con unknown/requested/locked/unlocked/error separados. Un cliente no puede enviar secure=true y dar por autenticado al usuario.
- Respuesta de comando: requestId, accepted, completed, resultado efectivo y error tipado. Accepted no significa completed. Error incluye código nativo y texto traducible seguro, sin tokens/rutas privadas.
- Validar tamaño/tipos/rangos y limitar cola. Request tardía/cancelada no revierte una solicitud más reciente. Shutdown deja estado invalidado antes de retirar el canal.

### 9.7 Valores iniciales para prototipos y límites

Estos valores son **defaults de partida propuestos** para que el agente no deje recursos ilimitados. Registrar los definitivos con evidencia en B02/P18; no trasladar los números a todos los servicios ni confundir un timeout con que la operación terminó correctamente.

| Recurso/operación | Valor inicial propuesto | Regla |
| --- | --- | --- |
| Startup | Aviso de demora a 15 s, fallo recuperable a 30 s | Discriminación por fase; nunca esperar indefinidamente con Explorer oculto |
| Health listener | Heartbeat 1 s, expiración 3 s | Revocación/error conocido actúa inmediatamente; expiry restaura recepción original |
| Comando proveedor local | 5 s para respuesta del helper | Operación aceptada pendiente necesita confirmación separada; no matar proveedor principal |
| Mensaje IPC de control | Máximo 64 KiB | No transportar chat/imágenes por este canal; rechazo seguro |
| Thumbnail workers | 2 concurrentes, cola acotada/prioridad visible | Deduplicar, cancelar consumidores muertos; revisar en HDD/UNC |
| Preview de red | Hasta 4 requests concurrentes, límite 10 MiB por preview | Archivos originales son otra acción con tamaño/progreso declarados |
| HTTP ordinario | 10 s conectar, 30 s sin progreso | Streaming usa límite de inactividad/progreso; grabación no hereda este timeout |
| Retry ordinario | Hasta 3 intentos con backoff y jitter | Solo errores recuperables/idempotentes; no repetir uploads/ops de archivo a ciegas |
| Metadata cache | TTL/invalidación por mtime/version | Identidad de objeto y bytes, no clear-all por cantidad de entradas |
| Espectro decorativo | 30 FPS por defecto | Compartido, pausado sin consumidor; no cap global de animación |
| Config backups | Last-good + backup previo de migración | Rotación por tamaño/versión, sin duplicación en cada tick |
| Recorder | Un pipeline por grabación explícita | Límite/ruta/espacio visible; no perder track de estado al cerrar panel |

Definir budgets de cache CPU/GPU/disco tras contar tamaños reales y consumidores; no fijar RAM total prometida a partir de esta tabla. Cualquier límite de tamaño debe producir mensaje propio claro con posibilidad de elegir otro archivo, sin truncar silenciosamente datos.

### 9.8 Estructura del seguimiento y evidencia por tarea

Crear registro equivalente al siguiente, con paths relativos a un directorio de evidencias seguro. Es un ejemplo del formato esperado; valores entre comillas descriptivas se reemplazan por resultados reales.

~~~yaml
id: R02
estado: EN_CURSO
base_ii: "commit real"
base_qs: "commit real"
hallazgo_vigente: true
cambios:
  - "ruta fuente/overlay/parche"
commits:
  ii: []
  quickshell_windows: []
pruebas:
  - escenario: launch-exe-missing
    resultado: PENDIENTE
    entorno: "Windows build / VM o físico"
    evidencia: null
criterios_pendientes:
  - "restauración observada de Explorer"
riesgos:
  - "limitación concreta si existe"
rollback: "procedimiento probado o pendiente explícito"
~~~

El registro debe ser revisable por Carlos y reutilizable por otro agente. Guardar escenarios PASSED/FAILED/SKIPPED separados del estado de implementación. Antes de marcar VERIFICADA, todos los criterios del alcance deben tener evidencia o una limitación aceptada y documentada; «el código parece correcto» no es evidencia de comportamiento Windows.

## 10. Trazabilidad con la auditoría y cobertura funcional

La numeración R01–R11 y P01–P18 conserva la del informe, aunque algunas tareas se complementen entre sí. B01 corrige primero la base técnica de R10; R10 añade calidad de assertions. R03 corrige seguridad del contrato; U08 añade estética permitida. P02 optimiza DWM; C02 crea captura screen real; C10 añade snapshots de minimizadas. W01–W04 desglosan la integración externa; F01 responde al cambio de Fastfetch.

| Área original/paridad | Tareas que la cubren | Qué no debe confundirse |
| --- | --- | --- |
| Estructura/familias | B00/P06/P17 | Waffle no es objetivo de identidad ii |
| Barra/tray | U02/U06/U09/P10 | Menú ajeno propietario no es controlable universalmente |
| Overview | P02/P07/C10/R09 | Miniatura DWM no es screen texture |
| Launcher | P13/C05/C06/U02 | Ejecutar sugerencia no debe ocurrir al escribir |
| Clipboard/emojis | U09/R11 | Ya implementados, conservar y validar |
| Dock | C10/U02/P02 | Jump Lists avanzadas quedan capacidad/propuesta |
| Quick settings | U01/U05/P10 | Toggle visual no confirma resultado |
| Red/Bluetooth | P10/U05/U09/X10 | Sin permiso distinto de no adaptador |
| Audio/micro | P05/P10/U05/X10 | Rutas per-app/default privadas requieren límites |
| Media | P04/P05/C10/X08 | Reconocimiento/letras son ampliaciones |
| Notificaciones | R01/R11/U09 | Ocultar sistema requiere listener operativo |
| Calendario/tareas/foco | P11/X05 | Local existente distinto de calendario conectado |
| IA | R11/P06/C07/C08 | Transporte existente distinto de todos providers verificados |
| Traducción | C02/C04/C12 | Texto existente distinto de screen translation |
| Galería online | R11/P06/P09/C11 | Servicio externo no garantizado |
| Captura/OCR/grabación | C01/C02/C03/C04/X09 | Botón presente no equivale a encoder operativo |
| Overlay | P03/P16/C03/U02 | Juegos/anti-cheat no tienen compatibilidad universal |
| Wallpaper/Material | W01–W04/P09/U08 | Fondo vivo de desktop no es login animado |
| Widgets/layout | P03/P04/P11/P14/C09 | Pausa visual no altera duración real |
| Brillo/energía | P10/P16/U05/C13/C09 | Gamma HDR/salud desconocida deben declararse |
| Ventanas/gestos | R09/U02/U03/C10/X01 | Virtual Desktop global distinto de workspace por monitor |
| Sesión/bloqueo | R03/U08/C13 | QML no autentica Windows |
| Teclado/ayudas | P12/U02/U07/U09/C12 | Hook no cubre todos gestos/OEM/IME |
| Waffle | B00/documentación | Fuera del trabajo prioritario; no eliminar sin analizar consumidores |
| Mantenimiento/terminal | R04–R08/P17/F01/Q01–Q03/X07 | Release publicado distinto de fuente examinada |

Cobertura de puntos adicionales: ownership de temas/GPU/cursor/fuentes en R08; rutas largas/UNC/nube y Known Folders en U04/C09; redacción de avisos/chats y claves de galería en R11; cache/red/peticiones en P09/C11; CI Windows/dependencias/Qt privado/crash URL en P17/Q01; configs last-good y export seguro en el contrato 3.3 y la tarea adicional siguiente.

### 10.1 Configuración portable

D01 especifica schema, última versión válida, import/export y pruebas negativas. Se conserva QSaveFile como base atómica ya existente; last-good y migración son mejoras adicionales. Q01 debe verificar que un paquete/export no incluye secretos o datos de la máquina de build.

## 11. Fuentes de inspiración y decisión de traslado

| Referencia | Idea adaptada | Tareas |
| --- | --- | --- |
| [Caelestia](https://github.com/caelestia-dots/shell) | Dashboard/acciones/transiciones coordinadas | P06/U01/X04 |
| [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) | Proveedores de búsqueda, procesos y extensiones | C06/X03/X06 |
| [Noctalia](https://github.com/noctalia-dev/noctalia) | Navegación/ranking, movimiento y estilo coherentes | P13/U07/X04 |
| [HyDE](https://github.com/HyDE-Project/HyDE) | Packs y perfiles con preview | P16/X04 |
| [Hydebar](https://github.com/HyDE-Project/hydebar/blob/main/ROADMAP.md) | Eventos/coalescencia/budgets como orientación de diseño | P07/P10/P18 |
| [niri](https://github.com/niri-wm/niri) | Navegación espacial/overview | C10/X01 |
| [GlazeWM](https://github.com/glzr-io/glazewm) | Tiling/reglas ya orientados a Windows | X01 |

Estas referencias provienen de la auditoría, no de un benchmark comparativo. Antes de incorporar código/assets/dependencias, revisar licencia, versión, arquitectura y coste. Copiar idea de navegación es distinto de copiar un compositor Linux; preservar la identidad ii y evitar otra barra duplicada.

## 12. Prompt listo para entregar al agente

Copiar este bloque y adjuntar este documento completo y, si está disponible, la auditoría original:

> Trabaja en ii-windows y su fork quickshell-windows siguiendo TASKS_ii_windows.md. Antes de editar, lee las instrucciones locales, compara HEAD con los commits auditados y confirma qué hallazgos siguen vigentes. Conserva upstream y cambios del usuario.
>
> El alcance inicial recomendado es CORE y su VALIDACIÓN, empezando por B00/B01/B02 y los P0; PARIDAD e IDEA son fases separadas. Si esta sesión selecciona un subconjunto, registra los IDs y sus dependencias y no anuncies el resto como terminado.
>
> Implementa cambios persistentes en fuentes/overlay/parches, no solo en build/ii. Prioriza recuperación, datos y seguridad del contrato de sesión; luego rendimiento medido y rutas propias ii. Cada tarea debe entregar criterios de aceptación, tests pertinentes y evidencia antes/después. Función visible en QML no equivale a servicio operativo.
>
> No prometas login QML seguro, compatibilidad universal de COM privado ni ausencia absoluta de UI Windows protegida. Mantén una recuperación usable si falla el reemplazo. No ocultes avisos cuando el listener no puede recibirlos.
>
> Si no tienes Windows/hardware/proveedor, implementa y prepara pruebas de las tareas independientes y marca exactamente lo que queda sin validar. No inventes PASS/FPS ni te detengas únicamente a proponer otro plan. No publiques, despliegues en la sesión personal ni uses cuentas/servicios externos fuera del alcance otorgado.
>
> Mantén seguimiento por ID con cambios, commits de ambos repositorios, evidencias y bloqueos. Termina con un paquete local revisable, instrucciones de reproducción, límites reales y pendientes accionables.

## 13. Referencias técnicas y evidencias fijadas

Las fuentes siguientes se conservan para localizar el razonamiento y los contratos auditados. Antes de implementar una API o CLI, consultar su documentación oficial vigente para la versión objetivo. Los enlaces de código fijados muestran la base del hallazgo; las líneas pueden no coincidir con HEAD futuro. No transformar ejemplos de documentación en garantías de una build no probada.


### 13.1 Documentación primaria citada en la auditoría

Estas fuentes respaldan límites/API y las referencias de diseño, no las mediciones del port. La adaptación concreta propuesta es razonamiento de esta auditoría.

- **S1 — Microsoft:** [LockWorkStation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-lockworkstation). Operación asíncrona y notificaciones de sesión.
- **S2 — Qt:** [Qt Quick performance](https://doc.qt.io/qt-6.12/qtquick-performance.html) y [QML profiling](https://doc.qt.io/qtcreator/creator-qml-performance-monitor.html). Presupuesto de frames, trabajo asíncrono y perfilado.
- **S3 — Microsoft:** [LowLevelKeyboardProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc). Estado de teclas y retirada silenciosa por timeout.
- **S4 — Microsoft:** [Campos de Credential Provider](https://learn.microsoft.com/en-us/windows/win32/api/credentialprovider/ne-credentialprovider-credential_provider_field_type) y [Credential Providers](https://learn.microsoft.com/en-us/windows/win32/secauthn/credential-providers-in-windows). Modelo de campos/autenticación y sus límites.
- **S5 — Microsoft:** [Custom Logon](https://learn.microsoft.com/en-us/windows/configuration/custom-logon/). Disponibilidad por edición y alcance.
- **S6 — Wallpaper Engine:** [Lock screen](https://help.wallpaperengine.io/en/general/lockscreen.html). Límite de fondo animado y snapshot estático.
- **S7 — Wallpaper Engine:** [Command Line Controls](https://help.wallpaperengine.io/en/functionality/cli.html). Controles documentados del proveedor.
- **S8 — Lively:** [Command Line Controls](https://github.com/lively-community/lively/wiki/Command-Line-Controls). Wiki actual consultada; no usar sintaxis de revisiones antiguas sin validar versión instalada.
- **S9 — Fastfetch:** [Repositorio oficial](https://github.com/fastfetch-cli/fastfetch), [Logo options](https://github.com/fastfetch-cli/fastfetch/wiki/Logo-options) y [Dependencies](https://github.com/fastfetch-cli/fastfetch/wiki/Dependencies).
- **S10 — Microsoft:** [IVirtualDesktopManager](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager). Distinguir este contrato público de COM interno de Explorer.
- Las referencias primarias de Caelestia, DMS, Noctalia, HyDE, Hydebar, niri y GlazeWM están enlazadas en la tabla correspondiente. No se usaron reseñas de terceros para atribuirles capacidades.

### 13.2 Índice de código auditado

Las rutas y enlaces de la siguiente tabla quedan fijados a las revisiones examinadas. En el QML parcheado, la evidencia corresponde al overlay o al parche que lo genera; no a un supuesto archivo `build/ii` publicado en Git.

| Evidencia | Archivo fijado |
| --- | --- |
| Arquitectura, receta y promesas | [ii: README.md](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/README.md#L87) |
| Estado reciente, métricas históricas y pendientes | [ii: PROGRESS.md](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/PROGRESS.md#L259) |
| Inventario anterior; contrastar con parches actuales | [ii: docs/INVENTARIO-WINDOWS.md](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/docs/INVENTARIO-WINDOWS.md#L1) |
| Launch, banners, fallos, prioridad y rescate | [ii: host/src/main.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/main.cpp#L101) |
| Atajos, fullscreen y callback | [ii: host/src/keyboard.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/keyboard.cpp#L115) |
| Supresión/restauración de banners | [ii: host/src/banners.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/banners.cpp#L70) |
| Cubierta de arranque y repintado | [ii: host/src/splash.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/splash.cpp#L180) |
| Restauración y propiedad de temas | [ii: host/src/theme.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/theme.cpp#L89) |
| Operaciones y UI Shell de archivos | [ii: host/src/fileops.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/fileops.cpp#L137) |
| Virtual desktops internos y build gate | [ii: host/src/vdesk.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/vdesk.cpp#L95) |
| Multi-command shim y límites de bash | [ii: host/src/shim.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/shim.cpp#L300) |
| Capturas/edición y acciones incompletas | [ii: host/src/capture.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/capture.cpp#L272) |
| Transporte IA | [ii: host/src/airequest.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/airequest.cpp#L109) |
| Secretos de IA | [ii: host/src/secrettool.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/secrettool.cpp#L68) |
| FFT/loopback | [ii: host/src/cava.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/cava.cpp#L324) |
| Terminal/perfiles y selector color | [ii: host/src/switchwall.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/switchwall.cpp#L343) |
| Brillo/hardware | [ii: host/src/brightness.cpp](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/host/src/brightness.cpp#L1) |
| Staging normal | [ii: tools/dev/stage-ii.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/dev/stage-ii.ps1#L16) |
| Deploy y dependencias | [ii: tools/dev/deploy.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/dev/deploy.ps1#L2) |
| Parche P0, batería, galería y widgets | [ii: tools/port/patch_ii_p0.py](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/port/patch_ii_p0.py#L40) |
| Parche IA y temporales | [ii: tools/port/patch_ii_ai.py](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/port/patch_ii_ai.py#L123) |
| Animación/estado de bloqueo | [ii: tools/port/patch_ii_lock.py](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/port/patch_ii_lock.py#L1) |
| Ajustes y controles escondidos | [ii: tools/port/patch_ii_settings.py](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/port/patch_ii_settings.py#L1) |
| Parche/desktops | [ii: tools/port/patch_ii_desktops.py](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/port/patch_ii_desktops.py#L26) |
| Comandos/settings Windows del panel | [ii: tools/port/patch_ii_sidebar.py](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/port/patch_ii_sidebar.py#L336) |
| Limpieza automática desktops | [ii: overlay/ii/services/DesktopCleanup.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/services/DesktopCleanup.qml#L38) |
| Modelo completo reconstruido | [ii: overlay/ii/services/HyprlandData.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/services/HyprlandData.qml#L68) |
| Cobertura escritorio | [ii: overlay/ii/services/DesktopCover.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/services/DesktopCover.qml#L1) |
| Foto/GIF | [ii: overlay/ii/modules/ii/background/widgets/photo/PhotoWidget.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/modules/ii/background/widgets/photo/PhotoWidget.qml#L127) |
| Música/espectro/placeholder | [ii: overlay/ii/modules/ii/background/widgets/media/MediaWidget.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/modules/ii/background/widgets/media/MediaWidget.qml#L34) |
| Iconos y menús de escritorio | [ii: overlay/ii/modules/ii/background/widgets/desktop/DesktopIcons.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/modules/ii/background/widgets/desktop/DesktopIcons.qml#L1) |
| Menú de escritorio | [ii: overlay/ii/modules/ii/background/widgets/desktop/DesktopMenu.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/modules/ii/background/widgets/desktop/DesktopMenu.qml#L116) |
| Session Windows | [ii: overlay/ii/modules/common/functions/Session.qml](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/overlay/ii/modules/common/functions/Session.qml#L36) |
| Instalación/upgrade/GPU | [ii: tools/package/install.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/package/install.ps1#L152) |
| Desinstalación, datos y manifest | [ii: tools/package/uninstall.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/package/uninstall.ps1#L183) |
| Nombre de tarea | [ii: tools/package/autostart-task.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/package/autostart-task.ps1#L10) |
| Contenido/versiones/terceros del paquete | [ii: tools/package/make-package.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/package/make-package.ps1#L38) |
| Reporte y redacción | [ii: tools/rescue/ii-report.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/rescue/ii-report.ps1#L12) |
| Driver de pruebas | [ii: tools/sandbox/sbx.ps1](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/tools/sandbox/sbx.ps1#L35) |
| Logo textual | [ii: extras/fastfetch/ii-logo.txt](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/extras/fastfetch/ii-logo.txt#L1) |
| Config de Fastfetch | [ii: extras/fastfetch/ii.jsonc](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/extras/fastfetch/ii.jsonc#L6) |
| Wrapper que impone logo | [ii: extras/fastfetch/fastfetch.cmd](https://github.com/TheCarlosS5/ii-windows/blob/22dec5487e8482aeb5f150880e2ea24c5014ed1b/extras/fastfetch/fastfetch.cmd#L3) |
| Flags, Debug y URL crash | [qs: CMakeLists.txt](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/CMakeLists.txt#L115) |
| Loop basic | [qs: src/win32/init.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/init.cpp#L29) |
| Miniaturas/lock superficial | [qs: src/win32/compat/wayland.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/compat/wayland.cpp#L189) |
| secure y fuentes screen no soportadas | [qs: src/win32/compat/wayland.hpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/compat/wayland.hpp#L221) |
| Tracking y escaneos | [qs: src/win32/toplevels.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/toplevels.cpp#L215) |
| Entrada/AppBar y reconciliación | [qs: src/win32/native.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/native.cpp#L304) |
| Compatibilidad Hyprland/dispatch | [qs: src/win32/compat/hyprland.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/compat/hyprland.cpp#L543) |
| Virtual desktops Windows | [qs: src/win32/virtualdesktops.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/virtualdesktops.cpp#L1) |
| Audio/sesiones/default no público | [qs: src/win32/services/pipewire.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/pipewire.cpp#L301) |
| Notificaciones/permisos/poll | [qs: src/win32/services/notifications.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/notifications.cpp#L129) |
| Red/refresco | [qs: src/win32/services/network.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/network.cpp#L85) |
| Bluetooth nativo | [qs: src/win32/services/bluetooth.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/bluetooth.cpp#L1) |
| Batería/valores normalizados | [qs: src/win32/services/battery.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/battery.cpp#L58) |
| Media GSMTC | [qs: src/win32/services/mpris.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/mpris.cpp#L1) |
| Bandeja Windows | [qs: src/win32/services/tray.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/win32/services/tray.cpp#L1) |
| Proveedor síncrono pixmap | [qs: src/core/iconimageprovider.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/core/iconimageprovider.cpp#L17) |
| Cachés y Shell GetImage | [qs: src/core/winapps.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/core/winapps.cpp#L211) |
| Caché QML entre inicios | [qs: src/core/qmltree.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/core/qmltree.cpp#L47) |
| Scanner de rutas corregido | [qs: src/core/scan.hpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/core/scan.hpp#L27) |
| FileView atómico | [qs: src/io/fileview.cpp](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/src/io/fileview.cpp#L262) |
| CI heredada Linux | [qs: .github/workflows/build.yml](https://github.com/TheCarlosS5/quickshell-windows/blob/39428f7c5fb0fd38f56601ed10f1aa93aa8950c0/.github/workflows/build.yml#L11) |
| Panel izquierdo base/pin | [up: dots/.config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeft.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeft.qml#L56) |
| Medios base y ruta IPC | [up: dots/.config/quickshell/ii/modules/ii/mediaControls/MediaControls.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/modules/ii/mediaControls/MediaControls.qml#L194) |
| Carga de paneles | [up: dots/.config/quickshell/ii/panelFamilies/PanelLoader.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/panelFamilies/PanelLoader.qml#L8) |
| Lanzador/resultados | [up: dots/.config/quickshell/ii/services/LauncherSearch.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/services/LauncherSearch.qml#L184) |
| Búsqueda/indexado | [up: dots/.config/quickshell/ii/services/AppSearch.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/services/AppSearch.qml#L46) |
| Cronómetro | [up: dots/.config/quickshell/ii/services/TimerService.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/services/TimerService.qml#L110) |
| Idiomas/listado | [up: dots/.config/quickshell/ii/services/Translation.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/services/Translation.qml#L99) |
| Tamaño wallpaper correcto | [up: dots/.config/quickshell/ii/modules/common/widgets/StyledImage.qml](https://github.com/end-4/dots-hyprland/blob/33f31a08caddd41422a2d97670adeeb52b4f1e7c/dots/.config/quickshell/ii/modules/common/widgets/StyledImage.qml#L27) |

## 14. Regla de cierre

Este documento es una lista de trabajo con criterios de verificación, no una certificación del estado actual. El agente debe mantener visible la diferencia entre código implementado, conducta probada y límite de plataforma. El resultado esperado es una base ii fiable y fluida con ampliaciones seleccionadas, sin comprometer recuperación ni autenticación para aparentar que Windows ha desaparecido.

## 15. Registro de ejecución

Registro vivo de lo ejecutado a partir de este documento. Cada ficha sale de `docs/seguimiento/<ID>.md`
y se vuelca aquí con `python tools/dev/tasks_status.py sync` (que también marca el índice de la sección 5).
Los estados son los de la sección 3.4; las casillas del índice reflejan este registro, no la redacción original.

**Alcance de esta ejecución (10 de octubre de 2026, rama `work/tasks-ii-windows`; fork en `ii-tasks`):**
fases 0–2 (base, recuperación, propiedad) en la medida indicada ficha a ficha, parte de la fase 3, F01 y las
tareas de las fases 4–6 que figuran abajo. Las tareas sin ficha en esta sección siguen en `TODO`: **no están
hechas y este documento no debe leerse como cumplimiento completo** (sección 4, «Puede entregarse un paquete
correctivo…»). Las ideas (fase 8) no se han tocado.

**Entorno:** Windows 11 Pro 10.0.28000, equipo de pruebas del usuario con su ii real
instalado y en ejecución. Ese ii **no se tocó**: todo se probó en carpetas temporales, con instancias aisladas
de `ii-host` (`II_DATA_DIR`, `II_NO_UI=1`, sin ocultar nada) y un shell falso (`ii-fake-shell`). No se probaron GPU
dedicada, segunda pantalla, Wallpaper Engine, Lively, tacto, RDP ni batería; los escenarios que los
necesitan quedan como pendientes de validación, no como PASS.

**Cadena de herramientas (sin administrador, nada instalado en el sistema):** MSVC 14.44 + Windows SDK 26100 en
`dev\toolchain\msvc` (extracción portátil de los paquetes oficiales de Microsoft con `portable-msvc.py`), clang-cl
23.1.3 (LLVM oficial), Qt 6.12 oficial (`tools/dev/fetch_qt.py`), CLI11 2.5.0, CMake/Ninja de pip. `tools/dev/vsenv-portable.ps1`
activa el entorno. Compilados: `ii-host`, `ii-fake-shell`, `ii-lockstate-test`, `ii-sidebar-test` y el fork de
Quickshell completo (Release, preset `windows-release`).

**Cómo reproducir las pruebas:**
`powershell -File tools\sandbox\runner-selftest.ps1` (el runner) ·
`powershell -File tools\sandbox\run-tests.ps1 -Path tools\sandbox\tests\test-host-launch.ps1 -RequireAssertions` (una prueba) ·
`powershell -File tools\sandbox\run-tests.ps1 -Suite tools\sandbox\tests -Filter "test-*.ps1" -RequireAssertions` (la suite nueva).
Las pruebas `test-host-*`, `test-bench`, `test-rescue-ps` necesitan `cmake --build host\build --target ii-host ii-fake-shell` antes.
Cada ejecución escribe `results.json` con passed/failed/timeout/skipped por prueba; un skip nunca cuenta como PASS.

**Decisiones propuestas adoptadas (no aprobadas por Carlos, ajustables):** timeouts de arranque 45 s (90 s en
primer arranque sin caché QML) en lugar de 30 s, a afinar con B02; reintento de `CreateProcess` 3 veces con espera
1/2/4 s; una pantalla sin fondo de la shell tras 10 s de que otra ya lo tenga cuenta como «listo parcial» y su
cubierta se retira; `restore` solo deshace lo que este ii ocultó (el rescate fuerza); `-KeepConfig` conserva también
las claves guardadas y existe `-KeepSecrets`; el desinstalador ya no borra `%LOCALAPPDATA%\quickshell` entero.

### ID: B00 — Confirmar HEAD, arquitectura y mapa de reproducción

**Estado:** VERIFICADA
- **Base:** ii-windows `22dec54` (= revisión auditada, sin diferencias); quickshell-windows `39428f7` (= auditada); upstream `33f31a0` (= auditada, sin modificar). Hallazgos R01–R05 y P15 siguen vigentes en HEAD; ninguno estaba ya resuelto.
- **Cambios:** `tools/sandbox/tests/test-staging.ps1`; `tools/dev/vsenv-portable.ps1`; rama de trabajo `work/tasks-ii-windows` (ii) e `ii-tasks` (fork); upstream clonado en `upstream/` (ignorado por git).
- **Pruebas (PASS):** `test-staging` (11 aserciones): dos stagings limpios dan árboles idénticos byte a byte (942 archivos, hash de árbol `C9A816DF…F75A`); `upstream/` no cambia; un upstream movido (texto esperado por `patch_ii_lock.py` alterado) hace fallar el parche con `expected 1 match(es), found 0` y el nombre del archivo.
- **Pendiente:** el mapa ficha→archivo se hizo solo para las fichas ejecutadas (resto, al abordarlas). La clasificación completa de rutas Linux residuales queda para C12.
- **Rollback:** n/a (solo lectura + pruebas).

### ID: B01 — Hacer fiable el runner de pruebas

**Estado:** VERIFICADA
- **Base:** `sbx.ps1` hacía `break` en timeout y terminaba en cero; el agente no devolvía el código de salida de cada script.
- **Cambios (commit `32c2b78`):** `tools/sandbox/run-tests.ps1` (cada prueba en su proceso, timeout que mata solo el árbol de esa prueba, resultado por prueba en `results.json`, `-RequireAssertions`, skips reportados como skipped, carpeta de salida nueva por ejecución); `lib/ii-test.ps1` (Assert-*, Skip-Test, código 77); `runner-selftest.ps1` + fixtures (éxito, exit 7, excepción, aserción fallida, proceso colgado con hijo, skip, sin aserciones); `sbx.ps1`/`agent.ps1` devuelven el código de salida (124 timeout, 125 agente antiguo).
- **Pruebas (PASS):** `runner-selftest.ps1` bajo Windows PowerShell 5.1 y pwsh 7: 15 comprobaciones desde un proceso padre (exit 7 ⇒ el runner sale distinto de 0; timeout ⇒ `timeout` y sin hijos huérfanos; skip ⇒ exit 0 pero `passed=0`; una falla entre pasadas falla la corrida).
- **Pendiente:** las ~114 pruebas heredadas de `tests/` no se han convertido (R10); `sbx.ps1` no se ejecutó (Windows Sandbox no está habilitado en este equipo).
- **Rollback:** los scripts nuevos son aditivos; `git revert 32c2b78`.

### ID: B02 — Instrumentar arranque, frames y consumo antes de optimizar

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Qué hay:** marcas de línea de tiempo con reloj monotónico en `host.log` (`bench: +<ms> <evento>`): host listo, shell lanzada, primera cobertura por monitor, listo (o listo parcial), cubierta retirada (commit `1f6919c`); sondeo de readiness cada 250 ms hasta que la shell esté lista; `tools/dev/bench-manifest.ps1` (manifiesto de entorno sin nombre de usuario, equipo ni rutas personales); `tools/dev/bench-startup.ps1` (N arranques ⇒ min/p50/p95/p99/max por fase + datos brutos + manifiesto; se niega a correr con ii abierto salvo `-Inert`); `tools/dev/lib/bench-stats.ps1`.
- **Pruebas (PASS):** `test-bench` (29 aserciones): percentiles por rango más cercano sobre datos de respuesta conocida, detección de reloj no monotónico, manifiesto con los campos del protocolo y sin identidad, 3 arranques reales inertes con la shell falsa (línea de tiempo ordenada, marca por monitor, un log por corrida).
- **Pendiente (impide VERIFICADA):** toma de referencia real (≥5 arranques fríos/10 cálidos) con el ii real; frames p95/p99, entrada, CPU/GPU, working set y handles (solo hay arranque); build Release comparable ya existe (preset `windows-release`). Los números del shell falso **no** son una línea base.
- **Rollback:** las marcas son líneas de log; `git revert 1f6919c`.

### ID: R01 — Coordinar permisos y salud antes de ocultar notificaciones

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Contrato:** `host/src/health.cpp`, mensaje JSON UTF-16 v1 por `WM_COPYDATA` (≤64 KiB, tipo `service-state`): la autoridad sale del canal (la ventana emisora debe ser del proceso de la shell que lanzó este host), del `instanceId` aleatorio entregado por entorno (`II_INSTANCE_ID`, `II_HOST_HWND`, `II_PROTOCOL_VERSION`) y de la sesión; la caducidad (3 s, latido 1 s) la juzga el reloj del host. Versión desconocida, emisor ajeno, id incorrecto o estado ≠ `available` no ocultan nada.
- **Cambios:** host (commit `3934b00`): los banners de Windows solo se desactivan tras un informe fresco «available/granted/subscribed» y se devuelven al instante si el permiso se deniega o revoca, el latido se calla, la shell cae o llega un mensaje inválido; la llamada periódica ya no los vuelve a ocultar (`evaluateBanners`). Fork (commit `01317f1`): el listener relee el permiso cada vuelta (sin diálogo), sigue vivo si está denegado (un permiso concedido después funciona) y envía el latido tras cada lectura; si el bucle se cuelga, el latido para.
- **Pruebas (PASS):** `test-host-health` (18 aserciones) con una shell falsa que emite los mensajes reales: ok ⇒ apagado una sola vez; denegado, id erróneo, versión 99 ⇒ nunca apagado; silencio ⇒ devuelto en ≤3 s; revocación ⇒ devuelto al instante; emisor que no es la shell ⇒ ignorado. El fork compila (Release, clang-cl).
- **Pendiente (impide VERIFICADA):** el listener real de Windows (primer inicio, aceptar/denegar, revocar con la shell viva, Explorer reiniciado) no se probó: pediría el diálogo de permiso en el equipo del usuario. «Sin duplicación ordinaria» en la transición no se midió. Los avisos internos de ii no se distinguen aún de los del sistema en el informe.
- **Riesgos / rollback:** `--keep-banners` sigue desactivando todo. Un host nuevo con una shell vieja nunca recibe latido ⇒ los banners de Windows se quedan encendidos (degradación segura). `git revert 3934b00` (host) / `01317f1` (fork).

### ID: R02 — Lanzar y activar la shell como operación recuperable

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (commits `33479f8`, `a650d76`):** fases registradas (preparing → launching → awaiting-ready → active → restoring → recovered/failed); un ejecutable de shell inexistente se rechaza **antes** de ocultar nada; `CreateProcess` fallido ⇒ 3 intentos con espera 1/2/4 s y después restauración por el camino común (`restoreAndStop`, idempotente, sin `PostQuitMessage` hasta tras el aviso) y un solo mensaje; una shell que nunca muestra su fondo devuelve Explorer mientras se reinicia y lo vuelve a ocultar cuando la nueva está lista; readiness **por monitor** (listo parcial con plazo de 10 s, monitores ausentes registrados); timeouts 45 s/90 s en frío; los kills del watchdog no cuentan como cuelgues; `restore` solo deshace lo que este ii ocultó (el rescate fuerza).
- **Pruebas (PASS):** `test-host-launch` (37 aserciones, instancias aisladas e inertes): exe ausente ⇒ exit 1 sin fase de lanzamiento; exe imposible de crear ⇒ 3 intentos espaciados y exit 2; shell que sale con 5 siempre ⇒ exit 2; shell que nunca muestra nada ⇒ devuelve Explorer, reinicia 3 veces, exit 2 y no deja procesos; shell sana ⇒ `active`, shell registrada, `WM_CLOSE` ⇒ exit 0 y la shell se va.
- **Pendiente (impide VERIFICADA):** no se verificó el estado real de Explorer (barra/iconos visibles tras el fallo, sin cubiertas ni handles huérfanos) porque las pruebas son inertes a propósito (el ii real corre en este equipo); QML inválido y DLL ausente reales; matar host/guard/shell por separado con la ocultación activa; el «entorno de entrada esencial» (solo se mira cobertura de pantalla, no hay mensaje `readiness` de la shell: queda como parte de R01/P15 con un cambio en el fork).
- **Riesgos / rollback:** el umbral de 45 s es una propuesta; si una máquina lenta supera 45 s sin caché, 3 reinicios ⇒ abandono: la espera es 90 s si no hay caché QML. `git revert 33479f8 a650d76`.

### ID: R03 — Corregir el contrato de bloqueo solicitado y confirmado

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios:** fork `ae68568` — `compat/lockstate.hpp` (máquina de estados sin Qt: unknown/unlocked/requested/accepted/locked/error), `WlSessionLock` la usa: `LockWorkStation()` se llama **al momento** (sin los 450 ms decorativos) y solo inicia el bloqueo; `secure` es verdadero únicamente tras el evento WTS de **esta** sesión (o una consulta de la sesión al arrancar, con «unknown» si no se puede leer); fallo de API o falta de confirmación a los 5 s ⇒ `lockFailed(reason)` y el estado «solicitado» se retira; un `unlock()` desde QML nunca desbloquea Windows; eventos de otra sesión ignorados; reconexión consola/RDP relee la sesión. ii `3934b00`: `Session.lock()` deja de programar una segunda petición a los 2 s; el parche de bloqueo restablece `screenLocked` en `onLockFailed` y toma el estado si la shell arranca ya bloqueada.
- **Pruebas (PASS):** `ii-lockstate-test` (33 comprobaciones: secure solo tras Windows; llamada fallida/aceptada/tardía/temporizador viejo; otra sesión; unlock de QML; Win+L sin petición; inicio ya bloqueado; resync); humo con el `quickshell.exe` compilado: `WlSessionLock` lee del Windows real `secure=false state=unlocked` sin bloquear.
- **Pendiente (impide VERIFICADA):** bloqueo real (Win+L, bloqueo desde ii, RDP, suspender/reanudar) no probado: bloquearía la sesión del usuario. No se introdujo ninguna contraseña en QML (ni se prueba). La transición visual/imagen estática es U08.
- **Rollback:** `git revert ae68568` en el fork + `3934b00` en ii.

### ID: R04 — Limitar desinstalación a datos propiedad de ii

**Estado:** VERIFICADA
- **Cambios (commit `88e7028`, integrado en `b465360`):** `tools/package/ii-ownership.ps1`: lista fija de lo que ii posee (`quickshell\illogical-impulse`, `quickshell\State\user`, `quickshell\cache\notifications`, `ii-windows\cache`, `ii-windows\secrets`), borrado confinado a su raíz que no sigue junctions ni enlaces simbólicos (un enlace se retira como enlace; un ancestro enlazado se rechaza) y `install.json` **no** es fuente de rutas a borrar. El desinstalador ya no borra `%LOCALAPPDATA%\quickshell`; `-KeepConfig` conserva config, estado y claves; nuevo `-KeepSecrets`; la selección de procesos usa prefijo de ruta real. El instalador copia la biblioteca y `make-package` la empaqueta.
- **Pruebas (PASS):** `test-ownership` (32 aserciones, `LOCALAPPDATA` temporal): otra config de Quickshell, su estado y la caché compartida sobreviven con y sin `-KeepConfig`; lo de ii se borra/conserva según los interruptores; junction dentro, como carpeta propia y como ancestro ⇒ el destino queda intacto; rutas fuera de raíz/raíz/raíz de unidad/hermano con prefijo rechazadas; manifest hostil o corrupto no borra nada. `test-install-flow` (43): el `install.ps1`/`uninstall.ps1` reales en modo `-Sandbox` sobre un `LOCALAPPDATA` desechable: instalar → actualizar → desinstalar, y otra vez instalar → `-KeepConfig` (config y claves sobreviven) → reinstalar sobre ellos → desinstalación completa (config y claves se van; otra config de Quickshell sigue intacta).
- **Límite del alcance:** el desinstalador no se ejecutó contra el `LOCALAPPDATA` real de este equipo (tocaría el ii instalado y en uso); `-Sandbox` omite fuentes, cursor, PATH, tarea, entrada de Aplicaciones y perfiles de Terminal, que se cubren por separado o quedan pendientes (ver R06/R08). Rutas con espacios y un manifest «ausente» no se probaron como casos propios.
- **Compatibilidad:** los manifests antiguos funcionan (las rutas ya no se leen). Quien quiera conservar la config usa `-KeepConfig`; «borrar también otras configs de Quickshell» ya no existe, a propósito.
- **Rollback:** `git revert 88e7028`.

### ID: R05 — Rescatar solo los procesos de la instancia supervisada

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (commits `33479f8`, `1f6919c`):** el host registra en `state.ini` (`[instance]`) PID + hora de creación + ruta + config de su shell y de sí mismo; guardia y `--rescue` paran solo el proceso cuyo PID, creación, ruta y sesión coinciden (primero cierre ordenado a sus ventanas, después terminación acotada); sin registro, solo procesos con la ruta exacta `<instalación>\quickshell\quickshell.exe`; PID reutilizado o registro viejo no autoriza nada. `tools/rescue/ii-rescue.ps1` hace lo mismo (registro o ejecutable bajo la carpeta de la instalación, misma sesión) en lugar de `Get-Process` por nombre. `killProcessesNamed` desapareció.
- **Pruebas (PASS):** `test-host-launch` (rescate: shell+host registrados paradas, un `quickshell.exe` de otra carpeta intacto; registro viejo ⇒ intacto con la razón en el log; sin registro ⇒ solo el exe exacto) y `test-rescue-ps` (8 aserciones: igual para el rescate PowerShell, incluido registro válido fuera de la instalación).
- **Pendiente (impide VERIFICADA):** otra sesión de usuario (no hay segunda cuenta), host colgado de verdad con la ocultación activa y la restauración posterior de Explorer; la comparación de línea de comandos/config de una misma exe con dos configuraciones no se implementó (el registro cubre la instancia supervisada; el caso sin registro sí distingue por ruta de ejecutable, no por argumentos).
- **Rollback:** `git revert 33479f8 1f6919c`.

### ID: R06 — Hacer autostart independiente por usuario y dueño

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (commit `b9613eb`):** `tools/package/ii-autostart.ps1`: la tarea es `\ii-windows\Logon-<SID>` (identidad por SID, carpeta propia) y lleva en la descripción el marcador `[ii-windows-owner:<SID>]` y la versión; instalar reemplaza/actualiza solo una tarea con ese marcador; una homónima sin marcador se **informa y se conserva**; la tarea antigua plana `\ii-windows` solo se migra si demostrablemente es de este usuario (corre como su SID) y de esta instalación (el programa está dentro de su carpeta), si no se conserva y se explica; se ejecuta limitada, sin elevar; el instalador intenta sin elevación primero y solo pide administrador si Windows lo rechaza. El desinstalador retira solo la propia (y la antigua si es suya).
- **Pruebas (PASS):** `test-autostart` (25 aserciones) contra el Programador de tareas **real** pero solo en una carpeta desechable (`\ii-windows-test\<id>\`): alta con marcador, RunLevel Limited, trigger de inicio de sesión, ruta con caracteres no ASCII, actualización sin duplicar, tarea de «otro usuario» y homónima sin marcador intactas tras instalar y desinstalar, migración de la antigua propia, conservación de la antigua ajena.
- **Pendiente (impide VERIFICADA):** dos cuentas reales, cambio rápido de usuario y ejecución de la tarea al iniciar sesión (no se reinició ni se inició sesión); el instalador completo con la tarea real no se ejecutó (se probó con `-Sandbox`, que no toca el autostart).
- **Rollback:** `git revert b9613eb`; la tarea antigua `\ii-windows` del usuario no se tocó en las pruebas.

### ID: R07 — Instalar y actualizar runtime con activación y rollback

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Diseño (commit `b465360`):** `versions\<id>\` (una versión completa, nunca editada tras activarla) + `current.txt` (active/previous/state/attempts, sustituido de forma atómica con `File.Replace`/`MoveFileEx`) + `journal.txt`. `Install-IiRuntime`: verifica el paquete contra `payload.manifest` (sha256), copia a `<id>.staging-<n>` junto a la versión activa, verifica la copia, **un** renombrado de directorio y **un** reemplazo de `current.txt`; la versión anterior queda como vuelta atrás hasta que la nueva se confirma. `ii-launcher.exe` es el punto de entrada estable (accesos, tarea de inicio, clave Run): arranca la versión activa y, si está `pending`, espera a que el host la confirme (`ii-host` escribe `verified` cuando su shell está lista); si el host cae, no verifica en el plazo o se lanza demasiadas veces, vuelve a la anterior, ejecuta `--rescue` del colgado y deja `last-failure.txt`/`launcher.log`. Salida 17 del host = «ya hay un host» (no es fallo). Las instalaciones planas antiguas son la versión `legacy`. `make-package` escribe `payload.manifest` y `build-info.json`; `install.ps1` usa todo esto.
- **Pruebas (PASS):** `test-runtime` (74 aserciones, binarios falsos): instalación limpia, actualización sin tocar la versión activa (hash del árbol), crash/hang/«ya corriendo»/demasiados intentos, rollback manual, limpieza de versiones antiguas solo cuando están verificadas, capa legacy, paquete manipulado/incompleto/id con `..\` rechazados, y fallos inyectados (copia interrumpida, disco lleno simulado, archivo bloqueado de verdad, tras stage / tras rename / antes del puntero) que dejan `current.txt` byte a byte igual y sin restos, más un instalador **matado** a mitad cuyo journal se recupera. `test-install-flow` (43): el `install.ps1`/`uninstall.ps1` reales en modo `-Sandbox` (instalar → verificar → actualizar → reinstalar el mismo paquete → paquete manipulado → desinstalar).
- **Pendiente (impide VERIFICADA):** primer arranque con el `ii-host`+`quickshell` reales y un paquete completo (`make-package` no se ejecutó: faltan `dist/` y `build/ii` de una instalación de desarrollo); disco lleno real; binario incompatible; instalación sobre una instalación plana real; archivos en uso fuera de la prueba del bloqueo. La versión activa **no** se puede borrar mientras corre (se retira en la actualización siguiente).
- **Riesgos / rollback:** el plazo de verificación del launcher es 180 s (frío con compilación de QML); `Invoke-IiRollback` y borrar `current.txt` (vuelve al modo plano) son los rollbacks manuales. `git revert b465360`.

### ID: R08 — Preservar propiedad y decisiones del usuario entre upgrades

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (commit `b465360`):** `tools/package/ii-changes.ps1`: cada cambio externo guarda original (existía/tipo/valor exactos), lo aplicado y dueño; un valor ausente se crea y es de ii; uno **existente no se toma** (aunque iguale al recomendado) salvo que se pida con `-TakeOver`, que registra el original antes; un valor propio no se confunde con el original del usuario en una actualización; si el usuario lo cambió después, su elección manda y ii deja de reclamarlo; restaurar solo devuelve el original si el valor sigue siendo el que puso ii. Aplicado a GPU (una entrada por versión), cursores (por valor y con tipo; sustituye al `cursors.json`, que se sigue entendiendo para instalaciones antiguas restaurando solo lo que apunta a la carpeta de ii) y clave Run; los manifests antiguos (`gpuPreference`, entrada Run) se migran. Host: `theme::restore` no pisa un valor que ya no es el que ii escribió y `banners::restore` no apaga de nuevo un banner que el usuario encendió; `ii-rescue.ps1` respeta lo mismo en banners.
- **Pruebas (PASS):** `test-changes` (36) sobre una clave desechable de HKCU: ausente/preexistente/propio/modificado por el usuario/borrado por el usuario, String/DWord/ExpandString/Binary byte a byte, tres ciclos instalar-desinstalar sin acumular nada, manifest anterior a `changes[]` (reclamado solo si el valor sigue siendo el de ii), y el flujo real de `install.ps1`/`uninstall.ps1` en `-Sandbox` (`test-install-flow`).
- **Pendiente (impide VERIFICADA):** el restore condicional del host (`theme.cpp`, `banners.cpp`) compila pero no tiene prueba propia (tocaría el tema y los banners reales del usuario); tema/cursor/fuentes/PATH reales no se ejercieron de punta a punta; recuperación tras una restauración interrumpida a medias.
- **Rollback:** `git revert b465360`.

### ID: R11 — Unificar secretos y limpiar temporales/datos sensibles

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (ii: commit «R11: Gelbooru key…»; fork `55b6813`):** la clave de Gelbooru sale de `config.json` al almacén por usuario (DPAPI, el mismo de las claves de IA) con migración verificada (copiar, **releer del archivo cifrado**, solo entonces borrar la copia en claro; si algo falla se conserva y se reintenta) y comando `/gelbooru <id> <clave>`; `ii-shim ai-request` borra su archivo de petición (contiene el prompt; la credencial nunca estuvo: las cabeceras citan variables de entorno) en cuanto lo lee y barre `request.*.json` propios con más de 1 h (máx. 50 por llamada, solo ese patrón); `ii-report.ps1` redacta por defecto credenciales de cualquier forma (Authorization, apiKey, `api_key=`, `sk-…`, `ghp_…`), texto de avisos y de chat, más usuario/equipo/ruta personal (`-IncludePrivate` lo desactiva salvo la identidad); el fork ya no escribe el resumen de un aviso en el log (`QS_LOG_NOTIFICATION_TEXT=1` lo restablece).
- **Pruebas (PASS):** `test-airequest` (12) con un servidor HTTP local: cabecera expandida desde el entorno, archivo de petición borrado (también si la petición falla), barrido de caducados sin tocar archivos ajenos ni de nombre parecido; `test-report-redaction` (16) con centinelas de token, clave, texto de aviso y de chat; el parche de secretos aplica al árbol (staging) y `qmllint` no halla errores de sintaxis en `Booru.qml`/`Anime.qml`.
- **Pendiente (impide VERIFICADA):** la migración QML de la clave no se ejecutó en una shell real; errores DPAPI/IO, perfil distinto, valor viejo corrupto; archivos `request` huérfanos tras un crash de verdad; permisos de archivos; redacción de chats en los logs de la propia shell (hay `console.log` de mensajes en `Ai.qml` upstream sin revisar).
- **Rollback:** `git revert` de los dos commits; la clave sigue funcionando desde `config.json` si el almacén no la tiene (lectura de respaldo).

### ID: P04 — Eliminar animación decorativa perpetua del placeholder media

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (commit «P04: the idle media placeholder is still…»):** `MediaWidget.qml` (overlay): sin música el placeholder es **estático** por defecto (nota musical sobre una forma Material); solo hace un asentamiento breve (escala) cuando aparece o cambia el estado. La decoración continua (giro + cambio de forma cada 4 s) pasa a ser opción explícita `background.widgets.media.idleMotion` (apagada) y, aun activada, se detiene con «Reducir movimiento» (`appearance.reduceMotion`, interruptor nuevo en Ajustes › Widgets del escritorio), con la sesión bloqueada y con el escritorio cubierto. Reproducción, carátula, controles y espectro no cambian. No había un valor antiguo que migrar (antes siempre animaba): ninguna preferencia retirada deja una animación oculta. Parches: `patch_ii_widgets.py` (propiedades de configuración y los dos interruptores).
- **Pruebas:** el parche aplica al árbol; `test-qml-lint` (3 aserciones, `qmllint`) no halla errores de sintaxis en los 40+ archivos QML que cambian el overlay y los parches.
- **Pendiente (impide VERIFICADA):** medir en Windows el escritorio sin reproducción con el widget visible antes/después (frames, CPU/GPU), y comprobar visualmente el asentamiento al pasar play↔pausa; configuración antigua, lock/resume y cubrir/descubrir no se ejercieron con la shell real.
- **Rollback:** `git revert` del commit.

### ID: P11 — Basar temporizadores en tiempo real y limitar refresh visual

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Hallazgo:** `TimerService` ya guardaba marcas de tiempo (no contaba ticks); lo que faltaba era el refresco de cronómetro (10 ms) y pomodoro (200 ms) aunque nadie lo viera, y no había defensa frente a un ajuste del reloj. (El sello del cronómetro es una propiedad `int` de 32 bits: la resta sigue siendo correcta por aritmética modular hasta 248 días; ahora se hace explícito con `| 0`.)
- **Cambios (ii: `f888b8a`; fork: `889c2a1`):** `Quickshell.Win32.MonotonicClock` (fork): `QueryInterruptTime`, que **sí cuenta el tiempo dormido/hibernado** (`QueryUnbiasedInterruptTime`/contadores que paran en suspensión harían volver tarde un pomodoro; si la API no existe se cae a `GetTickCount64` y `includesSleep()` lo dice). `patch_ii_timers.py`: si el reloj de pared se ajusta (usuario, sincronización) mientras un temporizador corre, sus marcas se desplazan lo mismo (no aparece ni desaparece tiempo ni sale negativo); suspender cuenta como tiempo transcurrido y un pomodoro que terminó durmiendo termina **una vez** al despertar; el cronómetro se refresca (33 ms, muestra centésimas) solo si hay una vista en pantalla y el pomodoro cada segundo si se ve o, si no, despierta cerca del fin de la vuelta (≤30 s para notar cambios de reloj) de modo que la alarma sigue llegando a tiempo; sin escrituras a disco por tick.
- **Pruebas (PASS):** `test-qs-smoke` (4 aserciones) con el `quickshell.exe` compilado: el reloj monótono no retrocede, `includesSleep=true` y sigue al reloj de pared dentro de 150 ms en ~2 s; `qmllint` sin errores de sintaxis en `TimerService`/`Stopwatch`/`PomodoroTimer`.
- **Pendiente (impide VERIFICADA):** la lógica QML de `TimerService` (ajuste de reloj, un solo aviso tras dormir, parada del refresco al ocultar, reapertura con configuración persistida) no se ejecutó: requiere la shell con `Persistent`/`Config` reales; comparar contra un cronómetro de referencia y dormir de verdad el equipo no se hizo (no se suspende la sesión del usuario).
- **Rollback:** `git revert f888b8a` (ii) y `889c2a1` (fork).

### ID: P12 — Sustituir sondeo redundante y mantener hook barato

**Estado:** EN_CURSO
- **Hecho (el hook):** dentro del callback ya no hay `GetForegroundWindow`/`GetClassName`/`GetWindowRect`/`GetMonitorInfo` ni `FindWindow` por tecla: lee estado cacheado (átomos) que se refresca **fuera** del hook con un `WinEvent` de primer plano, la reconciliación de 1 s y los cambios de sesión (`WTSRegisterSessionNotification` ⇒ reinicia el estado tras bloquear/desbloquear/cambiar de sesión); el seguimiento de Ctrl/Alt/Mayús es propio, izquierda/derecha por separado, y `GetAsyncKeyState` solo se usa para curar una pulsación o un «soltar» perdidos y nunca para la tecla que se está procesando (cuyo estado el sistema aún no actualizó). El sondeo de disponibilidad de la shell tiene un tope de una búsqueda cada 250 ms. Además el host ahora sondea cada 250 ms **solo** hasta que la shell esté lista (antes 5 s) y luego baja a 5 s; la comprobación de salud va a 1 s con coste de un `GetTickCount64`.
- **Pruebas:** `ii-keyrouter-test` (48) para la lógica; el coste del callback bajo carga no se midió.
- **Pendiente:** inventario de cada temporizador (función, coste, consumidor, señal disponible) en host y fork, con eventos de sesión/pantalla/Explorer/layout donde sean fiables; el fallback de cursor de 250 ms se conserva y no se tocó; duración del callback con carga, Win solo/alt-tab rápido/input inyectado/reinicio de Explorer, y detección de un evento perdido; AppBar/InputRegions y keyboardlayout del fork.

### ID: P15 — Hacer splash barato y retirarlo por readiness real

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios (commit `33479f8`):** la shell se lanza antes de decodificar el fondo (`splash::show` crea ventanas de color plano, `loadImages` decodifica después); cada cubierta se retira cuando **su** pantalla ya muestra la shell (+700 ms), las pantallas que nunca la reciben pierden su cubierta 10 s después de que otra esté lista; un solo ventana de control posee los temporizadores; el repintado del indicador usa solo su rectángulo y un buffer del tamaño de lo sucio (antes: bitmap a pantalla completa cada 33 ms); aviso de demora a los 15 s.
- **Pruebas:** compila y los caminos sin splash están cubiertos por las pruebas del host (`--no-splash`); **el splash visible no se ejecutó** (cubriría el escritorio del usuario).
- **Pendiente (impide VERIFICADA):** medir CPU durante el arranque y tiempo proceso→interactivo antes/después (B02 real), 4K doble, fondo enorme/ausente, monitor lento, QML que no renderiza. No se retira por «entrada esencial» (solo por cobertura); eso necesita el mensaje `readiness` de la shell (fork).
- **Rollback:** `git revert 33479f8` (en conjunto con R02/R05, mismo commit).

### ID: P17 — Conservar caché QML y hacer reproducibles builds Windows Release

**Estado:** EN_CURSO
- **Hecho:** `CMakePresets.json` en el fork (commit `b8cb811`): `windows-release` (Release explícito, clang-cl, Ninja, servicios Linux apagados, `DISTRIBUTOR` y `CRASHREPORT_URL` apuntando a este proyecto en vez del upstream de Quickshell) y `windows-debug` solo para diagnóstico. El fork compila entero con ese preset (518 pasos, 0 errores) contra Qt 6.12 oficial y clang-cl 23.1.3.
- **Pendiente:** manifiesto de build (commits, flags, hashes, dirty) dentro del paquete; `deploy.ps1`/`make-package.ps1` ligados todavía a la ruta de Visual Studio y a `quickshell\build`; manifiesto incremental de assets; inventario de dependencias/licencias (CLI11 nuevo en la cadena); prueba de caché caliente/invalidada por cambio de QML; CI de Windows.
- **Nota:** no se afirma que el release anterior fuera Debug; solo que el default de CMake lo era.

### ID: U01 — Crear catálogo de acciones/capacidades y política de UI ii

**Estado:** EN_CURSO
- **Hecho (solo teclado):** `shared/actions.json` es la única lista de las acciones de teclado de ii, con id, texto, grupo, destino, **estado de soporte** (`available`/`partial`/`external`/`unsupported`) y **motivo obligatorio** para todo lo que no sea completo (el generador falla si falta). De ella salen, con `tools/dev/gen-actions.py`, la tabla que traga `ii-host` (`shortcuts_table.inc`), la chuleta de la shell (`HyprlandKeybinds.qml`) y `docs/ATAJOS.md`. `test-actions` falla si un archivo generado se desvía del catálogo, si una acción de shell que se traga una tecla no tiene `GlobalShortcut` en el QML, si ii se traga una combinación que Windows necesita (Win+L, Ctrl+Alt+Supr, Win+E, Win+P, Alt+Tab, Ctrl+Mayús+Esc) o si un límite no está explicado. Inventario de rutas Linux vivas: `docs/INVENTARIO-RUTAS-LINUX.md` (ver C12).
- **Pendiente:** el catálogo no cubre todavía tiles de ajustes rápidos, menús, IPC, errores ni `FileDialog`/`ChooseColor`; no hay política de «identidad ii» con lista de excepciones protegidas ni auditoría `rg` de `ms-settings:`/ejecutables/diálogos; los controles no disponibles de los tiles (U05) siguen sin explicar su causa.

### ID: U02 — Enrutar atajos completos con política por aplicación

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios:** los atajos de ii **ya no ceden ante una ventana maximizada** (antes cualquier ventana que cubriera el monitor los desactivaba y, con la barra oculta por ii, eso incluía un navegador maximizado: Win volvía a abrir Inicio). Política (`keyrouter.cpp::shouldYield`, regla en `%LOCALAPPDATA%\ii-windows\shortcuts.ini`): `auto` (por defecto) cede ante pantalla completa exclusiva/modo presentación y ventanas sin borde a pantalla completa, salvo navegadores; `geometry` es el comportamiento antiguo; `never` nunca cede; `[yield] processes=` fuerza ceder (perfil de juego) y `[keep] processes=` nunca; un `[yield]` explícito gana a `never`. El pánico (Ctrl+Alt+Mayús+R) es un `RegisterHotKey` del host: funciona incluso con los atajos cedidos. Nuevos/arreglados: Win+I → ajustes de ii (`ExtraShortcuts.qml`), Win+R → búsqueda de ii, Win+T → vista de ventanas (antes se tragaba sin hacer nada), Win+X → menú de sesión, Impr Pant → captura de región; Win+P/E, Alt+Tab, Ctrl+Mayús+Esc, Win+L siguen siendo de Windows y el catálogo dice por qué.
- **Pruebas (PASS):** `ii-keyrouter-test` (48 comprobaciones): Win solo (abre búsqueda y enmascara el Start), Win+S, Win+Z (no se enmascara), Win+número/Mayús/Ctrl, las combinaciones nuevas, modificadores izquierdo/derecho, Alt+F4 en el escritorio, Ctrl+Esc, sin shell, cediendo, Win o Ctrl cuyo «soltar» se perdió, Win seguido de un modificador, que **cada entrada de la tabla se alcanza a sí misma**, y la decisión de ceder (navegador maximizado no, juego sin borde sí, navegador en F11 no, exclusiva sí, `[yield]`/`[keep]`/políticas). `test-actions` (12).
- **Pendiente (impide VERIFICADA):** no se ejercitó con un teclado real ni con US/ES/OEM, autorepeat, juego real, ventana elevada (UIPI), RDP ni bloqueo/reanudación; la clasificación de primer plano (`SHQueryUserNotificationState`, estilos de ventana) solo está comprobada como lógica; Win+B sigue siendo el panel izquierdo (foco en bandeja necesita U06); Alt+Tab propio es U03.
- **Rollback:** `git revert` del commit; `shortcuts.ini` con `fullscreen=geometry` devuelve la cesión antigua sin recompilar.

### ID: C12 — Corregir pin, idiomas y rutas Linux residuales vivas

**Estado:** IMPLEMENTADA_SIN_VALIDAR_WINDOWS
- **Cambios:** `patch_ii_c12.py`: el **pin** del panel izquierdo es solo el estado (se acabó mover el cursor con `hyprctl cursorpos`/`dispatch` y arrancar tres procesos); la **lista de idiomas** se lee con `FolderListModel` sobre la carpeta real (solo archivos `xx_YY.json`; `tools/` no cuenta), no con `find`/`basename`; el idioma que se carga se **resuelve** contra los archivos que existen (`es_CO` → `es_MX` si no hay `es_CO.json`, si no inglés; se vuelve a resolver cuando termina el escaneo) con `overlay/.../LanguageResolve.js`; `Directories.qml` dejaba sin efecto `bash -c "rm -rf …; mkdir -p …"` (el `bash` del shim no es un intérprete) y ahora usa `ii-shim reset-dir`; `ii-shim` aprende `mkdir`, `rm`, `reset-dir` y `which` (`host/src/fsutil.cpp`), restringidos a carpetas del propio usuario (profundidad mínima, sin atravesar enlaces, sin `..`, nunca la raíz de una unidad); `tools/dev/scan-linux-routes.py` + `docs/INVENTARIO-RUTAS-LINUX.md` clasifican las llamadas a comandos Linux que siguen vivas por quién las atiende.
- **Pruebas (PASS):** `test-language` (26) ejecuta el `LanguageResolve.js` real bajo Node (fallbacks, normalización, carpeta real de upstream); `test-shim-files` (23) con un perfil **falso** (USERPROFILE/LOCALAPPDATA/APPDATA/TEMP apuntando a una carpeta temporal, así que un fallo de las reglas no puede tocar el perfil real): crear/borrar, rechazo de carpetas de primer nivel, de lo externo y de `..`, junction dentro de una carpeta que se vacía, `which`; `test-linux-routes` (8): ningún comando Linux nuevo sin proveedor (quedan `file`, `identify`, `hyprctl`, cada uno atado a su tarea) y `find`/pin siguen retirados; `qmllint` sin errores de sintaxis.
- **Pendiente (impide VERIFICADA):** pin con ratón/teclado, selector de idioma con archivos reales, cambio de idioma en caliente y es-CO/es-MX en la shell real; las 60 llamadas a `bash` del inventario (cada una puede estar inerte) y los warnings por undefined/null se revisan tarea a tarea, no aquí.
- **Rollback:** `git revert` del commit.

### ID: F01 — Cambiar logo Fastfetch y dejar de imponerlo desde el wrapper

**Estado:** VERIFICADA
- **Cambios (commit «F01: an 'ii' logo…»):** `extras/fastfetch/ii-logo.txt` es ahora un monograma «ii» compacto (dos tildes redondeadas y dos troncos de cinco filas, con el color 1 de la paleta de ii) y `ii-logo-ascii.txt` su variante en ASCII para consolas sin Unicode; `ii.jsonc` muestra el nombre y la **versión** del port con el módulo `command` (`II_VERSION`, «dev» si se ejecuta a mano) sin tocar la identificación del sistema (`os`, `uptime`, `terminal`… siguen siendo reales). `bin/fastfetch.cmd` ya no fuerza el logo viejo: **línea de comandos > configuración del usuario (`II_FASTFETCH_CONFIG` o `%LOCALAPPDATA%\ii-windows\fastfetch.jsonc`) > la de ii**; con `-c` no se añade nada, con `--logo`/`-l`/`--logo-*` no se añade el logo; elige el logo ASCII si no hay Windows Terminal ni consola UTF-8 (`II_FASTFETCH_ASCII=1` lo fuerza); resuelve la versión activa por `current.txt`; sin `fastfetch.exe` dice que no está y sale con 1 (el perfil de Terminal usa `-NoExit`/`cmd /k`, así que no hay bucle ni terminal rota). PNG/Sixel quedan documentados en `ii.jsonc` como opción de fastfetch según terminal. Los perfiles de Windows Terminal existentes no se tocan.
- **Pruebas (PASS):** `test-fastfetch` (15 aserciones) con el `fastfetch.exe` 2.69 real desde un árbol temporal: logo por defecto reconocible (5 filas de tronco), línea de shell con versión, ASCII forzado y en consola no UTF-8, `--logo none` sin logo, `-c`, `II_FASTFETCH_CONFIG`, archivo de usuario y su precedencia, versión activa de `current.txt`, y ausencia de fastfetch.
- **Pendiente (aceptado):** revisión visual humana de la alineación en distintos tamaños de terminal; Windows Terminal/consola clásica distintas de las de este equipo; rutas de instalación con Unicode.
- **Rollback:** `git revert` del commit; el logo antiguo estaba en `ii-logo.txt` de `22dec54`.
