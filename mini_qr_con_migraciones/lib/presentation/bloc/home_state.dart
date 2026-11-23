import 'package:equatable/equatable.dart';
import '../../domain/entities/merchant.dart';
import '../../domain/entities/product.dart';

enum HomeStatus { initial, loading, loaded, error }

/// Modo de visualizacion en la pantalla principal.
/// - [idle]: reposo (pantalla negra / espera).
/// - [attract]: video de atraccion cuando el robot esta cerca.
/// - [product]: carrusel de productos y boton de pago.
enum DisplayMode { idle, attract, product }

class HomeState extends Equatable {
  final HomeStatus status;
  final DisplayMode displayMode;
  final List<Product> products;
  final int currentIndex;

  /// Cambia solo cuando el operador pide abrir un producto exacto.
  /// Recrea el carrusel en su pagina de destino sin deslizamiento intermedio.
  final int operatorFocusRevision;
  final String merchantName;
  final List<String> merchantNames;
  final List<int> merchantIds;
  final Map<int, Merchant> merchantsById;
  final Map<String, int> cartQuantities;
  final String? cartSyncMessage;
  final int cartSyncRevision;
  final String? errorMessage;

  /// Marca de tiempo del último polling exitoso de productos.
  /// `null` si nunca se ha ejecutado el polling.
  final DateTime? lastPolledAt;

  /// Ruta del asset GIF que se muestra en modo [DisplayMode.attract].
  /// Por defecto `assets/images/normal.gif`.
  final String attractGifAsset;

  /// Restaurante elegido en "Elige restaurante". null = todavía no eligió.
  final int? selectedMerchantId;

  /// Pestaña activa. null = "TODO".
  final String? selectedCategory;

  /// Producto destacado por restaurante: merchantId → idProduct.
  /// Vacío hasta que exista el endpoint del destacado.
  final Map<int, int> featuredByMerchant;

  const HomeState({
    this.status = HomeStatus.initial,
    this.displayMode = DisplayMode.idle,
    this.products = const [],
    this.currentIndex = 0,
    this.operatorFocusRevision = 0,
    this.merchantName = 'Mi Tienda',
    this.merchantNames = const [],
    this.merchantIds = const [],
    this.merchantsById = const {},
    this.cartQuantities = const {},
    this.cartSyncMessage,
    this.cartSyncRevision = 0,
    this.errorMessage,
    this.lastPolledAt,
    this.attractGifAsset = 'assets/images/normal.gif',
    this.selectedMerchantId,
    this.selectedCategory,
    this.featuredByMerchant = const {},
  });

  static const productsPerPage = 6; // cuadrícula 2 × 3

  /// Restaurantes que tienen al menos un producto visible (§ 8.45). Uno sin
  /// productos (todo inactivo en el backend, filtro, etc.) no se ofrece: al
  /// elegirlo solo se llegaba a "Sin productos".
  List<int> get availableMerchantIds => [
        for (final id in merchantIds)
          if (products.any((p) => p.merchantId == id)) id,
      ];

  /// REGLA: "Elige restaurante" solo existe con 2 o más restaurantes CON
  /// productos. Con 1 solo se pasa directo a su catálogo.
  bool get hasMerchantChoice => availableMerchantIds.length > 1;

  /// true → se ve "Elige restaurante". También si el elegido se quedó sin
  /// productos (p. ej. tras un refresco del menú) y hay otros: se vuelve a
  /// la lista en vez de mostrar "Sin productos" (§ 8.45).
  bool get showMerchantPicker {
    if (!hasMerchantChoice) return false;
    final selected = selectedMerchantId;
    return selected == null || !availableMerchantIds.contains(selected);
  }

  /// Productos del restaurante elegido. Sin elegir → todos (como hoy).
  List<Product> get merchantProducts => selectedMerchantId == null
      ? products
      : products.where((p) => p.merchantId == selectedMerchantId).toList();

  /// Nombres de categoría sin repetir, en el orden en que llegan del backend.
  List<String> get categories {
    final seen = <String>{};
    for (final p in merchantProducts) {
      final c = p.category;
      if (c != null && c.isNotEmpty) seen.add(c);
    }
    return seen.toList();
  }

  /// Destacado del restaurante elegido (null si no hay o ya no está en el menú).
  Product? get featuredProduct {
    final id = featuredByMerchant[selectedMerchantId];
    if (id == null) return null;
    return merchantProducts.where((p) => p.id == id).firstOrNull;
  }

  /// Productos de la cuadrícula: categoría activa, sin el destacado.
  List<Product> get visibleProducts {
    final featuredId = featuredProduct?.id;
    return merchantProducts
        .where(
            (p) => selectedCategory == null || p.category == selectedCategory)
        .where((p) => p.id != featuredId)
        .toList();
  }

  /// Páginas de 6 agrupadas por categoría, en el orden del backend (una
  /// categoría nunca comparte página con otra). Sin categoría → al final.
  List<(String?, List<Product>)> get _pageGroups {
    final groups = <String?, List<Product>>{for (final c in categories) c: []};
    for (final p in visibleProducts) {
      final c = (p.category?.isEmpty ?? true) ? null : p.category;
      groups.putIfAbsent(c, () => []).add(p);
    }
    return [
      for (final e in groups.entries)
        for (var i = 0; i < e.value.length; i += productsPerPage)
          (
            e.key,
            e.value.sublist(i, (i + productsPerPage).clamp(0, e.value.length)),
          ),
    ];
  }

  /// Productos de cada página del carrusel.
  List<List<Product>> get pages => [for (final g in _pageGroups) g.$2];

  /// Categoría de cada página (misma posición que [pages]).
  List<String?> get pageCategories => [for (final g in _pageGroups) g.$1];

  /// Busca la pagina para un producto, seleccionando su comercio y la
  /// pestaña TODO sin alterar productos, categorias ni filtros persistentes.
  /// Retorna null si el producto no esta visible en este comercio.
  int? pageIndexForProduct(int merchantId, int productId) {
    final target = copyWith(
      selectedMerchantId: merchantId,
      clearSelectedCategory: true,
    );
    if (!target.products.any(
        (p) => p.id == productId && p.merchantId == merchantId)) {
      return null;
    }
    if (target.featuredProduct?.id == productId) return 0;
    final pages = target.pages;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].any((p) => p.id == productId)) return i;
    }
    return null;
  }

  /// Categoría de la página que se está viendo → pestaña activa.
  String? get activeCategory {
    final cats = pageCategories;
    return cats.isEmpty ? null : cats[currentIndex.clamp(0, cats.length - 1)];
  }

  /// Primera página de [category] (-1 si no tiene productos).
  int firstPageOf(String category) => pageCategories.indexOf(category);

  static String cartKey(Product product) =>
      '${product.merchantId}_${product.id}';

  int quantityFor(Product product) => cartQuantities[cartKey(product)] ?? 0;

  /// Solo los del restaurante elegido (sin elegir → todos).
  List<Product> get cartProducts =>
      merchantProducts.where((product) => quantityFor(product) > 0).toList();

  int get cartTotalItems =>
      cartProducts.fold(0, (total, p) => total + quantityFor(p));

  double get cartTotal => cartProducts.fold(
        0,
        (total, product) => total + product.price * quantityFor(product),
      );

  /// Obtiene el nombre del merchant para un producto especifico.
  String getMerchantNameForProduct(Product product) {
    final merchant = merchantsById[product.merchantId];
    if (merchant != null) return merchant.name;

    final index = merchantIds.indexOf(product.merchantId);
    if (index >= 0 && index < merchantNames.length) {
      return merchantNames[index];
    }
    return merchantName; // Fallback
  }

  bool merchantUsesBilling(int merchantId) =>
      merchantsById[merchantId]?.usesBilling ?? false;

  HomeState copyWith({
    HomeStatus? status,
    DisplayMode? displayMode,
    List<Product>? products,
    int? currentIndex,
    int? operatorFocusRevision,
    String? merchantName,
    List<String>? merchantNames,
    List<int>? merchantIds,
    Map<int, Merchant>? merchantsById,
    Map<String, int>? cartQuantities,
    String? cartSyncMessage,
    int? cartSyncRevision,
    String? errorMessage,
    DateTime? lastPolledAt,
    String? attractGifAsset,
    int? selectedMerchantId,
    bool clearSelectedMerchant = false,
    String? selectedCategory,
    bool clearSelectedCategory = false,
    Map<int, int>? featuredByMerchant,
  }) {
    return HomeState(
      status: status ?? this.status,
      displayMode: displayMode ?? this.displayMode,
      products: products ?? this.products,
      currentIndex: currentIndex ?? this.currentIndex,
      operatorFocusRevision:
          operatorFocusRevision ?? this.operatorFocusRevision,
      merchantName: merchantName ?? this.merchantName,
      merchantNames: merchantNames ?? this.merchantNames,
      merchantIds: merchantIds ?? this.merchantIds,
      merchantsById: merchantsById ?? this.merchantsById,
      cartQuantities: cartQuantities ?? this.cartQuantities,
      cartSyncMessage: cartSyncMessage ?? this.cartSyncMessage,
      cartSyncRevision: cartSyncRevision ?? this.cartSyncRevision,
      errorMessage: errorMessage ?? this.errorMessage,
      lastPolledAt: lastPolledAt ?? this.lastPolledAt,
      attractGifAsset: attractGifAsset ?? this.attractGifAsset,
      // Los flags permiten volver a null (copyWith con ?? no puede).
      selectedMerchantId: clearSelectedMerchant
          ? null
          : (selectedMerchantId ?? this.selectedMerchantId),
      selectedCategory: clearSelectedCategory
          ? null
          : (selectedCategory ?? this.selectedCategory),
      featuredByMerchant: featuredByMerchant ?? this.featuredByMerchant,
    );
  }

  @override
  List<Object?> get props => [
        status,
        displayMode,
        products,
        currentIndex,
        operatorFocusRevision,
        merchantName,
        merchantNames,
        merchantIds,
        merchantsById,
        cartQuantities,
        cartSyncMessage,
        cartSyncRevision,
        errorMessage,
        lastPolledAt,
        attractGifAsset,
        selectedMerchantId,
        selectedCategory,
        featuredByMerchant,
      ];
}
