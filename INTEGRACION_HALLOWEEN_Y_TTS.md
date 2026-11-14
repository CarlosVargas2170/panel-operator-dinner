# Integración pendiente en Mesero 06 · caras Halloween y TTS

> **Actualización (2026-11-13): las caritas Halloween ya vienen del backend.** La sección 1 queda obsoleta.
> El servidor local hace lo mismo que `control-remote-robot-mesero` (rama `feature/connect-backend`):
> 1. `GET {MESERO06_BACKEND_URL}/api/panel?robot=mesero-6` con `X-Panel-Token` → `emotions[{code,label,icon,gif_url}]`.
> 2. Al pulsar la carita: `POST :5050/attract/set {"gif": code, "url": gif_url}`. La app Flutter (rama `prod-v2-with-back`) descarga el GIF de Cloudinary y lo muestra.
>
> - El token del panel se pide oculto en el CMD (o en la variable `MESERO06_PANEL_TOKEN`). No va en el HTML.
> - Solo se aceptan GIF de `https://res.cloudinary.com`. El navegador envía solo el ID; la URL la pone el servidor.
> - La colección (Halloween, Navidad o Base) se deduce del código o del nombre (calabaza, fantasma, bruja…).
> - Copia sin conexión: `cache_caritas_backend.json`. Diagnóstico: `http://127.0.0.1:8765/api/mini/faces/diagnostic`.
> - Para agregar caritas nuevas, súbelas en `media.html` del panel web; aparecen en un minuto o con **Sincronizar caritas**.

Este ZIP está basado en la V15.1 y se contrastó con `control-remote-robot-mesero-main` proporcionado. Ese repositorio es el **panel web de todos los robots** y contiene audios. **No incorpora los archivos reales de las caritas Halloween** que el desarrollador indica que están instaladas en Mesero 06.

## 1. GIF Halloween

La V15.2 intenta descubrir inventario en el Flutter local del Mesero 06 (vía Tailscale):

```http
GET http://127.0.0.1:5050/attract/list
```

El desarrollador debe exponer, si no existe, un endpoint de sólo lectura que enumere los GIFs realmente instalados y admitidos por `POST /attract/set`, con esta estructura:

```json
{
  "success": true,
  "gifs": [
    {"id": "normal", "name": "Normal", "collection": "base"},
    {"id": "pumpkin", "name": "Calabaza", "collection": "halloween"},
    {"id": "ghost", "name": "Fantasma", "collection": "halloween"}
  ]
}
```

Los IDs del ejemplo **no se afirman instalados**. Deben coincidir con los ID de las caritas reales del Mesero 06 y estar disponibles en Flutter. La UI activa la carita mediante:

```http
POST http://127.0.0.1:5050/attract/set
Content-Type: application/json

{"gif":"pumpkin"}
```

Si lo instalado es una **pantalla HTML con `setEmotion('pumpkin')`** y no GIFs admitidos por Flutter, se requiere que el desarrollador exponga una API de su servidor que pueda enumerar y cambiar esas emociones. La API no está documentada en los ZIP recibidos; no se deben inventar endpoints ni controlar ese HTML mediante rutas asumidas.

Desde el panel local V15.2, visita `http://127.0.0.1:8765/api/mini/faces/diagnostic` para saber si la enumeración es compatible. Después pulsa **Caritas → Sincronizar caritas**. Los nombres y colecciones se llenan automáticamente sólo si Flutter lo confirma. No es necesario modificar GitHub para que el HTML local descubra esas caras si la API real está operativa.

## 2. STOP de TTS

El ZIP de GitHub documenta `POST /audio/stop` del servicio Flutter puerto **5050**. No documenta una ruta de parada del servicio TTS en el puerto **9000**. La V15.2 consulta `/openapi.json` de TTS y únicamente usa una ruta de parada POST expresamente publicada entre las rutas aprobadas. El administrador puede indicar una de esas rutas **después de verificarla** con la variable de entorno `MESERO06_TTS_STOP_PATH` (no es necesaria si OpenAPI ya la publica). No configurar ni adivinar una ruta inválida.

La V15.2 también consume por completo el streaming PCM de `/synthesize/play` para evitar dejar la petición abierta a medias. Pulsa **X** o el botón **Detener todo audio** para parar la reproducción en PC y enviar STOP a Flutter, sin tocar motores ni cámara. Si TTS no publica parada, mostrará “TTS: parada remota no disponible”, no una confirmación ficticia.

## 3. Nombres de venta

**Ventas → Resumen** conserva el `merchantId` de `/payment/polling-status`, pero ahora consulta el catálogo de productos y `/api/mini/merchants` para asignarle su nombre real. Si no tiene un ID identificado, puede inferir la sucursal únicamente cuando **todos** los artículos del grupo coinciden inequívocamente con la misma sucursal. Si sigue apareciendo “Comercio #ID”, introduce el mapeo real en **Ventas → Nombres de comercios (merchantId)**. No modifica precios ni pagos.

## Seguridad

No probar movimientos sin zona despejada ni STOP físico accesible. El puente local sólo escucha en 127.0.0.1. Evitar colocar tokens en JS o GitHub; el repositorio original recibido contenía un token de TTS dentro de `app.js`, por lo que el administrador debe **revocarlo/rotarlo** si sigue vigente y retirarlo del código público.


## Prueba V15.3 sin /attract/list
Con los 6 IDs documentados, V15.3 permite probar directamente `POST /attract/set` para `pumpkin`, `ghost`, `scared`, `witch`, `sinister`, `alien`. Los prueba mediante el mismo puente local autenticado; NO significa que esos GIF estén instalados. La respuesta de Flutter debe confirmar `success:true` y el ID solicitado. Si estos IDs solo pertenecen a un HTML Halloween separado y no son parte de `mini_app_qr`, la petición fallará y hará falta identificar el servicio que renderiza ese HTML. No se transfiere ningún archivo al robot.
