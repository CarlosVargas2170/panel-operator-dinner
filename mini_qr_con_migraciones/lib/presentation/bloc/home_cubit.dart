import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_settings.dart';
import '../../core/services/product_cache.dart';
import '../../domain/entities/merchant.dart';
import '../../domain/entities/product.dart';
import '../../domain/usecases/get_merchant_info.dart';
import '../../domain/usecases/get_products.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final GetProductsUseCase _getProducts;
  final GetMerchantInfoUseCase _getMerchant;

  Timer? _inactivityTimer;

  /// Timestamp del último poll exitoso.
  /// Se usa para evitar polls demasiado frecuentes (umbral configurable).
  DateTime? _lastPollTimestamp;

  /// Tiempo de inactividad antes de volver a [DisplayMode.attract].
  Duration get _inactivityTimeout => Duration(
        seconds: AppSettings().customerSessionTimeoutSeconds,
      );

  HomeCubit({
    required GetProductsUseCase getProducts,
    required GetMerchantInfoUseCase getMerchant,
  })  : _getProducts = getProducts,
        _getMerchant = getMerchant,
        super(const HomeState()) {
    load();
  }

  void incrementProduct(Product product) {
    final quantities = Map<String, int>.from(state.cartQuantities);
    final key = HomeState.cartKey(product);
    final currentQuantity = quantities[key] ?? 0;
    if (currentQuantity >= AppSettings().maxCartItemQuantity) {
      registerCartInteraction();
      return;
    }
    quantities[key] = currentQuantity + 1;
    emit(state.copyWith(cartQuantities: Map.unmodifiable(quantities)));
    registerCartInteraction();
  }

  void decrementProduct(Product product) {
    final quantities = Map<String, int>.from(state.cartQuantities);
    final key = HomeState.cartKey(product);
    final currentQuantity = quantities[key] ?? 0;
    if (currentQuantity <= 0) return;
    final nextQuantity = currentQuantity - 1;
    if (nextQuantity <= 0) {
      quantities.remove(key);
    } else {
      quantities[key] = nextQuantity;
    }
    emit(state.copyWith(cartQuantities: Map.unmodifiable(quantities)));
    registerCartInteraction();
  }

  void removeProductFromCart(Product product) {
    final quantities = Map<String, int>.from(state.cartQuantities)
      ..remove(HomeState.cartKey(product));
    emit(state.copyWith(cartQuantities: Map.unmodifiable(quantities)));
    registerCartInteraction();
  }

  void clearCart() {
    if (state.cartQuantities.isEmpty) return;
    emit(state.copyWith(cartQuantities: const {}));
    registerCartInteraction();
  }

  /// Reinicia el timeout mientras el cliente interactua con el carrito.
  void registerCartInteraction() {
    if (state.displayMode != DisplayMode.product) return;
    _cancelInactivityTimer();
    _startInactivityTimer(_inactivityTimeout);
  }

  /// Pausa la sesion de la home mientras otra pantalla controla el flujo.
  void pauseCustomerSessionTimeout() {
    _cancelInactivityTimer();
    debugPrint('[HomeCubit] Timeout de sesion pausado');
  }

  /// Reanuda el timeout solo si el cliente regreso al catalogo.
  void resumeCustomerSessionTimeout() {
    if (isClosed || state.displayMode != DisplayMode.product) return;
    _cancelInactivityTimer();
    _startInactivityTimer(_inactivityTimeout);
    debugPrint('[HomeCubit] Timeout de sesion reanudado');
  }

  /// Con un solo restaurante (con productos) se elige solo (se salta "Elige
  /// restaurante", § 8.45).
  int? get _defaultMerchantId {
    final available = state.availableMerchantIds;
    return available.length == 1 ? available.first : null;
  }

  /// Vuelve a "Elige restaurante" (o al único restaurante) y a la pestaña TODO.
  HomeState _resetSelection(HomeState s) => s.copyWith(
        selectedMerchantId: _defaultMerchantId,
        clearSelectedMerchant: _defaultMerchantId == null,
        clearSelectedCategory: true,
      );

  /// El cliente toca un restaurante (o el logo para volver: null).
  void selectMerchant(int? merchantId) {
    emit(state.copyWith(
      selectedMerchantId: merchantId,
      clearSelectedMerchant: merchantId == null,
      clearSelectedCategory: true,
      currentIndex: 0,
    ));
    registerCartInteraction();
  }

  /// Seleccion remota: ir a una pagina concreta manteniendo TODO el menu
  /// navegable y sin agregar items ni reiniciar el carrito.
  Map<String, dynamic> showProductById(int merchantId, int productId) {
    if (state.status != HomeStatus.loaded) {
      return {
        'success': false,
        'reason': 'CATALOG_NOT_LOADED',
        'message': 'El catalogo aun no esta cargado',
      };
    }
    // NEXUS_OPERADOR_COMERCIO_LIBRE_V1
    // La seleccion desde el operador no depende del comercio visible antes.
    // Si un filtro temporal oculto al comercio pero sus productos siguen en
    // ProductCache, se restaura el catalogo cargado sin recargar la API ni
    // alterar pedidos. Este metodo solo se llama tras el control de
    // carrito/pago/sesion ocupada de HomePage.
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
        // Igual que /merchants/show, solo cuando el producto solicitado
        // pertenece a un comercio autorizado y ya cargado en el robot.
        filter.enabledMerchants.clear();
        final restoredProducts = cache.allProducts
            .where((p) => filter.isProductVisible(p.id, p.merchantId))
            .toList();
        if (restoredProducts.any(
          (p) => p.id == productId && p.merchantId == merchantId,
        )) {
          debugPrint(
              '[HomeCubit] Operador: restaurando comercio $merchantId desde ProductCache');
          emit(state.copyWith(
            products: restoredProducts,
            merchantIds: cache.loadedMerchantIds,
            merchantNames: cache.merchantNames,
          ));
        } else {
          // Mantener ocultos los productos bloqueados individualmente.
          filter.enabledMerchants.addAll(previousEnabledMerchants);
        }
      }
    }
    if (!state.availableMerchantIds.contains(merchantId)) {
      return {
        'success': false,
        'reason': 'MERCHANT_UNAVAILABLE',
        'message': 'El comercio no tiene productos visibles',
      };
    }
    final page = state.pageIndexForProduct(merchantId, productId);
    if (page == null) {
      return {
        'success': false,
        'reason': 'PRODUCT_NOT_VISIBLE',
        'message': 'Producto ausente u oculto en este comercio',
      };
    }
    final product = state.products.firstWhere(
      (p) => p.id == productId && p.merchantId == merchantId,
    );
    _leaveDevPreview();
    _cancelInactivityTimer();
    emit(state.copyWith(
      displayMode: DisplayMode.product,
      selectedMerchantId: merchantId,
      clearSelectedCategory: true,
      currentIndex: page,
      operatorFocusRevision: state.operatorFocusRevision + 1,
    ));
    _startInactivityTimer(_inactivityTimeout);
    return {
      'success': true,
      'merchantId': merchantId,
      'productId': productId,
      'productName': product.name,
      'pageIndex': page,
      'totalPages': state.pages.length,
      'focusRevision': state.operatorFocusRevision,
      'message': 'Pagina del producto seleccionada',
    };
  }

  /// El cliente toca una pestaña: el carrusel salta a la primera página de
  /// esa categoría (null = primera página).
  void selectCategory(String? category) {
    final page = category == null ? 0 : state.firstPageOf(category);
    if (page < 0) return;
    emit(state.copyWith(currentIndex: page));
    registerCartInteraction();
  }

  /// Solo debug (F9): estado real guardado antes de una vista previa.
  HomeState? _devSnapshot;

  /// Solo debug (F9): muestra [preview] (cargando, error, sin productos).
  void devPreview(HomeState preview) {
    if (!kDebugMode) return;
    _cancelInactivityTimer();
    _devSnapshot ??= state;
    emit(preview);
  }

  /// Si había una vista previa (F9) activa, vuelve al estado real ANTES de
  /// cambiar de pantalla (§ 8.45). Sin esto, p. ej. la vista previa "Sin
  /// productos" (menú vacío) seguía al volver a la cara: elegir cualquier
  /// restaurante llevaba otra vez a "Sin productos" (bucle).
  void _leaveDevPreview() {
    final real = _devSnapshot;
    if (real == null) return;
    _devSnapshot = null;
    debugPrint(
        '[HomeCubit] Fin de vista previa (F9): se restaura el estado real');
    emit(real);
  }

  /// Solo debug (F9): vuelve al estado real de antes de la vista previa.
  void devRestore() {
    if (!kDebugMode || _devSnapshot == null) return;
    emit(_devSnapshot!);
    _devSnapshot = null;
  }

  Future<void> load() async {
    _devSnapshot = null; // si se recarga de verdad, manda el estado nuevo
    emit(state.copyWith(status: HomeStatus.loading, errorMessage: null));
    debugPrint('[HomeCubit] load() iniciado');

    try {
      final result = await _loadWithRetry();

      // Poblar cache global para que AppServer pueda leer los productos
      final cache = ProductCache();
      cache.allProducts = List.unmodifiable(result.products);
      cache.merchantNames = List.unmodifiable(result.merchantNames);
      cache.loadedMerchantIds = List.unmodifiable(result.merchantIds);
      debugPrint(
          '[HomeCubit] ProductCache actualizado: ${result.products.length} productos de ${result.merchantIds.length} merchants');

      // Aplicar filtro de visibilidad antes de emitir el estado
      final settings = AppSettings();
      final filter = settings.filterConfig;
      final filteredProducts = result.products
          .where((p) => filter.isProductVisible(p.id, p.merchantId))
          .toList();

      debugPrint(
          '[HomeCubit] Filtro aplicado: ${result.products.length} total -> ${filteredProducts.length} visibles (modo: ${filter.filterMode})');

      // Solo cuentan los restaurantes con productos visibles (§ 8.45).
      final withProducts = [
        for (final id in result.merchantIds)
          if (filteredProducts.any((p) => p.merchantId == id)) id,
      ];
      final onlyMerchant = withProducts.length == 1 ? withProducts.first : null;
      emit(state.copyWith(
        status: HomeStatus.loaded,
        displayMode: DisplayMode.attract,
        cartQuantities: const {},
        products: filteredProducts,
        currentIndex: 0,
        merchantName: result.merchantName,
        merchantNames: result.merchantNames,
        merchantIds: result.merchantIds,
        merchantsById: result.merchantsById,
        selectedMerchantId: onlyMerchant,
        clearSelectedMerchant: onlyMerchant == null,
        clearSelectedCategory: true,
      ));
      debugPrint(
          '[HomeCubit] Estado emitido: loaded + attract (${filteredProducts.length} productos de ${result.merchantIds.length} merchants)');

      // Marcar timestamp del último poll exitoso.
      _lastPollTimestamp = DateTime.now();
    } catch (e, stack) {
      debugPrint('[HomeCubit] load FAILED (incluyendo retry): $e');
      debugPrint('[HomeCubit] StackTrace: $stack');
      emit(state.copyWith(
        status: HomeStatus.error,
        errorMessage: 'No se pudieron cargar los productos.\n${e.toString()}',
      ));
    }
  }

  Future<_HomeLoadResult> _loadWithRetry() async {
    const maxRetries = 1;
    const retryDelay = Duration(seconds: 2);

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        debugPrint(
            '[HomeCubit] Reintentando en ${retryDelay.inSeconds}s... (intento ${attempt + 1}/${maxRetries + 1})');
        await Future.delayed(retryDelay);
      }

      try {
        final settings = AppSettings();
        final merchantsToLoad = settings.merchantIds;
        debugPrint(
            '[HomeCubit] merchantIds=$merchantsToLoad (intento ${attempt + 1})');

        if (merchantsToLoad.isEmpty) {
          throw Exception('No hay merchants configurados');
        }

        // Cargar todos los merchants en paralelo
        debugPrint(
            '[HomeCubit] Cargando ${merchantsToLoad.length} merchants en paralelo...');
        final results = await Future.wait(
          merchantsToLoad.map((merchantId) => _loadSingleMerchant(merchantId)),
        );

        // Combinar resultados de todos los merchants
        final allProducts = <Product>[];
        final merchantNames = <String>[];
        final loadedMerchantIds = <int>[];
        final merchantsById = <int, Merchant>{};
        final errors = <String>[];

        for (var i = 0; i < results.length; i++) {
          final merchantId = merchantsToLoad[i];
          final result = results[i];

          if (result != null) {
            allProducts.addAll(result.products);
            merchantNames.add(result.merchant.name);
            loadedMerchantIds.add(merchantId);
            merchantsById[merchantId] = result.merchant;
            debugPrint(
                '[HomeCubit] Merchant $merchantId: ${result.products.length} productos cargados');
          } else {
            errors.add('Merchant $merchantId: fallo al cargar');
          }
        }

        if (loadedMerchantIds.isEmpty) {
          throw Exception(
              'No se pudieron cargar productos de ningun merchant.\n${errors.join('\n')}');
        }

        if (errors.isNotEmpty) {
          debugPrint(
              '[HomeCubit] [WARN] ${errors.length} merchants fallaron, pero se cargaron ${allProducts.length} productos de ${loadedMerchantIds.length} merchants');
        }

        // merchantName principal: combina los nombres de todos los merchants
        final primaryName = merchantNames.join(' | ');

        return _HomeLoadResult(
          products: allProducts,
          merchantName: primaryName,
          merchantNames: merchantNames,
          merchantIds: loadedMerchantIds,
          merchantsById: Map.unmodifiable(merchantsById),
        );
      } catch (e) {
        if (attempt < maxRetries) {
          debugPrint('[HomeCubit] Intento ${attempt + 1} fallo: $e');
          continue;
        }
        rethrow;
      }
    }

    throw Exception('Agotados todos los intentos de carga');
  }

  /// Carga los productos e info de un solo merchant.
  /// Retorna null si falla (para manejo graceful de errores).
  Future<_MerchantLoadResult?> _loadSingleMerchant(int merchantId) async {
    try {
      debugPrint('[HomeCubit] Cargando merchant $merchantId...');
      final products = await _getProducts(merchantId);
      final merchant = await _getMerchant(merchantId);
      debugPrint(
          '[HomeCubit] Merchant $merchantId OK: ${products.length} productos, nombre="${merchant.name}"');
      return _MerchantLoadResult(products: products, merchant: merchant);
    } catch (e) {
      debugPrint('[HomeCubit] Error cargando merchant $merchantId: $e');
      return null; // Falla gracefully: un merchant caido no detiene a los demas
    }
  }

  // ─── Polling on-demand ─────────────────────────────────────────────────────

  /// Verifica si los datos están stale y ejecuta un poll si es necesario.
  ///
  /// Se llama cada vez que se va a mostrar el carrusel de productos.
  /// Si el último poll fue hace menos de [AppSettings.productPollingStaleSeconds]
  /// segundos, omite el poll y usa los datos actuales.
  Future<void> _pollIfStale() async {
    final staleSeconds = AppSettings().productPollingStaleSeconds;
    if (staleSeconds <= 0) {
      debugPrint(
          '[HomeCubit] Polling on-demand DESHABILITADO (stale=$staleSeconds)');
      return;
    }

    final staleThreshold = Duration(seconds: staleSeconds);

    if (_lastPollTimestamp == null) {
      // Nunca se ha hecho poll (ej: primer showProduct tras load fallido)
      debugPrint('[HomeCubit] Sin timestamp previo → forzando poll');
      await _pollProducts();
      return;
    }

    final elapsed = DateTime.now().difference(_lastPollTimestamp!);
    if (elapsed >= staleThreshold) {
      debugPrint(
          '[HomeCubit] Datos stale (${elapsed.inSeconds}s >= ${staleSeconds}s) → ejecutando poll');
      await _pollProducts();
    } else {
      debugPrint(
          '[HomeCubit] Datos frescos (${elapsed.inSeconds}s < ${staleSeconds}s) → omitiendo poll');
    }
  }

  /// Fuerza un poll incondicional (ignora el umbral de staleness).
  ///
  /// Útil para comandos de recarga manual (remote-control, /products/reload).
  Future<void> forcePoll() async {
    debugPrint('[HomeCubit] forcePoll() → forzando poll incondicional');
    _lastPollTimestamp = null; // Anular timestamp para forzar
    await _pollProducts();
  }

  /// Ejecuta un ciclo de polling: obtiene productos frescos de la API
  /// y actualiza el estado silenciosamente si hay cambios.
  ///
  /// No interrumpe al usuario:
  /// - Mantiene el [displayMode] actual.
  /// - Recalcula [currentIndex] si el producto activo sigue existiendo.
  /// - Resetea [currentIndex] a 0 si el producto activo fue eliminado.
  /// - Si no hay cambios, no emite estado (ahorra rebuilds).
  Future<void> _pollProducts() async {
    if (isClosed) return;

    debugPrint('[HomeCubit] [POLL] Iniciando ciclo de polling...');
    try {
      final result = await _loadWithRetry();

      // Aplicar filtro de visibilidad
      final settings = AppSettings();
      final filter = settings.filterConfig;
      final freshProducts = result.products
          .where((p) => filter.isProductVisible(p.id, p.merchantId))
          .toList();

      // Comparar con los productos actuales para detectar cambios
      final currentProducts = state.products;
      final cartSync = _reconcileCart(currentProducts, freshProducts);
      final productsChanged =
          !_listsAreIdentical(currentProducts, freshProducts);
      final cartChanged =
          !_cartMapsAreEqual(state.cartQuantities, cartSync.quantities);
      if (!productsChanged && !cartChanged) {
        // Sin cambios: actualizar timestamp pero no emitir estado
        debugPrint('[HomeCubit] [OK] Polling: sin cambios detectados');
        _lastPollTimestamp = DateTime.now();
        return;
      }

      // ── Hay cambios: loguear detalle de lo que cambió ──
      debugPrint(
          '[HomeCubit] [CHG] ──────────────────────────────────────────────');
      debugPrint('[HomeCubit] [CHG] POLLING: CAMBIOS DETECTADOS');
      debugPrint(
          '[HomeCubit] [CHG] Antes: ${currentProducts.length} productos → Ahora: ${freshProducts.length} productos');
      _logProductDiff(currentProducts, freshProducts);
      debugPrint(
          '[HomeCubit] [CHG] ──────────────────────────────────────────────');

      // Actualizar cache global con los productos frescos
      final cache = ProductCache();
      cache.allProducts = List.unmodifiable(result.products);
      cache.merchantNames = List.unmodifiable(result.merchantNames);
      cache.loadedMerchantIds = List.unmodifiable(result.merchantIds);
      debugPrint(
          '[HomeCubit] ProductCache actualizado: ${result.products.length} productos de ${result.merchantIds.length} merchants');

      // currentIndex = página del carrusel. Se mantiene; el carrusel la
      // ajusta si ahora hay menos páginas.
      final newIndex = state.currentIndex;

      // Marcar timestamp del poll exitoso
      _lastPollTimestamp = DateTime.now();

      // Emitir nuevo estado sin cambiar displayMode
      emit(state.copyWith(
        status: HomeStatus.loaded,
        products: freshProducts,
        currentIndex: newIndex,
        cartQuantities: Map.unmodifiable(cartSync.quantities),
        cartSyncMessage: cartSync.message,
        cartSyncRevision: cartSync.message == null
            ? state.cartSyncRevision
            : state.cartSyncRevision + 1,
        merchantName: result.merchantName,
        merchantNames: result.merchantNames,
        merchantIds: result.merchantIds,
        merchantsById: result.merchantsById,
        lastPolledAt: DateTime.now(),
      ));

      debugPrint(
          '[HomeCubit] [OK] Estado actualizado vía polling (${freshProducts.length} productos visibles, índice=$newIndex)');
    } catch (e, stack) {
      // Fallo silencioso: no interrumpir al usuario, solo loguear.
      debugPrint('[HomeCubit] [WARN] Polling falló (red caída?): $e');
      debugPrint('[HomeCubit] StackTrace: $stack');
      // El estado actual se mantiene intacto. NO actualizar _lastPollTimestamp.
    }
  }

  /// Compara dos listas de productos para determinar si son idénticas.
  ///
  /// Compara: orden, IDs, y campos relevantes (nombre, precio, oldPrice,
  /// descripción, urlImage, merchantId).
  _CartSyncResult _reconcileCart(
    List<Product> currentProducts,
    List<Product> freshProducts,
  ) {
    final currentByKey = {
      for (final product in currentProducts)
        HomeState.cartKey(product): product,
    };
    final freshByKey = {
      for (final product in freshProducts) HomeState.cartKey(product): product,
    };
    final quantities = <String, int>{};
    final removedNames = <String>[];
    final priceChangedNames = <String>[];

    for (final entry in state.cartQuantities.entries) {
      if (entry.value <= 0) continue;
      final freshProduct = freshByKey[entry.key];
      if (freshProduct == null) {
        removedNames.add(currentByKey[entry.key]?.name ?? 'Un producto');
        continue;
      }

      quantities[entry.key] = entry.value;
      final previousProduct = currentByKey[entry.key];
      if (previousProduct != null &&
          previousProduct.price != freshProduct.price) {
        priceChangedNames.add(freshProduct.name);
      }
    }

    final messages = <String>[];
    if (removedNames.isNotEmpty) {
      final availability = removedNames.length == 1
          ? 'ya no está disponible y fue retirado'
          : 'ya no están disponibles y fueron retirados';
      messages.add('${removedNames.join(', ')} $availability del carrito.');
    }
    if (priceChangedNames.isNotEmpty) {
      messages.add(
        'Se actualizó el precio de ${priceChangedNames.join(', ')}. '
        'Revisa el nuevo total.',
      );
    }

    return _CartSyncResult(
      quantities: quantities,
      message: messages.isEmpty ? null : messages.join(' '),
    );
  }

  bool _cartMapsAreEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _listsAreIdentical(List<Product> a, List<Product> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      if (a[i].name != b[i].name) return false;
      if (a[i].price != b[i].price) return false;
      if (a[i].oldPrice != b[i].oldPrice) return false;
      if (a[i].description != b[i].description) return false;
      if (a[i].urlImage != b[i].urlImage) return false;
      if (a[i].merchantId != b[i].merchantId) return false;
    }
    return true;
  }

  /// Loguea los cambios entre dos listas de productos para debugging.
  void _logProductDiff(List<Product> oldList, List<Product> newList) {
    final oldIds = oldList.map((p) => p.id).toSet();
    final newIds = newList.map((p) => p.id).toSet();

    // Productos agregados
    final added = newIds.difference(oldIds);
    if (added.isNotEmpty) {
      final addedProducts = newList.where((p) => added.contains(p.id));
      for (final p in addedProducts) {
        debugPrint('[HomeCubit]   [ADD] NUEVO:  "${p.name}" (ID: ${p.id}, '
            'Bs ${p.price}, merchant ${p.merchantId})');
      }
    }

    // Productos eliminados/ocultados
    final removed = oldIds.difference(newIds);
    if (removed.isNotEmpty) {
      final removedProducts = oldList.where((p) => removed.contains(p.id));
      for (final p in removedProducts) {
        debugPrint('[HomeCubit]   [DEL] OCULTO: "${p.name}" (ID: ${p.id}, '
            'merchant ${p.merchantId})');
      }
    }

    // Productos modificados (mismo ID pero campos cambiaron)
    final kept = oldIds.intersection(newIds);
    for (final id in kept) {
      final old = oldList.firstWhere((p) => p.id == id);
      final fresh = newList.firstWhere((p) => p.id == id);
      final changes = <String>[];
      if (old.name != fresh.name) {
        changes.add('nombre: "${old.name}" → "${fresh.name}"');
      }
      if (old.price != fresh.price) {
        changes.add('precio: Bs ${old.price} → Bs ${fresh.price}');
      }
      if (old.description != fresh.description) changes.add('descripción');
      if (old.urlImage != fresh.urlImage) changes.add('imagen');
      if (old.oldPrice != fresh.oldPrice) changes.add('oldPrice');
      if (changes.isNotEmpty) {
        debugPrint('[HomeCubit]   [EDIT]  EDITADO: "${fresh.name}" (ID: $id, '
            'merchant ${fresh.merchantId}): ${changes.join(', ')}');
      }
    }
  }

  // ─── Fin polling ───────────────────────────────────────────────────────────

  /// Actualiza el indice del producto seleccionado en el carrusel.
  /// Reinicia el timer de inactividad cada vez que el usuario hace swipe.
  void updateCurrentIndex(int index) {
    if (index != state.currentIndex) {
      emit(state.copyWith(currentIndex: index));
      _cancelInactivityTimer();
      _startInactivityTimer(_inactivityTimeout);
    }
  }

  /// Muestra el video de atraccion (robot cerca de persona).
  ///
  /// Si [gifAsset] es provisto, actualiza el GIF mostrado.
  /// Si es null, mantiene el GIF actual configurado en el estado.
  Future<void> showAttract({String? gifAsset}) async {
    debugPrint('[HomeCubit] showAttract(gifAsset: $gifAsset) llamado');
    _leaveDevPreview();
    _cancelInactivityTimer();

    emit(_resetSelection(state.copyWith(
      displayMode: DisplayMode.attract,
      attractGifAsset: gifAsset ?? state.attractGifAsset,
      cartQuantities: const {},
    )));
    debugPrint(
        '[HomeCubit] Estado emitido: displayMode=attract, gif=${gifAsset ?? state.attractGifAsset}');

    if (state.status == HomeStatus.error) {
      debugPrint(
          '[HomeCubit] showAttract() -> status=error, recargando en background...');
      await load();
    }
  }

  /// Cambia el GIF de atraccion y forza el modo attract inmediatamente.
  ///
  /// [assetPath] debe ser una ruta de asset valida (ej: `assets/images/coffee.gif`).
  /// Si es null, se usa el GIF por defecto (`assets/images/normal.gif`).
  Future<void> setAttractGif(String? assetPath) async {
    final gif = assetPath ?? 'assets/images/normal.gif';
    debugPrint('[HomeCubit] setAttractGif($gif) llamado');
    await showAttract(gifAsset: gif);
  }

  /// Muestra el carrusel de productos y programa el timer de inactividad.
  Future<void> showProduct() async {
    return showProductWithTimeout(_inactivityTimeout);
  }

  /// Muestra el carrusel con un timeout de inactividad personalizado.
  Future<void> showProductWithTimeout(Duration timeout) async {
    debugPrint(
        '[HomeCubit] showProductWithTimeout(${timeout.inSeconds}s) llamado');
    _leaveDevPreview();
    _cancelInactivityTimer();

    // Fase 8 (rendimiento): si ya hay menú, se muestra YA y se refresca en
    // segundo plano (antes se esperaba a la red y la hoja tardaba en subir).
    // Si llegan cambios, el polling actualiza la pantalla y el carrito solo.
    if (state.status == HomeStatus.loaded) {
      emit(state.copyWith(displayMode: DisplayMode.product));
      debugPrint('[HomeCubit] Estado emitido: displayMode=product');
      _startInactivityTimer(timeout);
      unawaited(_pollIfStale());
      return;
    }

    // Sin menú todavía: hay que esperarlo.
    await _pollIfStale();

    if (state.status == HomeStatus.loaded) {
      emit(state.copyWith(displayMode: DisplayMode.product));
      debugPrint('[HomeCubit] Estado emitido: displayMode=product');
      _startInactivityTimer(timeout);
      return;
    }

    if (state.status == HomeStatus.error) {
      debugPrint(
          '[HomeCubit] showProductWithTimeout() -> status=error, recargando...');
      await load();
      if (state.status == HomeStatus.loaded) {
        emit(state.copyWith(displayMode: DisplayMode.product));
        debugPrint('[HomeCubit] Recarga OK -> displayMode=product');
        _startInactivityTimer(timeout);
      } else {
        debugPrint('[HomeCubit] Recarga fallo, no se puede mostrar productos');
      }
      return;
    }

    debugPrint(
        '[HomeCubit] showProductWithTimeout() ignorado: status=${state.status}');
  }

  /// Vuelve a reposo / espera.
  Future<void> showIdle() async {
    debugPrint('[HomeCubit] showIdle() llamado');
    _leaveDevPreview();
    _cancelInactivityTimer();

    emit(_resetSelection(state.copyWith(
      displayMode: DisplayMode.idle,
      cartQuantities: const {},
    )));
    debugPrint('[HomeCubit] Estado emitido: displayMode=idle');

    if (state.status == HomeStatus.error) {
      debugPrint(
          '[HomeCubit] showIdle() -> status=error, recargando en background...');
      await load();
    }
  }

  /// Muestra "Elige restaurante" con una sesion nueva (carrito vacio).
  ///
  /// Re-aplica el filtro actual sobre [ProductCache] sin ir a la red, para
  /// que los comercios recien habilitados (`POST /merchants/show`) aparezcan
  /// al instante. Con un solo comercio con productos se va a su catalogo.
  Future<void> showMerchantPicker() async {
    debugPrint('[HomeCubit] showMerchantPicker() llamado');
    final cache = ProductCache();
    if (state.status != HomeStatus.loaded || !cache.isLoaded) {
      // Sin menu todavia: el flujo normal lo espera y resetea la seleccion.
      await showProductResetCarousel();
      return;
    }

    _leaveDevPreview();
    _cancelInactivityTimer();

    final filter = AppSettings().filterConfig;
    final next = state.copyWith(
      displayMode: DisplayMode.product,
      products: cache.allProducts
          .where((p) => filter.isProductVisible(p.id, p.merchantId))
          .toList(),
      currentIndex: 0,
      cartQuantities: const {},
      clearSelectedCategory: true,
    );
    final available = next.availableMerchantIds;
    final onlyMerchant = available.length == 1 ? available.first : null;
    emit(next.copyWith(
      selectedMerchantId: onlyMerchant,
      clearSelectedMerchant: onlyMerchant == null,
    ));
    debugPrint('[HomeCubit] Estado emitido: displayMode=product + '
        '${onlyMerchant == null ? "Elige restaurante" : "catalogo $onlyMerchant"}');
    _startInactivityTimer(_inactivityTimeout);
  }

  /// Muestra el carrusel de productos y resetea el indice al primer elemento.
  /// Ideal para cuando se reproduce el audio "Quieres un cafe?".
  Future<void> showProductResetCarousel() async {
    final timeout = _inactivityTimeout;
    _leaveDevPreview();
    debugPrint(
        '[HomeCubit] showProductResetCarousel(${timeout.inSeconds}s) llamado');
    _cancelInactivityTimer();

    void show() {
      emit(_resetSelection(state.copyWith(
        displayMode: DisplayMode.product,
        currentIndex: 0,
        cartQuantities: const {},
      )));
      debugPrint(
          '[HomeCubit] Estado emitido: displayMode=product + currentIndex=0');
      _startInactivityTimer(timeout);
    }

    // Fase 8 (rendimiento): con menú cargado se muestra YA y se refresca en
    // segundo plano (ver showProductWithTimeout).
    if (state.status == HomeStatus.loaded) {
      show();
      unawaited(_pollIfStale());
      return;
    }

    // Sin menú todavía: hay que esperarlo.
    await _pollIfStale();

    if (state.status == HomeStatus.loaded) {
      show();
      return;
    }

    if (state.status == HomeStatus.error) {
      debugPrint(
          '[HomeCubit] showProductResetCarousel() -> status=error, recargando...');
      await load();
      if (state.status == HomeStatus.loaded) {
        emit(_resetSelection(state.copyWith(
          displayMode: DisplayMode.product,
          currentIndex: 0,
          cartQuantities: const {},
        )));
        debugPrint(
            '[HomeCubit] Recarga OK -> displayMode=product + currentIndex=0');
        _startInactivityTimer(timeout);
      } else {
        debugPrint('[HomeCubit] Recarga fallo, no se puede mostrar productos');
      }
      return;
    }

    debugPrint(
        '[HomeCubit] showProductResetCarousel() ignorado: status=${state.status}');
  }

  void _startInactivityTimer([Duration? timeout]) {
    final duration = timeout ?? _inactivityTimeout;
    _inactivityTimer?.cancel();
    debugPrint(
        '[HomeCubit] Timer de inactividad iniciado (${duration.inSeconds}s)');
    _inactivityTimer = Timer(duration, () {
      if (!isClosed) {
        debugPrint(
            '[HomeCubit] Timer de inactividad expirado -> volviendo a attract');
        showAttract();
      }
    });
  }

  void _cancelInactivityTimer() {
    if (_inactivityTimer != null) {
      debugPrint('[HomeCubit] Timer de inactividad cancelado');
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
    }
  }

  @override
  Future<void> close() {
    _cancelInactivityTimer();
    return super.close();
  }
}

class _HomeLoadResult {
  final List<Product> products;
  final String merchantName;
  final List<String> merchantNames;
  final List<int> merchantIds;
  final Map<int, Merchant> merchantsById;

  const _HomeLoadResult({
    required this.products,
    required this.merchantName,
    required this.merchantNames,
    required this.merchantIds,
    required this.merchantsById,
  });
}

class _MerchantLoadResult {
  final List<Product> products;
  final Merchant merchant;

  const _MerchantLoadResult({
    required this.products,
    required this.merchant,
  });
}

class _CartSyncResult {
  final Map<String, int> quantities;
  final String? message;

  const _CartSyncResult({
    required this.quantities,
    required this.message,
  });
}
