# Seguridad de despliegue

- No versionar `.env`, tokens de TTS, credenciales Tailscale, panel tokens, cookies ni contraseñas.
- Guardar `MESERO06_TTS_TOKEN` **solo en Environment de Render o Secret Manager del servidor Nexus**.
- Requiere HTTPS, una sesión por operador, CSRF y un backend con acceso Tailscale autorizado.
- El backend actual es **un solo proceso por robot**; no escalar a varias instancias sin reemplazar el lease por almacenamiento compartido con bloqueo distribuido y watchdog dedicado.
- STOP y los failsafes del hardware deben mantenerse activos; verificar físicamente las órdenes antes de producción.
- Para los operadores, la regla de acceso a Tailscale se configura y verifica en infraestructura/identidad; un login web por sí solo no prueba pertenencia a la tailnet.
