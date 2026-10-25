# Publicar una versión de ii-windows

Lista de pasos para cada versión (plan 1.4: antivirus y SmartScreen). Lo automático lo hace `tools\package\make-package.ps1`; lo demás es a mano.

## 1. Construir

1. `cmake --build host\build-clang` y `cmake --build quickshell\build-r` (ver `tools\dev\vsenv-portable.ps1`).
2. `tools\dev\deploy.ps1 -Build quickshell\build-r` (necesita `fonttools` en el Python base: `python -I` no ve los paquetes `--user`).
3. `tools\dev\stage-ii.ps1`.
4. `tools\sandbox\run-local-suite.ps1`: todas en verde, o cada fallo explicado.
5. `tools\package\make-package.ps1`. Toma el host compilado más reciente (`host\build-clang` o `host\build`), firma los programas propios, escribe el manifiesto, hace el `.zip` y deja `release-check.md` dentro del paquete.

## 2. Firmar

Sin firma, SmartScreen avisa "Windows protegió su PC" y los antivirus desconfían más de un ejecutable nuevo. `tools\package\sign.ps1` firma (SHA-256, con sello de tiempo) solo los programas de ii-windows: `ii-host`, `ii-launcher`, `ii-shim` y sus copias, y `quickshell.exe`. Las DLL de Qt, fastfetch y el runtime de Microsoft conservan la firma de quien los hizo.

El certificado nunca va en el repositorio. Se da por variables de entorno:

| Variable | Qué es |
|---|---|
| `II_SIGN_THUMBPRINT` | Huella de un certificado de firma de código del almacén de Windows (token físico, cliente de Azure Trusted Signing o certificado de una CA). |
| `II_SIGN_PFX` y `II_SIGN_PFX_PASSWORD` | Un `.pfx`, por ejemplo en los secretos de una CI. |
| `II_SIGN_TIMESTAMP` | Servidor de sello de tiempo (por defecto `http://timestamp.digicert.com`). |

Sin ninguna de ellas el paquete sale **sin firmar** y lo dice: sirve para probar, no para publicar.

De dónde sacar un certificado:

- **SignPath Foundation**: firma gratuita para proyectos de código abierto. Se solicita en su web con el repositorio público; firman desde su CI con un certificado a nombre de la fundación.
- **Azure Trusted Signing**: de pago (unos pocos dólares al mes) y con verificación de identidad. Se usa con su cliente local y `II_SIGN_THUMBPRINT`.
- **Certificado OV/EV de una CA**: de pago. Un EV quita el aviso de SmartScreen desde el primer día; uno OV acumula reputación con las descargas.

## 3. Comprobar (`release-check.md`)

`tools\package\release-check.ps1 -Strict` falla si hay algo que una versión publicada no debe tener:

- un `.exe` sin datos de versión (nombre, descripción, empresa, versión);
- un ejecutable empaquetado (UPX y similares: ii nunca usa empaquetadores, son una causa clásica de falsos positivos);
- un programa propio sin firma;
- una detección en VirusTotal (con `VT_API_KEY` se consulta cada hash; no se sube nada).

## 4. Antivirus

1. Sube el `.zip` a VirusTotal (web) y revisa el informe. Si un motor lo marca, repórtalo como falso positivo en el portal de ese fabricante.
2. Envía el `.zip` y los `.exe` propios al portal de envío de archivos de Microsoft (Defender): https://www.microsoft.com/en-us/wdsi/filesubmission, como "software legítimo / falso positivo", en **cada** versión. Con la firma, la reputación pasa de una versión a la siguiente.

## 5. Probar en máquinas reales

Lo que las pruebas automáticas no cubren:

- osu! y Valorant de verdad: la tecla Windows y que el gancho se quite con el anticheat.
- Una laptop con NVIDIA (por ejemplo una 5070 Ti): el lag y la preferencia de GPU.
- Wallpaper Engine con la pausa activada.
- Un juego pesado que congele la shell: el latido fuera de las pruebas simuladas.
- "Junto al dock" en una pantalla pequeña con muchas apps, con la barra de tareas de Windows oculta (como funciona ii instalado).
- Alt+Tab propio sobre apps normales y sobre un juego (debe quedar el de Windows).

## 6. Publicar

Fusionar primero la rama del fork (`quickshell-windows`) y después la de ii-windows. Publicar el `.zip`, el `release-check.md` y las notas de la versión (`docs/RELEASE-x.y.z.md`).
