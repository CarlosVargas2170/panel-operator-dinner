# Mesero 06 · Centro de operación local completo V13.9

Este paquete consolida el **servidor y las ofertas de la V13.8** con el **HTML más reciente de la V13.9 (atajos asignables a acciones)**. Es el entorno de prueba local de Windows; **no despliega ni reemplaza** la aplicación Flutter ni el controlador oficial del robot.

## Qué contiene

| Archivo | Uso |
|---|---|
| `ABRIR_CONTROL_MESERO06.bat` | **Único iniciador habitual**, confirma `SI` y abre el centro local |
| `mesero06_local_v13.py` | Servidor local: voz TTS, audios, GIF, ofertas, catálogo, ventas y rutas HTTP del control |
| `mesero06_drive_bridge.py` | Conexión Socket.IO al controlador oficial, WASD, estado STM32, límite RPM, STOP y watchdog |
| `mesero06_panel_glass_v13.html` | Interfaz V13.9 con el nuevo editor de atajos de las acciones |
| `mesero06_camaras_2.html` | Visor independiente de dos vistas del video compuesto |
| `HERRAMIENTAS/INSTALAR_SOCKETIO_SI_FALTA.bat` | Instala `python-socketio[client]` **solo si lo pide el iniciador** |

## Requisitos ya instalados o que debes tener

- Windows con **Python 3.10 o posterior** disponible como `python` en CMD.
- **Tailscale** conectado a la misma red privada del robot.
- Robot Mesero 06 encendido, con sus servicios existentes en la IP `100.87.64.123`.
- Socket.IO en Windows (`python-socketio[client]`), que se instala una única vez cuando haga falta.
- Para texto a voz: token **oficial** del servicio de TTS, que se introduce en el CMD cuando el programa lo solicite. No se incluye en este archivo ZIP ni se coloca en la página web.

**Servicios existentes en el robot**, a los que se conecta la aplicación: controlador Socket.IO `:5000`; API de `mini_app_qr` `:5050`; MediaMTX WebRTC/HLS `:8889`/`:8888`; TTS `:9000`. El archivo ZIP **no instala** ni modifica esos servicios.

## Iniciar

1. Extrae el ZIP completo.
2. Entra a `CENTRO_LOCAL_MESERO06`. No mezcles sus archivos con otra versión.
3. Cierra CMD anteriores del Mesero 06 con `Ctrl+C`.
4. Haz doble clic en **`ABRIR_CONTROL_MESERO06.bat`**. No necesitas abrir los scripts Python por separado.
5. Si avisa que falta `python-socketio`, ejecuta **una sola vez** el instalador dentro de `HERRAMIENTAS` y vuelve al paso 4.
6. Para habilitar el modo de prueba física, confirma **`SI`** en CMD cuando te lo pida. Se requiere zona despejada, parada física disponible y supervisión. Si no quieres habilitarlo, cancela el BAT y no arranques una versión de movimiento.
7. Cuando pida token TTS, ingrésalo de forma oculta si quieres usar el cuadro de voz; Enter lo omite y deshabilita la autorización para voz escrita.
8. Abre `http://127.0.0.1:8765/` si no se abrió automáticamente.

**Nunca abras dos BAT simultáneamente.** Si el puerto `8765` está ocupado, cierra el CMD anterior y vuelve a abrir el correcto.

## Operación y atajos

- **Cámaras:** el visor principal muestra las cuatro cámaras compuestas y tiene pantalla completa. El visor de dos vistas también está disponible en `http://127.0.0.1:8765/camaras`. La conexión audiovisual usa Tailscale y MediaMTX.
- **Movimiento real:** pulsa `Tomar control REAL`, consulta el **modo físico STM32**, cambia por la acción oficial si está AUTÓNOMO/RC y comprueba `TELEDIRIGIDO`. El simulador no es el modo físico. El movimiento exige imagen WebRTC **nativa** reciente, ventana enfocada y sesión exclusiva. Empieza en **5 RPM** y la interfaz puede aumentar hasta **30 RPM**. El control original puede aplicar límites menores a giros y retroceso. El botón STOP y el paro físico deben seguir accesibles.
- **Caritas:** sección Caritas con las expresiones base que usa Flutter mediante `/attract/set`. La sección Halloween/Navidad puede contener elementos pendientes de identificar; no asumir que todos los GIF ya funcionan físicamente.
- **Música y audios:** biblioteca de sonidos con búsqueda y detener. Algunos audios están identificados, otros figuran como «falta vincular» hasta confirmar su archivo real. No necesitas copiar audios al PC: residen en `mini_app_qr` del robot.
- **TTS escrito:** `Voz / TTS` o `Escribir TTS`. El texto requiere el token oficial, a diferencia de los audios de Flutter. Diagnóstico: `http://127.0.0.1:8765/api/tts/diagnostic`.
- **Ofertas:** en Acciones, **☕ Ofrecer café**, **Café + imagen**, **Ver productos**, **Mostrar producto en robot**, saludos y avisos. La orden de oferta usa la API existente del robot. Si suena el saludo pero no se muestran productos, hay que revisar el producto/comercio que Flutter tenga seleccionado. La aplicación original puede seguir mostrando avisos de pantalla en determinados flujos.
- **Ventas:** «Ventas en vivo» y «Ver resumen» consultan la API actual de `mini_app_qr`; puede mostrar cero cuando el contador acaba de reiniciarse. La asignación a piloto depende de las identificaciones disponibles.
- **Atajos V13.9:** entra a **Acciones → Editar acciones y teclas → Asignar tecla**. Puedes asignar una letra libre a «Café + imagen» u otra acción, por piloto; no se permiten duplicados con WASD, STOP, TTS y menús. También se conservan nombres y emojis, y opciones de ocultar/mostrar.

Las preferencias de atajos, favoritos y elementos visibles se guardan **en el navegador local y por perfil**. No equivalen a una sincronización en Render ni a un respaldo externo.

## Pruebas recomendadas

1. Verifica cámaras y actualización de imagen; mantén el robot detenido.
2. Revisa `http://127.0.0.1:8765/api/local/status`.
3. Revisa `http://127.0.0.1:8765/api/drive/status` antes de tomar control.
4. Si quieres voz escrita, comprueba el diagnóstico TTS y realiza una prueba corta.
5. Verifica una carita base (Feliz → Normal) y luego música y STOP de audio.
6. Verifica el botón de café cuando Flutter esté en una pantalla apropiada y no haya pago en curso.
7. Asigna un atajo libre y prueba solo esa acción con el robot detenido.
8. Para prueba física, verifica modo real y parada al soltar teclas o perder enfoque/cámara antes de aumentar velocidad.

## Solución de problemas

| Síntoma | Qué revisar |
|---|---|
| «Socket.IO no instalado» | Ejecutar `HERRAMIENTAS/INSTALAR_SOCKETIO_SI_FALTA.bat` **una vez** |
| «Puerto 8765 ocupado» | Cerrar el CMD anterior con Ctrl+C; no abrir dos versiones |
| «Modo desactivado» | Asegurarte de haber usado el BAT correcto y confirmado `SI` |
| «No mueve / DESCONOCIDO / AUTÓNOMO» | Leer `/api/drive/status`, consultar modo físico y comprobar TELEDIRIGIDO y cámara WebRTC nativa; no eliminar protecciones |
| «Otro navegador tiene el control» | Liberar el control desde la sesión anterior, no forzar una segunda sesión |
| «Audios funcionan, TTS no» | Token oficial en CMD y `/api/tts/diagnostic`, servicio `:9000` |
| «Falta vincular» | El archivo real no está mapeado o verificado; no significa que haya desaparecido de Flutter |
| «Café suena pero no aparece catálogo» | Comprobar comercio y producto configurados en `mini_app_qr`; «Ver productos» consulta el catálogo del panel |
| «Atajo no se guarda» | Recargar `Ctrl+F5`, abrir editor del piloto adecuado, evitar tecla duplicada |

## Seguridad y alcance

- El servidor se escucha solo en `127.0.0.1:8765`. **No publicar en Internet ni sustituir por un servicio Render de acceso público.**
- El robot ya tiene su propio controlador. No moverlo sin estar presente, con la vía despejada y la parada física disponible. Las pruebas a 30 RPM requieren especial cuidado.
- Este paquete **no contiene credenciales, tokens, audio ni datos sensibles** del robot.
- Los cambios de caras, música y movimiento dependen de servicios externos que tienen que estar funcionando en el Mesero 06.
- Las pruebas automatizadas de este paquete no sustituyen una prueba física ni garantizan que todas las expresiones y ofertas pendientes estén vinculadas.
