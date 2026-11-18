# Integración oficial del Mesero 06

## No dependencias del operador

El navegador usa HTTPS y el backend llama a `100.87.64.123` desde el **servidor que ejecuta la API**. Ninguna PC necesita ejecutar un BAT. La regla de Nexus de exigir Tailscale al operador debe implementarse en su control de acceso/red; la autenticación web sola no verifica que tenga Tailscale.

## Configuración en Render (para integrar y probar la aplicación)

- Conecta el repositorio privado a un Web Service Python.
- Root Directory: vacío, porque los archivos del servidor están en la raíz.
- Build Command: `pip install -r requirements.txt`
- Start Command: `uvicorn nexus_panel_app:app --host 0.0.0.0 --port $PORT --workers 1 --proxy-headers`
- Health Check: `/healthz` (solo estado de servidor, no confirma robot).
- `PANEL_PUBLIC_URL`: URL HTTPS exacta del servicio (por ejemplo `https://panel-dinner-1.onrender.com`, si realmente se ha asociado este repo a ese servicio).
- Variables secretas: `PANEL_USER`, `PANEL_PASSWORD`, `PANEL_SESSION_SECRET`, `MESERO06_TTS_TOKEN`.
- Variables del robot: `MESERO06_SOCKET_URL`, `MESERO06_MINI_URL`, `MESERO06_TTS_URL`, `MESERO06_ENABLE_DRIVE`, `MESERO06_REMOTE_SUPERVISADO`.
- HLS apagado: `CAMERA_HLS_PROXY_ENABLED=0`. Se activa después con `1`.

**Render no recibe automáticamente acceso a Tailscale.** Se requiere asociar su backend a una tailnet autorizada o migrarlo al backend de Nexus que ya tiene acceso. Sin esa conectividad la interfaz funciona, pero las acciones del robot fallarán correctamente.

## Configuración en adminrobots.nexarobotics.org

El responsable puede alojar esta aplicación FastAPI como módulo independiente detrás del proxy autenticado de Nexus, o adaptar las rutas `/api/*` al backend del portal. Antes de integrarlo debe revisar sus roles, sus cookies y que no tenga varias instancias compitiendo por el control del mismo robot.

### Verificación desde EL SERVIDOR destino

Sin emitir movimiento:

1. Comprobar Tailscale conectado y permitido por ACL.
2. TCP a `100.87.64.123:5000`, `:5050` y `:9000` desde ese servidor.
3. Abrir panel HTTPS e iniciar sesión.
4. Comprobar `GET /api/connection`, `GET /api/drive/status`, `GET /api/mini/status`, `GET /api/tts/diagnostic` autenticados.
5. Confirmar `connected: true` y `serial_connected: true` antes de solicitar movimiento.
6. Verificar TTS/audios/GIF; por último probar STOP y WASD con supervisión física y área despejada.

**No** interpretar `/healthz: {ok:true}` como robot conectado.

## Token TTS

El nombre correcto es **`MESERO06_TTS_TOKEN`**. Guardar únicamente en un secret manager o en **Render → Web Service → Environment → Add Environment Variable**; valor completo del token oficial. El backend añade `Authorization: Bearer ...` al llamar a `http://100.87.64.123:9000/synthesize/play`. El token no llega al HTML ni al cliente. El `<meta name="local-tts-token">` del HTML es un token de protección CSRF por sesión, **no** la credencial oficial del TTS.

No compartir tokens por mensajes ni subir `.env`, HAR con cabeceras o capturas de secret managers a GitHub.
