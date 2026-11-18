# Lista de aceptación del Mesero 06

La prueba automatizada local es **offline**: puede verificar rutas y seguridad, pero no certificar STM32, audio del robot ni movimiento real. Aprobar cada componente en orden:

1. **Sesión**: sin login no hay acceso; credenciales inválidas rechazadas, salida de sesión controlada.
2. **Tailscale**: el servidor tiene acceso a los servicios 5000/5050/9000 del Mesero 06.
3. **Control**: `drive/status` recibe realmente `connected`, `robot_mode`, `serial_connected` y confirmaciones `claim_control`. El mando no se recupera automáticamente después de reconectar.
4. **Parada**: STOP en reposo, parada durante movimiento, desenfoque, pestaña oculta y pérdida de heartbeat. Revisar STOP físico y sensores del robot.
5. **WASD**: solo con modo TELEDIRIGIDO y un operador; velocidad limitada por el controlador original. Sin vídeo reciente, casilla de supervisión presencial habilitada explícitamente.
6. **TTS**: `/health`, `/voices` y `POST /synthesize/play`, con token real en el servidor. Confirmar audio del altavoz.
7. **Flutter**: `/config`, `/products`, `/attract/set`, `/audio/play`, `/audio/stop`; comprobar GIF en pantalla física.
8. **Catálogos**: verificar que todas las imágenes, audio y productos guardados existan en la instalación del robot. Los archivos adjuntos son snapshots, no prueba de sincronización actual.
9. **HLS**: activar solo si Render/Nexus puede alcanzar Flussonic y revisar vídeo dentro del visor, latencia y carga de red.
10. **Producción**: revisar identidad/Tailscale de cada operador, backups, logs, secretos, seguridad de la red y evitar varios workers para un mismo robot.

Si un componente falla, dejarlo desactivado hasta documentar el contrato real. No convertir un error en un éxito ficticio.
