# Nexus Robotics · Mesero 06 | Panel web operativo

**Código web y backend que reutiliza los servicios originales de Mesero 06.** Repositorio de integración para un servidor Nexus con acceso autorizado a Tailscale. No modifica los servicios instalados en el robot ni el firmware STM32.

## Qué incluye

- Pantalla única existente: WASD, toma/liberación de control, velocidad, modos, TTS, caritas, audio, comercios, ventas y HLS opcional.
- Backend FastAPI `nexus_panel_app.py` con inicio de sesión, sesión firmada, CSRF, operador exclusivo, vigilancia de pérdida de conexión y despacho a los controladores originales `robot_local_06.py` y `mesero06_drive_bridge.py`.
- 57 audios, catálogos Halloween/GitHub y módulo `render_hls_proxy.py`.
- Configuración centralizada. **No incluye BAT, puentes de Windows, claves, secretos ni modo demo como servicio desplegado.**

## Estado exacto

**Integración implementada sobre las APIs originales, pero NO verificada contra el robot físico ni contra el servidor de Nexus.** El backend falla de forma cerrada cuando Tailscale/Socket.IO/STM32 no responden. La existencia de una URL o un botón no acredita que ese servicio esté disponible en producción.

## Puesta en marcha

1. Subir **los archivos descomprimidos** a un repositorio privado de GitHub. Nunca subir `.env` real ni tokens.
2. Desplegar en **servidor Nexus con acceso Tailscale** al `100.87.64.123`. Comprobar desde ese servidor, no desde tu PC, acceso TCP 5000, 5050 y 9000. El servidor debe ser un solo proceso por robot (`--workers 1`) para conservar exclusividad y watchdog.
3. Instalar dependencias: `pip install -r requirements.txt`.
4. Configurar variables de entorno tomando `.env.example` como **referencia de nombres**, sin copiar secretos al repositorio. Obligatorios: `PANEL_USER`, `PANEL_PASSWORD` (mínimo 12), `PANEL_SESSION_SECRET` (mínimo 32), `PANEL_PUBLIC_URL`, `MESERO06_TTS_TOKEN`. En Render las variables se añaden en **Environment**. El token TTS real va **solo** en la variable `MESERO06_TTS_TOKEN`; no se pega en este chat, en el HTML, en `.env.example` ni en GitHub.
5. Ejecución HTTP con proxy TLS terminado delante, por ejemplo `uvicorn nexus_panel_app:app --host 0.0.0.0 --port $PORT --workers 1 --proxy-headers`. El servicio debe servir HTTPS al operador.
6. Entrar con cuenta, consultar `/api/connection`, verificar respuestas reales de Socket.IO/STM32 y mini_app_qr, probar TTS/audio/Flutter y después STOP/WASD con robot físicamente supervisado. **Si no hay cámara reciente, el operador debe marcar explícitamente la casilla «Supervisión presencial confirmada».**

## Render: punto que puede impedir movimiento

El archivo `render.yaml` permite desplegar el servicio HTTP y login. **No incluye ni crea la conexión Tailscale de Render.** Si Render no está autorizado dentro de la tailnet, verás el panel pero el backend seguirá sin alcanzar al robot. La vía recomendada es que Nexus despliegue este repositorio en su servidor que ya tenga acceso a Tailscale. Si se utiliza Render, Nexus tendrá que aportar una conexión Tailscale autorizada desde el contenedor o la infraestructura y verificar sus ACL. Tener Tailscale en la PC del operador no concede acceso al servidor.

## HLS

Está **desactivado por defecto** (`CAMERA_HLS_PROXY_ENABLED=0`). Para habilitar después: `CAMERA_HLS_PROXY_ENABLED=1`, verificar acceso HTTP a Flussonic desde el backend y abrir `/ver-hls`. La ruta proxy es `/api/v3/video/SERBOT06/index.m3u8`. Se conserva la implementación original; no es necesario instalar GStreamer en el navegador.

## APIs originales conservadas

- Socket.IO: `MESERO06_SOCKET_URL` → `100.87.64.123:5000`, eventos observados `claim_control`, `release_control`, `control_input`, `emergency_stop`, `status_request`.
- Flutter / mini_app: `MESERO06_MINI_URL` → `100.87.64.123:5050`, rutas `/attract/set`, `/audio/play`, `/audio/stop`, `/products`, `/config`.
- TTS: `MESERO06_TTS_URL` → `100.87.64.123:9000`, `POST /synthesize/play`, header `Authorization: Bearer <MESERO06_TTS_TOKEN>` generado solo en el backend.

## Precauciones de operación

Una sesión de operador a la vez, sin liberación automática de control después de perder foco; sí STOP por pérdida de señales. El backend original detiene entrada motriz si no hay cámara reciente o supervisión confirmada, si pierde foco, si STM32 no confirma conexión o si el modo físico no es TELEDIRIGIDO. No desactivar watchdog ni protecciones del robot. El uso del servidor privado requiere cuentas/ACL de Nexus; no hacer público un despliegue que permita movimiento sin credenciales.

Para incorporar al portal `adminrobots.nexarobotics.org`, el equipo puede reutilizar la app FastAPI completa o llamar a sus rutas desde su backend oficial. Debe adaptar autenticación/roles, asegurar que el usuario tenga acceso permitido, y migrar las variables de entorno.

**Audios y TTS:** un usuario autenticado puede utilizarlos sin tomar control de motores siempre que no exista otro operador activo. El control WASD sí exige Tomar control.

---

## PANEL ROBOT MULTIRROBOT - Nexus

**Rama:** feat/panel-robot-multirrobot

### Modificaciones realizadas

Se incorporo una version del panel operador para controlar robots meseros mediante su IP local o Tailscale.

Las principales funciones de esta version son:

- Control WASD, STOP y modos de operacion.
- Visualizacion de camaras y funciones TTS.
- Gestion de caritas, audios y comercios.
- Seleccion de comercio y producto mediante su ID unico.
- Integracion del boton Ofrecer con el endpoint POST /operator/show-product de Mini QR.
- Apertura del selector de comercios mediante POST /merchants/show.
- Atajos personalizables para pilotos.
- Conservacion de las funciones originales del panel.

### Seleccion directa de productos

El panel puede solicitar que Mini QR abra el catalogo de un comercio directamente en la pagina del producto seleccionado.

Ejemplo:

POST /operator/show-product

{"merchantId":84,"productId":455}

El cliente puede continuar navegando por los demas productos y realizar una compra normalmente.

Esta funcion requiere una version de Mini QR que implemente el endpoint indicado.

### Alcance

Los cambios corresponden al panel operador y su integracion con Mini QR. No se modifican los controles fisicos STM32 ni la logica interna de pagos.

Las funciones deben verificarse en cada robot compatible antes de su uso operativo.

### Autor

Atte. Alex

