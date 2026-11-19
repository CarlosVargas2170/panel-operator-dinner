# Panel Robot Multirrobot: diagnóstico y correcciones

## Corregido en esta entrega local
- Asignación de caritas entre **Todas**, **Base**, **Halloween**, **Navidad** y **Troleo**. Los dos editores ahora muestran el destino después de guardar y notifican el cambio. Se mantienen los ajustes del piloto almacenados en el navegador.
- Estado TTS en el visor: una sola notificación flotante temporal, con check verde **solo cuando el servicio confirma la solicitud**, alerta roja si falla y texto del mensaje. Desaparece a los 4.3 segundos.
- El historial de TTS debajo de la consola conserva los mensajes. La consola principal también añade el texto y resultado final, sin modificar la implementación ni el token TTS.
- Estilo del editor flotante TTS más discreto y translúcido. No se alteraron sus peticiones, funcionamiento, tiempo de espera ni controles de audio.

## Requiere revisar el repositorio Flutter mini_app_qr
1. **Comercio + producto específico + audio:** el panel almacena `productId` por botón, pero la API que está invocando para mostrar un producto es `POST /product` con `{}` (sin `productId`). El botón de audio es independiente. Debemos buscar si Flutter permite seleccionar un producto por ID y qué transición de pantalla necesita después de `POST /products/filter`; de no existir, añadirlo con pruebas y sin interferir en pagos activos.
2. **Ver comercios:** `Ver todos en el panel` solo cambia la visualización local. `Ver todos los comercios en el robot` utiliza `POST /products/filter` con un mapa `merchants` y `reload:true`, obteniendo previamente IDs de `GET /products`. Necesitamos revisar la implementación real de Flutter (y el formato de `GET /payment/polling-status`) para confirmar si respeta ese contrato, muestra la página de comercios y necesita otro comando para abrirla.
3. **Halloween:** el robot ha confirmado `POST /attract/set`, pero el widget de Flutter informó anteriormente «GIF no encontrado» para recursos externos; revisar la URL de Cloudinary, caché y widget de renderizado.

### Para revisar Flutter
Compartir el enlace del repositorio y la rama que corre en el Robot 01 o un ZIP con el código, omitiendo `.env`, tokens, certificados y contraseñas. Archivos más relevantes: servicio HTTP en `5050`, manejadores `/products`, `/products/filter`, `/product`, `/attract/set`, modelos de comercios/productos, widgets de catálogo y reproductor de audio.

### Pruebas
Estos ajustes se validan estáticamente y con comprobación de sintaxis JS/Python. El hardware y el backend Mini QR no están conectados a este entorno; se debe confirmar cada función en el robot real. No modificar la configuración de movimiento mientras se prueban comercios o TTS.
