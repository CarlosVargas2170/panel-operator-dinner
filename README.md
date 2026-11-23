# MINI APP QR PRUEBAS · Integración completa con Panel Robot · Mesero 06

**README único para la rama `mini-qr-pruebas`.** Manual técnico de la Mini App QR de origen y de **MINI APP QR PRUEBAS**, validada en Mesero 06. **Este archivo es documentación, no contiene ni instala el proyecto Flutter.** El objetivo es que otro desarrollador entienda **de dónde salió la aplicación, qué se conservó y migró, qué código se cambió, en qué archivo, por qué, cómo se reproduce y cómo se comprueba**, sin crear instalaciones Flutter innecesarias.

> **Decisión operativa:** en el robot queremos conservar **exactamente dos instalaciones**: **MINI APP QR ORIGINAL** (respaldo al que volver si las pruebas fallan) y **MINI APP QR PRUEBAS** (la copia que modificamos, compilamos y probamos). **No son dos ramas de GitHub ni dos procesos simultáneos.** Los nombres en mayúsculas son etiquetas de documentación: no se han renombrado las rutas del robot.

> **Importante sobre los números de línea:** se verificaron contra los fuentes de la integración por ID y contra el parche exacto que el operador aplicó sobre la Mini QR activa. En el robot se confirmó que el marcador del parche aparece en `home_cubit.dart:134`. Los archivos de medios añadidos posteriormente no están completos en el paquete de fuentes que se pudo revisar aquí: sus ubicaciones funcionales se documentan, pero **no se inventan líneas**. El comando de la sección 12 obtiene los números actuales directamente del proyecto del robot antes de publicarlo.

## Cómo utilizar este README único

Este documento está pensado para publicarse **solo como `README.md`** en GitHub. Reúne lo que se hizo, los fragmentos de código disponibles, las rutas, el propósito de cada modificación, los contratos HTTP y las pruebas. No es necesario subir los 272 archivos para que otras personas puedan leerlo, **pero subir solo el README no equivale a respaldar el código**: el proyecto Flutter completo debe conservarse en `MINI APP QR PRUEBAS` y en un respaldo privado autorizado.

**Estado de la evidencia:** los bloques de `AppServer`, `UiCommandBus`, `HomePage`, `HomeCubit`, el parche de comercio libre y el puente del Panel Windows se cotejaron con fuentes disponibles de la integración. Los fragmentos de reproducción remota con `MediaCache` se explican por su contrato y las pruebas realizadas; el archivo final completo de `media_cache.dart` y de `audio_service.dart` no está adjunto a esta entrega y **no se atribuye a ellos código inventado**. La línea `home_cubit.dart:134` del marcador `NEXUS_OPERADOR_COMERCIO_LIBRE_V1` sí fue comprobada directamente por el operador en la copia real.

**No incluir en un README público:** direcciones privadas del robot, valores reales de `.env`, tokens TTS, credenciales del backend, contraseñas, claves Supabase ni enlaces privados de medios. Todos los ejemplos utilizan `127.0.0.1` desde dentro del robot, URLs ficticias o identificadores que ya formaron parte de las pruebas funcionales.

## Estado de las instalaciones confirmado el 23 de noviembre de 2026

- **ORIGINAL:** `/home/serbot01-06/Nexus_Patio_Tech/mini_app_qr/mini-app-qr`; último ejecutable activo observado por `systemctl --user`: el bundle de ORIGINAL.
- **PRUEBAS:** `/home/serbot01-06/mini_qr_prueba_81f405a/mini_qr_con_migraciones`; conserva el código validado de los productos por ID y los audios recuperados.
- Se eliminaron las tres carpetas antiguas `mini_qr_integrada`, `mini_qr_prueba` y `mini_qr_panel_robot` tras respaldar su código. Respaldo verificado con SHA-256 en `~/RESPALDO_CODIGO_MINIQR_ANTIGUAS/fuentes_antiguas_20261123_122330.tar.gz`. **Este respaldo no se publica en GitHub.**
- La rama de publicación acordada es **`mini-qr-pruebas`**. La otra rama de trabajo del repositorio, `panel-robot-local`, contiene el panel Windows y se documenta por separado.

## 0. Origen de la aplicación: de Mini App QR a Mini App QR Pruebas

### 0.1 De dónde salió nuestro trabajo

**Todo este trabajo parte de Mini App QR, la aplicación que ya existía en el robot.** No hicimos otra aplicación desde cero. Utilizamos su base funcional y recuperamos o trasladamos componentes del desarrollo anterior para construir una **copia de pruebas**, donde se integraron los cambios de medios, productos y comercios. Esa es la procedencia que debe quedar clara en cualquier entrega del código.

El recorrido funcional de la integración fue:

```text
MINI APP QR ORIGINAL  (instalación histórica del robot)
  ├─ Estructura Flutter y ejecución Linux ARM64
  ├─ Pantallas, catálogo, comercios, productos y lógica de compras preexistentes
  ├─ Recursos y componentes recuperados de la aplicación previa
  └─ Base que debe conservarse como alternativa de recuperación
       │
       └─ Fuentes y componentes trasladados / integrados para trabajar aislados
            ↓
MINI APP QR PRUEBAS  (nuestra copia de trabajo)
  ├─ Directorio: mini_qr_prueba_81f405a/mini_qr_con_migraciones
  ├─ GIF externos y Halloween: URL + MediaCache + visualización física
  ├─ Audios locales/remotos y recuperación de archivos faltantes
  ├─ Producto exacto por merchantId + productId y confirmación pageReady
  ├─ Regreso al catálogo completo con /merchants/show
  └─ Corrección en HomeCubit: cambio de comercio con ProductCache
```

**Qué significa «con migraciones»:** `mini_qr_con_migraciones` es el nombre de la carpeta del código integrado que trasladamos para probar. Describe la integración y recuperación de capacidades del proyecto anterior, **no una garantía de que ejecutamos migraciones de base de datos**. La carpeta de ejecución final sigue siendo una sola copia de pruebas. El árbol de fuentes que se llevó al robot incluyó archivos y recursos recuperados; por ejemplo, el soporte Linux se recuperó de la instalación existente del robot cuando no estaba disponible en el árbol inicial de trabajo.

**Qué se conservó de la Mini App QR de origen:** los flujos del cliente, catálogo, navegación, pantalla, configuración y protecciones de carrito/pagos. **Qué se añadió o corrigió dentro de PRUEBAS:** presentación por producto, descarga/caché de GIF y audios remotos, recuperación de audios ausentes y acceso directo a otros comercios ya cargados. Son modificaciones de la **misma familia de aplicación**, no sistemas nuevos ni servicios separados.

### 0.2 Las dos instalaciones que debemos mantener

| Uso | Nombre acordado | Ruta del proyecto en el robot | Política |
|---|---|---|---|
| Respaldo y retorno | **MINI APP QR ORIGINAL** | `/home/serbot01-06/Nexus_Patio_Tech/mini_app_qr/mini-app-qr` | **No modificar ni borrar.** Verificar que sus fuentes, assets, credenciales de ejecución y bundle sigan completos antes de confiar en ella como respaldo. |
| Desarrollo y validación | **MINI APP QR PRUEBAS** | `/home/serbot01-06/mini_qr_prueba_81f405a/mini_qr_con_migraciones` | **Única instalación para incorporar cambios nuevos.** Es la que se comprobó activa al compilar y mostrar COFI → HAVANNA → COFI. |

La ubicación **conocida** del ejecutable original es:

```text
/home/serbot01-06/Nexus_Patio_Tech/mini_app_qr/mini-app-qr/build/linux/arm64/release/bundle/mini_app_qr
```

Y la de PRUEBAS:

```text
/home/serbot01-06/mini_qr_prueba_81f405a/mini_qr_con_migraciones/build/linux/arm64/release/bundle/mini_app_qr
```

**Estado comprobado:** PRUEBAS fue la instalación activa cuando se compiló y se verificaron los tres productos. Posteriormente, el 23 de noviembre de 2026, se comprobó mediante `readlink -f /proc/$PID/exe` que el servicio ejecutaba ORIGINAL y estaba `active`. **Pendiente de verificar:** que la elección de versión sobreviva un reinicio del robot. La configuración temporal de `systemd --user` usada en pruebas puede desaparecer al reiniciar. Por eso no se afirma que el cambio de versión ya sea automático ni persistente.

### 0.3 Regla de funcionamiento y recuperación

- Hay **dos directorios instalados**, pero **un solo proceso Mini QR a la vez**, asociado a `mini_app_qr_v1.service` y al puerto `5050`.
- Se realizan todas las modificaciones, descargas de assets autorizados, compilaciones y pruebas **en PRUEBAS**, no en ORIGINAL.
- Si PRUEBAS falla, se detiene su servicio y se configura/arranca **ORIGINAL**, tras comprobar su ejecutable y recursos; nunca lanzar ambos a la vez.
- La selección del ejecutable debe revisarse con `systemctl --user cat mini_app_qr_v1.service` y `readlink -f /proc/<PID>/exe`. El procedimiento exacto de conmutación persistente debe validarse sobre el estado real del servicio **antes** de dejarlo como instrucción operativa definitiva.
- Una rama de GitHub para Mini QR integrada puede contener el código de PRUEBAS, mientras ORIGINAL se mantiene físicamente en el robot como opción de recuperación. **Ramas Git e instalaciones Linux son cosas distintas.**

## 1. Aplicación que quedó funcionando

| Elemento | Valor confirmado |
|---|---|
| Robot | Mesero 06 |
| Instalaciones a conservar | **2: MINI APP QR ORIGINAL + MINI APP QR PRUEBAS** |
| Origen | **Mini App QR ORIGINAL**, aplicación preexistente del robot, de donde se recuperó la base y componentes previos |
| Copia que modificamos | **MINI APP QR PRUEBAS** |
| Proyecto Flutter de PRUEBAS | `/home/serbot01-06/mini_qr_prueba_81f405a/mini_qr_con_migraciones` |
| Ejecutable de PRUEBAS | `build/linux/arm64/release/bundle/mini_app_qr` dentro del proyecto anterior |
| Instalación ORIGINAL de respaldo | `/home/serbot01-06/Nexus_Patio_Tech/mini_app_qr/mini-app-qr` |
| Servicio | `mini_app_qr_v1.service` (usuario Linux) |
| Servidor HTTP de Mini QR | `127.0.0.1:5050` dentro del robot |
| Código de entrega | **Una sola** rama `mini-qr-pruebas`, con **todo** el proyecto Flutter funcional y sus recursos autorizados |

La subcarpeta se llama `mini_qr_con_migraciones` porque ahí reunimos la base y los componentes trasladados desde el trabajo de Mini App QR anterior con los cambios nuevos, y así se llevó la integración al robot. **Ese nombre no demuestra por sí solo que se hayan ejecutado migraciones de base de datos**. El historial de Halloween y audios se desarrolla más abajo. El operador confirmó que **PRUEBAS** era la que ejecutaba el servicio, compiló en ella y logró tres cambios de producto consecutivos. **ORIGINAL se conserva para regresar si falla PRUEBAS**; la ruta del servicio al reiniciar todavía requiere verificación.

## 2. Qué heredamos de la aplicación original y qué incorporamos a PRUEBAS

La Mini App QR anterior ya proporcionaba la base funcional (comercios, catálogo, navegación, presentación, compras y servicio local). No se sustituyó todo eso por una aplicación nueva: se **trasladó e integró en PRUEBAS**, agregando las correcciones siguientes. Esta tabla describe el trabajo sobre esa base, no una lista de programas independientes.


| Componente | Problema observado | Corrección y comportamiento |
|---|---|---|
| Selección por producto | El panel necesitaba abrir un producto exacto sin navegar manualmente | Endpoint `POST /operator/show-product`, con IDs de comercio y producto; **no** hace cobros |
| Cambio COFI ↔ HAVANNA | El filtro del comercio visible podía impedir acceder al otro | `HomeCubit.showProductById` repone productos **ya cargados** desde `ProductCache`, respetando filtros individuales |
| Confirmación de pantalla | El audio podía empezar antes del producto | Flutter confirma `pageReady=true` cuando el carrusel de destino queda montado |
| Selector completo | Había que volver a «Elige restaurante» | `POST /merchants/show` restaura el selector general |
| GIF de Halloween | El identificador existía, pero la pantalla física no siempre tenía el GIF local | Envío de `gif` **y** `url`, descarga/caché del medio remoto, reproducción desde archivo local |
| Audios nuevos | El panel mostraba nombres cuyo archivo no existía dentro del bundle Flutter activo | Se descargaron o transfirieron los audios faltantes a recursos locales, se declararon y se recompiló el bundle |
| Interacción y pagos | Un cambio externo durante carrito o compra es peligroso | Se conservó el rechazo por `SESSION_BUSY`, sin alterar carrito ni navegación de pagos |

## Arquitectura de la integración: backend, Flutter y panel Windows

Se conectaron **tres capas distintas**, además del resto de servicios del robot:

```text
BACKEND de datos/medios (remoto, con permisos propios)
  ├─ Comercios y productos consumidos por casos de uso de Flutter
  └─ Inventario/referencias de GIF y audios disponibles para el operador
       │                                │
       ▼                                ▼
MINI APP QR PRUEBAS (Flutter Linux ARM64)    PANEL WINDOWS (HTML + Python)
  puerto 5050 dentro del robot                 http://127.0.0.1:8765
  ├─ AppServer: endpoints HTTP                   ├─ PANEL_ROBOT_LOCAL.html
  ├─ UiCommandBus: órdenes de pantalla           ├─ panel_robot_local.py
  ├─ HomeCubit: productos/comercios               ├─ product_offer_flow.py
  ├─ HomePage: carrusel + protecciones            └─ gestor de audios/GIF
  ├─ MediaCache: descarga y archivo de medio         │
  └─ AudioService / AttractGifPlayer                 │ solicitud HTTP del operador
       ▲                                              ▼
       └────────── llamadas autorizadas desde el puente Python ──────────┘

PANTALLA FÍSICA: Flutter dibuja los GIF y productos; el sonido sale por el
sistema de audio del robot. Los botones y mensajes de estado se dibujan en
el navegador de Windows. No se confunden las dos pantallas.
```

**Puertos y responsabilidades:** `5050` es Mini QR; `8765` es el servidor del panel en el PC; `5000` corresponde a control del robot y `9000` al servicio TTS. **La integración de productos/GIF/audios descrita aquí no modifica el control de motores.** El TTS es un servicio aparte y no debe confundirse con `POST /audio/play` de Mini QR.

### Backend externo: qué se consulta y qué no se debe confundir

- Para **productos y comercios**, Flutter utiliza sus casos de uso (`GetProductsUseCase`, `GetMerchantInfoUseCase`) y la configuración autorizada de `AppSettings`. En `HomeCubit.load()` se reciben productos y comercios, se copian a `ProductCache` y luego se aplican filtros locales. **La URL y ruta exactas de la API de productos dependen de la configuración desplegada; no deben adivinarse a partir de `merchantId`.**
- Para **medios del panel**, se trabajó con el catálogo del backend del robot, cuyo acceso para Mesero 06 se identificó como `GET /api/panel?robot=mesero-6` en el servidor de medios. En pruebas ese recurso también devolvió **403** sin autorización adecuada: no es un inventario público anónimo y una respuesta fallida no demuestra que falten archivos.
- Los **GIF externos** tienen una URL concreta de archivo (por ejemplo en Cloudinary) que se obtiene de un registro autorizado. El navegador envía la referencia al puente; este llama a `POST /attract/set` en Mini QR. **No se crea ninguna URL sustituyendo simplemente el nombre de la carita.**
- Las rutas `GET /products`, `POST /operator/show-product`, `POST /audio/play` y `POST /attract/set` de las tablas siguientes son de la **API local de Mini QR**, no son rutas del backend de comercios ni de Cloudinary.
- `merchantId` identifica el comercio dentro de Flutter; **no debe sustituirse automáticamente por `branchId`** de otro sistema. El `productId` siempre se interpreta junto al `merchantId` al presentar un producto.

### Mapa de archivos e inserción de código

| Archivo | Dónde encaja y qué responsabilidad tiene |
|---|---|
| `lib/core/services/app_server.dart` | Registrar y validar rutas del HTTP local. Aquí están `/operator/show-product`, `/merchants/show`, `/attract/set`, `/audio/play` y `/audio/stop`. |
| `lib/core/services/ui_command_bus.dart` | Declarar `ShowProductById`, `ShowAttract`, `ShowMerchantPicker` y otros mensajes hacia Flutter. |
| `lib/presentation/pages/home_page.dart` | Escuchar comandos, bloquear cambios en compras activas y comprobar el montaje real de la página mediante `pageReady`. |
| `lib/presentation/bloc/home_cubit.dart` | Seleccionar comercio/producto y posición del carrusel. **El parche `NEXUS_OPERADOR_COMERCIO_LIBRE_V1` va al principio de `showProductById`, antes de validar `availableMerchantIds`.** |
| `lib/presentation/bloc/home_state.dart` | Estado de productos, página, comercio y revisión de enfoque (`operatorFocusRevision`). |
| `lib/core/services/product_cache.dart` | Cachear todos los productos ya cargados; permite recuperar un comercio oculto temporalmente sin inventar productos. |
| `lib/core/services/media_cache.dart` | Implementación integrada de caché/descarga de medios remotos. **Ubicación funcional confirmada; cotejar el código final antes de copiar fragmentos.** |
| `lib/presentation/widgets/attract_gif_player.dart` | Muestra GIF locales o los descargados al almacenamiento del robot. |
| `lib/core/services/audio_service.dart` | Selecciona la fuente del audio, lo reproduce y lo detiene. |
| `pubspec.yaml` | Declara `assets/audio/` y `assets/images/` y dependencias de reproducción. |
| `PANEL_ROBOT_LOCAL.html` (proyecto Windows) | Renderiza catálogo, botones guardados, mensajes de error y caritas en el navegador. **No va dentro de Flutter.** |
| `panel_robot_local.py` y `product_offer_flow.py` (proyecto Windows) | Validan y envían las llamadas desde el PC al puerto 5050, con recuperación acotada de filtros. |

## 3. Recorrido completo: del botón al producto físico

```text
Panel Windows (botón "Mostrar" u "Ofrecer")
  POST http://127.0.0.1:8765/api/mini/operator/show-product
         {"merchantId":53,"productId":74}
  │
  └─ Puente Python local → Mini QR del robot, puerto 5050
       POST /operator/show-product
         │
         ├─ AppServer valida enteros positivos
         ├─ UiCommandBus publica ShowProductById
         ├─ HomePage impide actuar si hay compra/carrito/pantalla ocupada
         ├─ HomeCubit busca el producto, recupera caché autorizada si hace falta,
         │  y actualiza comercio + página del carrusel
         ├─ HomePage espera el montaje y compara IDs/página/revisión
         └─ Respuesta JSON con pageReady=true
                 │
                 └─ Solo entonces el panel puede iniciar el audio asociado
```

**Distinción fundamental:** `merchantId` identifica un comercio para Mini QR; no significa necesariamente `branchId` o una sucursal de otra API. Los ejemplos probados fueron COFI `53/74` y HAVANNA `84/455`.

### 3.1 Endpoint HTTP: `lib/core/services/app_server.dart`

**Líneas 410–413 del código de integración examinado:**

```dart
if (path == '/operator/show-product' && method == 'POST') {
  await _handleOperatorShowProduct(request, response);
  return;
}
```

**Líneas 495–544:** `_handleOperatorShowProduct` decodifica el JSON, exige `merchantId` y `productId` como enteros positivos, emite un comando y espera la confirmación de Flutter con tiempo límite de seis segundos:

```dart
final merchantId = data['merchantId'] as int;
final productId = data['productId'] as int;
final cmd = ShowProductById(merchantId: merchantId, productId: productId);
UiCommandBus.emit(cmd);
final result = await cmd.completed.future.timeout(
  const Duration(seconds: 6),
);
```

Resultados posibles: `200` si se confirmó; `400` para IDs o JSON inválidos; `404` para producto/comercio no visible; `409` para condiciones de aplicación que impiden la operación; `503` si Flutter no confirma a tiempo; `500` ante error inesperado. **Un HTTP 200 sin `pageReady` no basta para iniciar un audio de oferta.**

### 3.2 Comunicación interna: `lib/core/services/ui_command_bus.dart`

**Líneas 30–39:** comando `ShowProductById` y su promesa de respuesta.

```dart
class ShowProductById extends UiCommand {
  final int merchantId;
  final int productId;
  final Completer<Map<String, dynamic>> completed =
      Completer<Map<String, dynamic>>();

  ShowProductById({required this.merchantId, required this.productId});
}
```

`AppServer` no manipula widgets directamente. En cambio, manda el comando y recibe por `completed` el resultado de la pantalla. Así se evita responder «listo» solo por haber recibido un paquete HTTP.

### 3.3 Seguridad y montaje visual: `lib/presentation/pages/home_page.dart`

**Líneas 143–180 del código examinado:**

```dart
case ShowProductById(:final merchantId, :final productId, :final completed):
  if (_isPreparingPayment ||
      _activePaymentCubit != null ||
      Navigator.of(context).canPop() ||
      cubit.state.cartQuantities.values.any((q) => q > 0)) {
    completed.complete({
      'success': false,
      'reason': 'SESSION_BUSY',
      'message': 'Hay un carrito, compra o pantalla activa',
    });
    break;
  }
  final result = cubit.showProductById(merchantId, productId);
  // ... espera fin de frame y confirma que sigan coincidiendo página, IDs y revisión ...
  if (!samePage) {
    result['success'] = false;
    result['reason'] = 'VIEW_CHANGED';
  } else {
    result['pageReady'] = true;
  }
```

Se conservan las comprobaciones originales y se espera `WidgetsBinding.instance.endOfFrame` más un pequeño margen para montar el carrusel. `pageReady` significa página montada, **no garantiza que toda imagen de red esté descargada**. No se fuerza un cambio si ya se inició una compra.

### 3.4 Selección, carrusel y comercio: `lib/presentation/bloc/home_cubit.dart`

**Líneas 126–214 de la versión reconstruida con el mismo parche que se aplicó al robot.** El bloque nuevo comienza en la **línea 134**, corroborada por el resultado del operador.

```dart
// NEXUS_OPERADOR_COMERCIO_LIBRE_V1
final targetIsAlreadyVisible = state.products.any(
  (p) => p.id == productId && p.merchantId == merchantId,
);
if (!targetIsAlreadyVisible) {
  final settings = AppSettings();
  final cache = ProductCache();
  if (settings.merchantIds.contains(merchantId) &&
      cache.isLoaded &&
      cache.loadedMerchantIds.contains(merchantId) &&
      cache.allProducts.any(
        (p) => p.id == productId && p.merchantId == merchantId,
      )) {
    final filter = settings.filterConfig;
    final previousEnabledMerchants = Set<int>.of(filter.enabledMerchants);
    filter.enabledMerchants.clear();
    final restoredProducts = cache.allProducts
        .where((p) => filter.isProductVisible(p.id, p.merchantId))
        .toList();
    if (restoredProducts.any(
      (p) => p.id == productId && p.merchantId == merchantId,
    )) {
      emit(state.copyWith(
        products: restoredProducts,
        merchantIds: cache.loadedMerchantIds,
        merchantNames: cache.merchantNames,
      ));
    } else {
      filter.enabledMerchants.addAll(previousEnabledMerchants);
    }
  }
}
```

**Qué hace cada parte:**

1. **Líneas 140–142:** comprueba si el producto ya figura entre los visibles. Si sí, no toca filtros.
2. **Líneas 144–151:** verifica que el comercio esté autorizado por la configuración, que la caché exista y que producto y comercio estén presentes allí. **No crea datos inexistentes**.
3. **Líneas 152–159:** guarda el filtro anterior, habilita la lista de comercios cargados y reconstruye visibles respetando `isProductVisible(...)` para no revelar productos bloqueados individualmente.
4. **Líneas 160–173:** si el destino aparece tras la reconstrucción, emite el estado; si no, restaura el filtro anterior.
5. **Líneas 176–190:** el método conserva el rechazo por comercio o producto no disponible.
6. **Líneas 191–214:** usa `pageIndexForProduct`, selecciona `merchantId`, cambia `currentIndex`, incrementa `operatorFocusRevision` y devuelve información del producto, sin agregar al carrito ni cobrar.

**Caché de productos:** `lib/core/services/product_cache.dart`, líneas 9–24 de la fuente consultada, contiene `allProducts`, `merchantNames`, `loadedMerchantIds` e `isLoaded`. `HomeCubit.load` la llena cuando consulta la API (líneas 164–209 de la fuente previa al parche; en el archivo final ese bloque queda desplazado por el nuevo código). No guardar índices antiguos de línea para funciones que se desplazaron.

### 3.5 Volver a todos los comercios

`POST /merchants/show` es la acción de Mini QR que abre el selector general «Elige restaurante». **No equivale a editar permanentemente los IDs configurados**. El endpoint aparece en `app_server.dart:442–445` del código de integración examinado. El panel llama esta ruta desde su puente `POST /api/mini/merchants/all`.

### 3.6 Código exacto del parche de comercio libre: qué insertar y dónde

El método `showProductById(int merchantId, int productId)` **ya existía** en la integración por ID. Antes, cuando `state.availableMerchantIds` no contenía el comercio solicitado, devolvía inmediatamente `MERCHANT_UNAVAILABLE`. La corrección agrega un bloque **justo antes** de esa comprobación, sin cambiar la API ni la lógica del carrito.

**Archivo:** `lib/presentation/bloc/home_cubit.dart`.
**Ubicación comprobada en PRUEBAS:** comentario `// NEXUS_OPERADOR_COMERCIO_LIBRE_V1` en línea **134**. **Fragmento del parche disponible:**

```dart
// NEXUS_OPERADOR_COMERCIO_LIBRE_V1
// La selección del operador no depende del comercio visible anteriormente.
final targetIsAlreadyVisible = state.products.any(
  (p) => p.id == productId && p.merchantId == merchantId,
);
if (!targetIsAlreadyVisible) {
  final settings = AppSettings();
  final cache = ProductCache();
  if (settings.merchantIds.contains(merchantId) &&
      cache.isLoaded &&
      cache.loadedMerchantIds.contains(merchantId) &&
      cache.allProducts.any(
        (p) => p.id == productId && p.merchantId == merchantId,
      )) {
    final filter = settings.filterConfig;
    final previousEnabledMerchants = Set<int>.of(filter.enabledMerchants);
    filter.enabledMerchants.clear();
    final restoredProducts = cache.allProducts
        .where((p) => filter.isProductVisible(p.id, p.merchantId))
        .toList();
    if (restoredProducts.any(
      (p) => p.id == productId && p.merchantId == merchantId,
    )) {
      emit(state.copyWith(
        products: restoredProducts,
        merchantIds: cache.loadedMerchantIds,
        merchantNames: cache.merchantNames,
      ));
    } else {
      filter.enabledMerchants.addAll(previousEnabledMerchants);
    }
  }
}
// A continuación sigue la comprobación original:
if (!state.availableMerchantIds.contains(merchantId)) {
  // devolver MERCHANT_UNAVAILABLE si de verdad no está disponible
}
```

La última comprobación aparece abreviada para mostrar el **punto de inserción**. No debes reemplazar con este ejemplo el método entero: conserva el código original para `pageIndexForProduct`, `selectedMerchantId`, `currentIndex`, `operatorFocusRevision`, timeout de inactividad y errores. El parche real fue insertado una sola vez; antes de volver a aplicarlo comprueba si ya existe la marca, para no duplicar la lógica.

**Por qué funciona:** `ProductCache` guarda datos que ya llegaron del backend. Cuando el piloto cambia de COFI a HAVANNA, el estado visible puede estar filtrado. El parche revisa que el comercio esté configurado, que el producto esté cargado y que no esté individualmente bloqueado; restaura el conjunto visible desde caché y deja que el mismo método original seleccione la página. **No habilita comercios no configurados, no descarga un producto nuevo y no cambia la sesión de pago.**

### 3.7 Cómo se dibuja la página en el robot

Con la selección aceptada, `HomeCubit` emite el estado siguiente (extracto del método de la integración por ID, después del bloque de recuperación):

```dart
emit(state.copyWith(
  displayMode: DisplayMode.product,
  selectedMerchantId: merchantId,
  clearSelectedCategory: true,
  currentIndex: page,
  operatorFocusRevision: state.operatorFocusRevision + 1,
));
```

La `HomePage` ya está escuchando cambios de `HomeCubit`. El `selectedMerchantId` determina qué comercio se presenta; `currentIndex` posiciona el carrusel; `operatorFocusRevision` ayuda a detectar que otra orden cambió la vista. Al terminar el frame y el pequeño intervalo de montaje, `HomePage` comprueba que ambos IDs y la página todavía coincidan y responde `pageReady: true`. El usuario **puede seguir navegando por el catálogo** después de esa presentación, porque el comando no crea una pantalla de pago ni elimina los demás productos.

### 3.8 Qué se ve en el panel Windows y qué se dibuja físicamente

**Código del panel V29 examinado:**

- `PANEL_ROBOT_LOCAL.html:2841` define `loadProducts()` y solicita `GET /api/mini/products` al servidor Python de Windows; `normalizeProductCatalog()` convierte el resultado agrupado en comercios y productos a filas que usa `renderProducts()`.
- `PANEL_ROBOT_LOCAL.html:2821` contiene `renderProducts()`. Esta función **dibuja las tarjetas, nombres, precios y botones en el navegador**, no en la pantalla física del robot.
- `PANEL_ROBOT_LOCAL.html:2921` define la llamada real `presentProduct: (merchantId,productId) => callMini('/api/mini/operator/show-product',{merchantId,productId})`.
- `PANEL_ROBOT_LOCAL.html:3503–3533` contiene `runCommerceOffer(row,withAudio)`, el controlador de **Ofrecer + audio** y **Mostrar sin audio** para botones personalizados.

Fragmento **real** de la decisión del panel:

```js
const result = await api.presentProduct(merchantId, id);
if (!result.ok || result.pageReady !== true ||
    Number(result.productId) !== id ||
    Number(result.merchantId) !== merchantId) {
  throw Error('Mini QR no confirmó el producto solicitado. No se envió audio.');
}
// Solo después de verificar la pantalla se solicita el audio asociado.
if (withAudio && row.audioId && api.getAudio().some(x => x.id === row.audioId)) {
  await api.playAudioForOffer(row.audioId);
}
```

**Dónde recibe el PC la solicitud:** `panel_robot_local.py:785–855` valida `merchantId`, `productId`, el origen del navegador y la autorización local, y llama a `show_product_for_any_merchant` (`product_offer_flow.py:22–55`). Comprueba `pageReady` y que Flutter devolvió los **mismos IDs**. Si Flutter devuelve 404 únicamente por `MERCHANT_UNAVAILABLE` o `PRODUCT_NOT_VISIBLE`, el puente puede hacer `POST /merchants/show` y volver a intentarlo; **no realiza esa recuperación frente a 409 por compra/pago ocupado**. La corrección principal para nuestros casos está en `HomeCubit`.

**Resultado visual esperado:** el botón del panel cambia su mensaje a «mostrando» y luego a «confirmado»; simultáneamente, la pantalla física de Flutter muestra el comercio y la tarjeta del producto exacto. Si el audio asociado falla, el panel indica **«producto visible, audio falló»**, sin mentir diciendo que falló todo el producto.

## 4. Ejemplos exactos que se probaron físicamente

```bash
# COFI: Cappuccino
curl -sS -i -X POST http://127.0.0.1:5050/operator/show-product \
  -H 'Content-Type: application/json' \
  -d '{"merchantId":53,"productId":74}'

# HAVANNA: Coca-Cola, sin cambiar antes el comercio
curl -sS -i -X POST http://127.0.0.1:5050/operator/show-product \
  -H 'Content-Type: application/json' \
  -d '{"merchantId":84,"productId":455}'

# Volver a COFI
curl -sS -i -X POST http://127.0.0.1:5050/operator/show-product \
  -H 'Content-Type: application/json' \
  -d '{"merchantId":53,"productId":74}'
```

El operador confirmó las tres pantallas correctas en ese orden. Es una prueba **real del robot**, no una simulación. No repetir con carrito o pago activos.

## 5. Cómo se muestran GIF y por qué Halloween necesitó caché

**Ruta externa:** `POST /attract/set` en el puerto 5050, con dos datos complementarios:

```json
{"gif":"alien_qfau","url":"https://res.cloudinary.com/.../carita.gif"}
```

- `gif` es la referencia lógica que solicita el operador; no basta cuando el recurso nuevo no está empaquetado.
- `url` señala un medio remoto válido, autorizado y accesible desde el robot. No usar URLs inventadas.
- `MediaCache` descarga o reutiliza el archivo cacheado. `AttractGifPlayer` muestra el archivo descargado con `Image.file`; para caritas incorporadas a la aplicación se mantiene `Image.asset`.
- Flutter cambia al modo de atracción y dibuja esa carita en la **pantalla física del robot**, no simplemente en el navegador de Windows.
- Se solucionó el caso en que enviar únicamente el nombre no mostraba los GIF nuevos. La prueba física de Halloween funcionó después de enviar `gif` y `url` y utilizar caché.

**Dónde revisar el código fuente final:** `lib/core/services/app_server.dart` (handler `/attract/set`), el servicio real que define `MediaCache`, el widget `AttractGifPlayer` y la vista de atracción. **Las líneas exactas de esas dos últimas clases se deben tomar de la carpeta activa**, porque el archivo fuente de medios final no está en el extracto disponible para este README. Consulta la sección 12. No reemplazar el handler moderno por el código antiguo que solo aceptaba `gif`.

### 5.1 Contrato real de Halloween y diferencia frente al código antiguo

En un extracto **anterior** de `AppServer` se comprobó que `/attract/set` aceptaba solo `gif` y hacía esto:

```dart
final gifName = json['gif'] as String? ?? 'attract';
final assetPath = 'assets/images/$gifName.gif';
UiCommandBus.currentGifName = gifName;
UiCommandBus.emit(ShowAttract(gifAsset: assetPath));
```

Ese diseño funcionaba solo cuando `assets/images/<nombre>.gif` existía en el bundle. **Este es el código anterior, NO el handler completo de medios remotos que quedó integrado.** El problema con las caritas Halloween era que algunas se guardaban en el backend y tenían URL externa; enviar únicamente el nombre llevaba a una ruta local inexistente.

La integración probada amplió el contrato para enviar **los dos campos**:

```http
POST /attract/set HTTP/1.1
Content-Type: application/json

{"gif":"<id_del_gif>","url":"https://res.cloudinary.com/<cuenta>/<ruta>/<archivo>.gif"}
```

En Flutter el flujo funcional es:

1. `AppServer` recibe y valida el identificador y la URL del GIF.
2. `MediaCache` busca una copia local válida; si no existe, descarga el medio remoto permitido y lo almacena para reutilizarlo.
3. `UiCommandBus` emite la orden de atracción que llega a la pantalla.
4. `AttractGifPlayer` utiliza **`Image.file`** cuando la fuente es un archivo descargado y **`Image.asset`** cuando es una carita empaquetada.
5. El robot muestra la carita en su pantalla física. El panel Windows solo presenta el catálogo y el botón que dispara la acción.

**Esquema explicativo, NO copia literal del `media_cache.dart` final:**

```dart
// Ejemplo de estructura; cotejar nombres y tipos con el código real.
final cachedFile = await mediaCache.resolve(allowedRemoteUrl);
// Si viene de caché/descarga: Image.file(cachedFile)
// Si es recurso incorporado:  Image.asset(assetPath)
```

No pegues este pseudocódigo directamente en Flutter: `resolve` es un nombre didáctico y puede no coincidir con el método real. Las rutas de implementación verdaderas se encuentran en `lib/core/services/media_cache.dart`, `lib/presentation/widgets/attract_gif_player.dart`, el comando `ShowAttract` y el handler `/attract/set` del `app_server.dart` **de PRUEBAS**. Revisa esas clases si cambias el formato de respuesta o el origen de medios.

### 5.2 Cómo llega Halloween desde el backend hasta el robot

```text
Backend de medios (registro id + URL GIF, autenticación si corresponde)
  ↓ listado permitido para ese robot
Panel Windows (gestor de GIF / colección Halloween)
  ↓ operador pulsa «Mostrar» o un atajo de TAB
PANEL_ROBOT_LOCAL.html
  ↓ POST /api/mini/face/set con id y url
panel_robot_local.py (puente PC → Mini QR, control de entradas)
  ↓ POST /attract/set {gif, url}
AppServer de Flutter → MediaCache → ShowAttract → AttractGifPlayer
  ↓
Pantalla física de Mesero 06 muestra GIF local/caché
```

La colección **Halloween** es una agrupación del panel; Mini QR interpreta el identificador y la URL del medio. Si la URL o el acceso falla, el panel debe informar del error y **no afirmar que el GIF se mostró**. El antiguo backend no garantiza acceso sin credencial y la sincronización del inventario de GIF del panel no se considera completamente probada para todas las emociones.

## 6. Audios: qué pasó y cómo logramos que suenen

### 6.1 El problema

El panel podía incluir un nombre o ruta de audio en su catálogo sin que Mini QR tuviera realmente el archivo en `assets/audio`. La presencia del nombre **no prueba que el audio sea reproducible**. Así ocurrió con los audios nuevos, incluidos **`pedro_pedro.mp3` y `bebita.mp3`**.

### 6.2 La solución usada en la prueba

1. Se localizó o recuperó el archivo real autorizado de cada audio.
2. Se transfirió desde el equipo operador al proyecto Flutter que se estaba probando, dentro de sus recursos `assets/audio/`.
3. Se comprobó la declaración/paquetización de recursos correspondiente en `pubspec.yaml` y que el archivo quedara dentro del bundle de Linux.
4. Se recompiló Mini QR **en esa misma carpeta**, no se levantó una segunda instancia permanente.
5. Se reinició el servicio y se ejecutó la reproducción directa por HTTP, comprobando que el **altavoz físico** sonara.

Nombres de archivo confirmados para estas pruebas:

```text
assets/audio/pedro_pedro.mp3
assets/audio/bebita.mp3
```

Esos archivos pudieron haberse transferido como recursos físicos en la sesión, pero **no están incluidos como código fuente en este README**, ni debe suponerse que el repositorio remoto actual ya los contiene. Verifica sus permisos de distribución antes de agregarlos a GitHub.

### 6.3 Reproducción: ruta y funcionamiento

La API ofrece `POST /audio/play`, compatibilidad `/play-audio` y detención por `POST /audio/stop`. Ejemplo con recurso local declarado en Flutter:

```bash
curl -sS -i -X POST http://127.0.0.1:5050/audio/play \
  -H 'Content-Type: application/json' \
  -d '{"asset":"audio/pedro_pedro.mp3","showOverlay":false}'
```

**Código del handler consultado, `lib/core/services/app_server.dart:548–593`:** se lee `asset`, `volume`, `force`, `displayText`, `showOverlay`, y se pasa a `AudioService.play`:

```dart
final asset = json['asset'] as String?;
final volume = (json['volume'] as num?)?.toDouble() ?? 1.0;
final force = json['force'] == true;
AudioService.setRemoteCall(true);
final displayText = json['displayText'] as String?;
final played = await AudioService.play(
  asset,
  volume: volume,
  force: force,
  displayText: displayText,
  showOverlay: showOverlay,
);
```

Este fragmento corresponde a la **versión de selección por ID examinada**; comprobar su posición actual en el archivo integrado antes del commit.

**Flujo físico:** panel → puerto `5050` → `AudioService` → resolución del recurso local o remoto → reproducción. Para medios remotos autorizados, la integración utiliza `MediaCache` y una fuente de archivo (`DeviceFileSource`); para assets empaquetados utiliza `AssetSource`. Cuando el audio está ejecutándose pueden existir controles de cooldown/ocupado; recibir la solicitud no equivale a que el archivo haya sonado. El panel también implementa `POST /api/mini/audio/stop`, que se traduce a la detención correspondiente.

**No confundir:** renombrar un audio en el panel Windows cambia la etiqueta o nota en la interfaz; no modifica el contenido de voz del WAV/MP3 que se reproduce.

### 6.4 Código nuevo de medios y líneas pendientes de cotejar

Las clases `MediaCache`, `AttractGifPlayer` y la implementación actual de `AudioService` forman parte de la Mini QR **completa** de la ruta activa, pero **no se encuentran en los extractos aislados** empleados para verificar este documento. Para la revisión Git:

```bash
cd ~/mini_qr_prueba_81f405a/mini_qr_con_migraciones
rg -n 'class MediaCache|class AttractGifPlayer|class AudioService|DeviceFileSource|AssetSource' lib
rg -n "'/attract/set'|'/audio/play'|'/audio/stop'|'/operator/show-product'" lib
rg -n 'pedro_pedro|bebita|assets/audio' pubspec.yaml lib assets 2>/dev/null
```

Anotar en el commit los números que devuelvan estos comandos. Si `rg` no existe, usar `grep -RniE`. Esta verificación es la que permite documentar **líneas reales y no estimaciones**.

### 6.5 Código de audio, empacado y reproducción real

**Handler confirmado en una fuente de la integración (`app_server.dart`, alrededor de las líneas 548–593 de esa revisión):**

```dart
final asset = json['asset'] as String?;
final volume = (json['volume'] as num?)?.toDouble() ?? 1.0;
final force = json['force'] == true;
final showOverlay = json['showOverlay'] ?? true;
final displayText = json['displayText'] as String?;
AudioService.setRemoteCall(true);
final played = await AudioService.play(
  asset,
  volume: volume,
  force: force,
  displayText: displayText,
  showOverlay: showOverlay,
);
```

La respuesta incluye el campo **`played`**: el hecho de recibir `HTTP 200` no basta si `played` es `false` por cooldown o audio ocupado. `POST /audio/stop` llama a `AudioService.stop()`. En `AudioService` se preserva la distinción entre `AssetSource` (audio empaquetado en Flutter) y `DeviceFileSource` (archivo descargado o almacenado localmente). La implementación final específica de `AudioService`/`MediaCache` debe consultarse en el código completo de PRUEBAS; no se reproducen aquí métodos cuya firma no está disponible.

**Configuración real de assets consultada en el `pubspec.yaml` de origen:**

```yaml
flutter:
  assets:
    - .env
    - assets/audio/
    - assets/images/
```

La carpeta `assets/audio/` es el lugar donde incorporamos los MP3 recuperados. Se comprobó en el Windows de preparación para GitHub que existen **`bebita.mp3` y `pedro_pedro.mp3`** dentro de ese directorio. Flutter debe generar un **nuevo bundle Linux ARM64** para incluir recursos incorporados al paquete; copiar únicamente el nombre del archivo en el catálogo del panel no reproduce nada. En la prueba física se recompiló PRUEBAS y luego se llamó a `/audio/play` desde SSH para confirmar el altavoz del robot.

**Importante de seguridad:** que `.env` aparezca bajo `flutter.assets` significa que, aunque no lo subas a Git, sus valores pueden terminar dentro de un bundle distribuido. Evitar claves privilegiadas en el cliente Flutter; emplear backend y controles de acceso apropiados.

### 6.6 Cómo se reproduce desde el panel y cómo verificar errores

```text
Operador pulsa «Reproducir audio» o «Ofrecer + audio»
  ↓
Panel HTML llama POST /api/mini/audio/play {"id":"<id_catalogo>"}
  ↓
Python resuelve el ID a un archivo permitido en su catálogo
  ↓
Python solicita POST /audio/play con asset/volumen/otros parámetros
  ↓
Flutter recibe la llamada en AppServer y ordena a AudioService reproducir
  ↓
Se escucha por el dispositivo de sonido configurado del robot
```

En `panel_robot_local.py:1060–1113` el puente exige origen y credencial local, resuelve el identificador contra la lista autorizada y **devuelve `202` cuando acepta un trabajo de reproducción**. Eso significa **«solicitud en proceso»**, no «audio escuchado». Puede rechazar con `409` si ya se atiende otro audio o `429` si se dispara muy seguido. Por eso los problemas se clasifican por separado: el botón está presente, el archivo existe, Flutter aceptó y finalmente el altavoz sonó.

La función **«Escuchar en PC»** pertenece a la previsualización del panel Windows; no certifica que Flutter tenga el mismo archivo en su bundle ni que su altavoz funcione. Archivar u ocultar un audio cambia la organización del panel, **no borra el audio de Linux ni de Cloudinary**.

## 7. Los cambios se integraron en PRUEBAS a partir de Mini App QR ORIGINAL

El resultado final reúne en **MINI APP QR PRUEBAS**: la base heredada de Mini App QR, catálogo multicomercio, `/merchants/show`, productos por ID, validación de compra ocupada, caritas originales, GIF remotos Halloween, audios locales, recuperación de audios y caché de medios. La corrección `NEXUS_OPERADOR_COMERCIO_LIBRE_V1` fue una modificación **adicional dentro de `home_cubit.dart`**, no otra instalación ni un nuevo repositorio.

**ORIGINAL y PRUEBAS son las dos instalaciones físicas acordadas.** ORIGINAL debe permanecer disponible para una recuperación si PRUEBAS falla. En consecuencia, jamás debe confundirse «guardar todo el código integrado en una sola rama Git» con «borrar la Mini App QR original del robot».

## 8. Construcción y reproducción en Linux ARM64

**Compilar únicamente en MINI APP QR PRUEBAS. No compilar ni sobrescribir la instalación ORIGINAL durante este flujo.**

Ruta de trabajo comprobada:

```bash
cd ~/mini_qr_prueba_81f405a/mini_qr_con_migraciones
flutter pub get
flutter build linux --release
```

**Estos comandos no deben ejecutarse mientras atiende clientes si pisan el bundle utilizado por el proceso activo.** Para desplegar, respaldar fuente y bundle, detener solo `mini_app_qr_v1.service`, compilar en la ventana acordada, iniciar y confirmar la ruta y estado:

```bash
PID=$(systemctl --user show -P MainPID mini_app_qr_v1.service)
readlink -f "/proc/$PID/exe"
systemctl --user is-active mini_app_qr_v1.service
```

Respaldo confirmado del cambio de comercios en PRUEBAS: `/home/serbot01-06/respaldo_miniqr_comercio_20261122_204247`. **No reemplaza la instalación ORIGINAL**, que se conserva como alternativa operativa independiente. El servicio apuntaba a PRUEBAS mediante configuración temporal, que **puede perderse tras reiniciar el robot**. Antes de confiar en el retorno a ORIGINAL, comprobar que esa instalación realmente arranca, que dispone de sus recursos y que solo una versión toma el puerto 5050. No proponer despliegue permanente sin validarlo expresamente.

## 9. README como única publicación ahora, y código fuente completo por separado

La rama de trabajo `mini-qr-pruebas` representa el desarrollo de **MINI APP QR PRUEBAS** y su documentación de origen. **En esta entrega se publica solo un README**, no el código ejecutable. Si más adelante se autoriza publicar las fuentes, hay que exportar el proyecto **completo desde la carpeta PRUEBAS verificada**, no solamente `home_cubit.dart`: `lib/`, `test/`, `assets/` cuya distribución esté autorizada, `linux/`, `pubspec.yaml`, `pubspec.lock`, plantillas de configuración sin credenciales y este README. Se debe incluir el código integrado de `AppServer`, `UiCommandBus`, `HomePage`, caché, reproducción de audio y GIF, junto con la corrección de comercio. **No** publicar `.env`, tokens, credenciales de TTS/Supabase, bundles Linux, cachés o archivos de audio cuya licencia no permita distribución.

La rama `mini-qr-pruebas` reúne todo el código. **No hay ni debe crearse otra rama para los productos por ID, para Halloween ni para comercio libre.**

## 10. Verificaciones mínimas después de cualquier actualización

Antes de las pruebas funcionales confirmar qué versión está activa. Las pruebas de Halloween, audio y comercio libre corresponden a **PRUEBAS**; volver a **ORIGINAL** es un procedimiento de recuperación y la versión original podría no incluir esas mejoras.

| Verificación | Resultado requerido |
|---|---|
| Versión activa | `readlink` indica **PRUEBAS** durante estas pruebas; `systemctl` muestra `active` |
| Audio `pedro_pedro.mp3` | Se escucha en el altavoz físico |
| Audio `bebita.mp3` | Se escucha en el altavoz físico |
| GIF Halloween remoto | Se muestra en la pantalla real |
| COFI 53/74 | Producto correcto visible |
| HAVANNA 84/455 | Cambio directo desde COFI |
| Regreso a COFI | Cambio directo sin selector |
| Selector general | `POST /merchants/show` abre «Elige restaurante» |
| Carrito o pago activo | No lo interrumpe una orden de presentación |
| Panel Windows | Audio asociado empieza solo después de `pageReady` |

**Estado conocido:** el operador confirmó físicamente el cambio COFI → HAVANNA → COFI y, en pruebas anteriores, la reproducción de los audios recuperados y de GIF Halloween. No se afirma que toda reproducción remota nueva o la persistencia tras reinicio esté verificada.

## 11. API resumida

| Método | Ruta | Finalidad |
|---|---|---|
| `POST` | `/operator/show-product` | Presentar por `merchantId` y `productId` |
| `POST` | `/merchants/show` | Abrir todos los comercios disponibles |
| `GET` | `/products` | Consultar productos cargados |
| `POST` | `/attract/set` | Elegir carita o GIF externo |
| `POST` | `/audio/play` | Reproducir sonido local o autorizado remoto |
| `POST` | `/audio/stop` | Detener audio |
| `GET` | `/health` o estado equivalente según build | Confirmar servicio si esa ruta está disponible |

## Pruebas prácticas recomendadas y diagnóstico

| Caso | Qué enviar o revisar | Confirmación real |
|---|---|---|
| Mini QR en línea | Estado del servicio y listener del puerto 5050 | El proceso activo corresponde a la instalación esperada |
| Comercios cargados | `GET /merchants` y `GET /products` | IDs, nombres y productos existentes; no solo un selector vacío |
| Ver todos | `POST /merchants/show` | Flutter abre «Elige restaurante» cuando hay más de un comercio visible |
| COFI | `POST /operator/show-product` con `53/74` | Se dibuja Cappuccino y se recibe `pageReady=true` |
| HAVANNA | `POST /operator/show-product` con `84/455` sin cambiar el selector | Se dibuja Coca-Cola y coincide `merchantId` |
| Audio local | `POST /audio/play` con `audio/pedro_pedro.mp3` | `played=true` cuando aplica y sonido en robot |
| Audio recuperado | `POST /audio/play` con `audio/bebita.mp3` | Sonido en robot, no solo respuesta del panel |
| GIF externo | `POST /attract/set` con `gif` y URL real autorizada | Aparece en la pantalla física y caché permite repetir |
| Pago o carrito ocupado | Solicitud de presentación durante sesión protegida | HTTP 409/`SESSION_BUSY`, sin cambiar flujo del cliente |
| Publicación en GitHub | Rama `mini-qr-pruebas` y README editado | Solo documentación si se subió únicamente este archivo; **no implica que el código se publicó** |

**Respuestas que orientan el diagnóstico:** `400` entrada inválida, `404` producto/comercio no visible, `409` sesión ocupada, `503` la vista no confirmó a tiempo. El panel puede devolver `502` si el PC no llega al robot o si Flutter devolvió datos que no coinciden. Para productos, **nunca iniciar el audio automático si no llega `pageReady=true` con IDs iguales**.

## Dónde integrar estas funciones en otro proyecto, sin romper la original

1. Partir de la aplicación que ya tenga catálogo y navegación. Mantener el proyecto ORIGINAL del robot sin sobrescribir.
2. Incorporar el endpoint `POST /operator/show-product` en `AppServer` y el comando `ShowProductById` en el bus, en la misma ruta HTTP que utiliza Mini QR.
3. Incorporar el manejador de ese comando en `HomePage`, **con bloqueo de carrito/pago** y confirmación después del montaje.
4. Añadir `HomeCubit.showProductById` usando `pageIndexForProduct`, `selectedMerchantId` y `operatorFocusRevision`; **no** recrear compras ni simular clics de pago.
5. Si hay varios comercios, conservar `ProductCache` y el parche de recuperación en el punto anterior a `availableMerchantIds.contains`. Añadirlo una sola vez.
6. Para Halloween, comprobar que la versión actual de `/attract/set` recibe ambos campos `gif` y `url`; conectar a `MediaCache` y al widget `AttractGifPlayer`. No usar el handler histórico que solo construye `assets/images/<gif>.gif`.
7. Para audios, confirmar el recurso real en `assets/audio/` o el archivo remoto autorizado, su empaquetado en `pubspec.yaml` y el contrato de `/audio/play` y `/audio/stop`.
8. En el panel Windows, `loadProducts` obtiene el catálogo de Flutter a través del puente, `renderProducts` crea las tarjetas, y `runCommerceOffer` envía exactamente los IDs guardados. Reproducir audio **después** del éxito de la pantalla.
9. Ejecutar pruebas unitarias, compilación ARM64 y prueba física **en la instalación PRUEBAS**, con el robot detenido, sin pagos ni atención comercial. Revisar que el único proceso del puerto 5050 sea el correcto.
10. Conservar un respaldo operativo de ORIGINAL y documentar cualquier cambio de `systemd --user` antes de reiniciar; la activación de PRUEBAS usada previamente fue temporal y no se confirmó persistente.

**Limitación documental:** este README permite conocer la arquitectura, puntos de modificación y fragmentos verificados, pero no es un parche ejecutable. Para replicar exactamente la caché de medios y el audio remoto hace falta consultar los archivos Flutter completos de PRUEBAS. No se deben completar esas clases con métodos supuestos.

## 12. Verificación exacta de líneas antes de subir a GitHub

Ejecutar **dentro de MINI APP QR PRUEBAS**, en el robot, **solo lectura**, sin recompilar. Este README documenta los fragmentos disponibles y la prueba física, pero no afirma haber leído remotamente el estado actual de ambos proyectos:

```bash
cd ~/mini_qr_prueba_81f405a/mini_qr_con_migraciones
for needle in \
  NEXUS_OPERADOR_COMERCIO_LIBRE_V1 \
  showProductById \
  ShowProductById \
  _handleOperatorShowProduct \
  MediaCache \
  AttractGifPlayer \
  DeviceFileSource \
  pedro_pedro \
  bebita; do
  echo "====== $needle ======" 
  grep -RniF --include='*.dart' --include='*.yaml' "$needle" lib pubspec.yaml 2>/dev/null | head -20
done
```

Estos resultados, junto con `git diff` del árbol que se publique, son la referencia definitiva si el proyecto recibió otras modificaciones después de la prueba. **Este documento no sustituye el código completo del robot ni afirma haberlo extraído remotamente.**

## 13. Inventario seguro de las dos instalaciones (antes de limpiar el robot)

**Solo lectura.** Verificar ambas carpetas y el servicio antes de borrar directorios antiguos. **No borrar ORIGINAL, PRUEBAS ni respaldos sin inventariarlos.**

```bash
ORIGINAL="$HOME/Nexus_Patio_Tech/mini_app_qr/mini-app-qr"
PRUEBAS="$HOME/mini_qr_prueba_81f405a/mini_qr_con_migraciones"

for ITEM in "$ORIGINAL" "$PRUEBAS"; do
  printf '\n== %s ==\n' "$ITEM"
  test -f "$ITEM/pubspec.yaml" && echo 'Fuentes Flutter presentes' || echo 'Revisar pubspec.yaml'
  test -x "$ITEM/build/linux/arm64/release/bundle/mini_app_qr" && echo 'Bundle ejecutable presente' || echo 'Revisar bundle'
done

systemctl --user cat mini_app_qr_v1.service
PID=$(systemctl --user show -P MainPID mini_app_qr_v1.service)
if [ "${PID:-0}" -gt 0 ]; then readlink -f "/proc/$PID/exe"; fi
```

**Estado deseado al finalizar la limpieza:** dos instalaciones (ORIGINAL y PRUEBAS) y un único servicio Mini QR activo. No crear otra carpeta de Flutter por cada cambio. Si falla PRUEBAS, retornar de forma controlada a ORIGINAL; **no está implementada ni confirmada una conmutación automática**.
