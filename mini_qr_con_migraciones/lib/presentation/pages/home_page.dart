import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_settings.dart';
import '../../core/dev/dev_screen_menu.dart';
import '../../core/dev/dev_shortcuts.dart';
import '../../core/di/service_locator.dart';
import '../../core/services/image_preloader.dart';
import '../../core/services/ui_command_bus.dart';
import '../../core/ui/themes/app_colors.dart';
import '../../domain/entities/product.dart';
import '../bloc/home_cubit.dart';
import '../bloc/home_state.dart';
import '../bloc/qr_payment_state.dart';
import '../bloc/qr_payment_cubit.dart';
import '../widgets/attract_gif_player.dart';
import '../widgets/merchant_picker.dart';
import '../widgets/payment_result.dart';
import '../widgets/audio_overlay_wrapper.dart';
import '../widgets/audio_overlay_widget.dart';
import '../widgets/billing_dialogs.dart';
import '../widgets/category_tabs.dart';
import '../widgets/featured_card.dart';
import '../widgets/floating_cart.dart';
import '../widgets/motion/reveal.dart';
import '../widgets/motion/sheet_transition.dart';
import '../widgets/product_carousel.dart';
import 'qr_payment_page.dart';

/// Pantallas de la home, en el orden del diseño (01 Reposo → 03a Catálogo).
/// Ir hacia adelante en esta lista sube la hoja; ir hacia atrás la baja.
enum _HomeScreen {
  idle,
  loading,
  error,
  noProducts,
  attract,
  merchants,
  catalog;

  static _HomeScreen of(HomeState state) => switch (state.displayMode) {
        DisplayMode.attract => attract,
        DisplayMode.idle => idle,
        DisplayMode.product => switch (state.status) {
            HomeStatus.initial || HomeStatus.loading => loading,
            HomeStatus.error => error,
            HomeStatus.loaded => state.showMerchantPicker
                ? merchants
                : state.merchantProducts.isEmpty
                    ? noProducts
                    : catalog,
          },
      };
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl.homeCubit(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  StreamSubscription<UiCommand>? _commandSub;
  QrPaymentCubit? _activePaymentCubit;
  int _lastCartSyncRevision = 0;
  bool _isPreparingPayment = false;

  /// Posición del carrusel del catálogo en páginas, cuadro a cuadro. La
  /// escribe el carrusel y la lee la barra de categorías (§ 8.38).
  final ValueNotifier<double> _catalogPosition = ValueNotifier(0);

  /// Productos para los que ya se pidió la precarga de primeras páginas.
  List<Product>? _preloadedFor;

  /// Fotos del destacado y de la PRIMERA página de cada restaurante a
  /// memoria apenas llegan los productos (§ 8.39), mientras se ve la cara:
  /// al entrar al catálogo por primera vez ya están (antes la precarga
  /// empezaba recién al entrar y las fotos llegaban mientras aparecían las
  /// tarjetas). El resto de las páginas las precarga el carrusel al entrar.
  void _preloadFirstPages(BuildContext context, HomeState state) {
    if (state.status != HomeStatus.loaded ||
        identical(state.products, _preloadedFor)) {
      return;
    }
    _preloadedFor = state.products;
    final urls = <String>[];
    for (final id in state.merchantIds) {
      final m =
          state.copyWith(selectedMerchantId: id, clearSelectedCategory: true);
      final featured = m.featuredProduct;
      if (featured != null) urls.add(featured.urlImage);
      final pages = m.pages;
      if (pages.isNotEmpty) urls.addAll(pages.first.map((p) => p.urlImage));
    }
    ImagePreloader.preload(context, urls, concurrency: 2);
  }

  @override
  void initState() {
    super.initState();
    _commandSub = UiCommandBus.stream.listen(_onCommand);
  }

  @override
  void dispose() {
    _catalogPosition.dispose();
    _commandSub?.cancel();
    _activePaymentCubit?.close();
    _activePaymentCubit = null;
    super.dispose();
  }

  void _onCommand(UiCommand cmd) async {
    debugPrint('[HomePage] UiCommand recibido: $cmd');
    if (!mounted) {
      debugPrint('[HomePage] Comando ignorado: widget no montado');
      return;
    }
    final cubit = context.read<HomeCubit>();
    switch (cmd) {
      case ShowAttract(:final gifAsset):
        _cancelActivePayment();
        _popPaymentIfOpen();
        await cubit.showAttract(gifAsset: gifAsset);
        break;
      case ShowProductById(:final merchantId, :final productId, :final completed):
        // No cerrar ni cancelar una pantalla de pago ni una compra iniciada.
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
        if (result['success'] == true) {
          // El estado ya contiene el comercio y la pagina. Esperar a que la
          // hoja termine de entrar y el nuevo carrusel haya sido montado.
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          final s = cubit.state;
          final samePage = mounted &&
              s.status == HomeStatus.loaded &&
              s.displayMode == DisplayMode.product &&
              s.selectedMerchantId == merchantId &&
              s.operatorFocusRevision == result['focusRevision'] &&
              s.currentIndex == result['pageIndex'] &&
              s.pageIndexForProduct(merchantId, productId) == s.currentIndex &&
              !s.showMerchantPicker;
          if (!samePage) {
            result['success'] = false;
            result['reason'] = 'VIEW_CHANGED';
            result['message'] = 'La vista cambio antes de confirmar el producto';
          } else {
            result['pageReady'] = true;
            // Indica pagina montada, no garantiza imagen de red descargada.
          }
        }
        if (!completed.isCompleted) completed.complete(result);
        break;
      case ShowProduct():
        _cancelActivePayment();
        _popPaymentIfOpen();
        await cubit.showProduct();
        break;
      case CancelPayment():
        _cancelActivePayment();
        _popPaymentIfOpen();
        await cubit.showProductWithTimeout(const Duration(seconds: 5));
        break;
      case ShowIdle():
        _cancelActivePayment();
        _popPaymentIfOpen();
        await cubit.showIdle();
        break;
      case ReloadProduct():
        debugPrint('[HomePage] Recargando productos por cambio de config...');
        await cubit.load();
        break;
      case DevPreviewScreen(:final screen):
        if (kDebugMode) await _devPreview(screen);
        break;
      case ShowProductResetCarousel():
        _cancelActivePayment();
        _popPaymentIfOpen();
        await cubit.showProductResetCarousel();
        break;
      case ShowMerchantPicker():
        _cancelActivePayment();
        _popPaymentIfOpen();
        await cubit.showMerchantPicker();
        break;
      // ── Product polling ──
      case ForceProductPoll():
        await cubit.forcePoll();
        break;
      case GetProductPollingStatus():
        // No-op: el estado se consulta via HTTP (GET /products/polling/status)
        break;
      // Polling manual del QR: lo gestiona QrPaymentPage al navegar.
      case StartPaymentPolling():
      case StopPaymentPolling():
        break;
    }
  }

  void _cancelActivePayment() {
    _activePaymentCubit?.cancel();
    _activePaymentCubit = null;
  }

  void _popPaymentIfOpen() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AudioOverlayWrapper(
      position: AudioOverlayPosition.bottom,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: BlocConsumer<HomeCubit, HomeState>(
            listener: (context, state) {
              _preloadFirstPages(context, state);
              if (state.displayMode != DisplayMode.product) {
                // Una nueva sesion no debe mostrar avisos de la anterior.
                _lastCartSyncRevision = state.cartSyncRevision;
              }
              _showCartSyncNoticeIfNeeded(context, state);
            },
            builder: (context, state) {
              debugPrint(
                  '[HomePage] rebuild -> status=${state.status}, displayMode=${state.displayMode}');
              final screen = _HomeScreen.of(state);
              // Fase 8 (§ 8.31): TODOS los cambios de pantalla con la hoja,
              // también cargando, error y sin productos. Avanzar sube; volver
              // baja desde arriba (espejo). Misma duración y curva.
              return SheetSwitcher(
                screen: screen,
                order: screen.index,
                background: AppColors.background,
                child: switch (screen) {
                  // La cara entra con la hoja/fundido, sin cortina (§ 8.16).
                  _HomeScreen.attract => _devTapToCatalog(ColoredBox(
                      color: Colors.black,
                      child:
                          AttractGifPlayer(assetPath: state.attractGifAsset))),
                  _HomeScreen.idle => _devTapToCatalog(_buildIdle()),
                  _HomeScreen.loading => _buildLoading(),
                  _HomeScreen.error => _buildError(context),
                  _HomeScreen.merchants => _buildMerchantPicker(context, state),
                  _HomeScreen.noProducts => _buildNoProducts(context),
                  _HomeScreen.catalog => _buildContent(context, state),
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Solo en debug: tocar la cara o "Esperando..." abre el catálogo.
  /// En release devuelve [child] tal cual (sin GestureDetector).
  Widget _devTapToCatalog(Widget child) {
    if (!kDebugMode) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: DevShortcuts.onIdleOrAttractTap,
      child: child,
    );
  }

  Widget _buildMerchantPicker(BuildContext context, HomeState state) {
    return MerchantPicker(
      // Solo restaurantes con productos visibles (§ 8.45).
      merchants: [
        for (final id in state.availableMerchantIds)
          if (state.merchantsById[id] != null) state.merchantsById[id]!,
      ],
      onSelect: context.read<HomeCubit>().selectMerchant,
      logo: const _MegacenterLogo(),
    );
  }

  Widget _buildIdle() {
    return Container(
      color: AppColors.background,
      child: const Center(
        child: RevealIn(
          child: Text(
            'Esperando...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 24,
            ),
          ),
        ),
      ),
    );
  }

  /// Catálogo (03a/03b): lienzo de 1440×810 del diseño escalado a la pantalla.
  Widget _buildContent(BuildContext context, HomeState state) {
    final cubit = context.read<HomeCubit>();
    final maxQuantity = AppSettings().maxCartItemQuantity;
    final featured = state.featuredProduct;
    // Orden del revelado (fase 8): cabecera, destacado, 6 tarjetas, carrito.
    final firstTile = featured == null ? 1 : 2;

    return FittedBox(
      child: SizedBox(
        width: 1440,
        height: 810,
        child: Stack(
          children: [
            // Cabecera: logo (vuelve a "Elige restaurante") + pestañas.
            // Zona segura del robot (§ 8.46): el marco ovalado tapa las
            // esquinas, los costados curvos y ~55 px abajo. Todo queda dentro
            // (medidas del artifact "Zona segura del robot").
            Positioned(
              top: 70,
              left: 250,
              right: 250,
              height: 66,
              // Llega con la hoja (§ 8.39): sin esperar ni cortina.
              child: RevealIn(
                enabled: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: state.hasMerchantChoice
                          ? () => cubit.selectMerchant(null)
                          : null,
                      child: const SizedBox(
                        width: 64,
                        height: 64,
                        child: FittedBox(child: _MegacenterLogo()),
                      ),
                    ),
                    if (state.categories.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          // La pastilla se desliza a la par del carrusel.
                          child: CategoryTabs(
                            categories: state.categories,
                            selected: state.activeCategory,
                            onSelect: cubit.selectCategory,
                            pageCategories: state.pageCategories,
                            position: _catalogPosition,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Cuerpo: destacado · cuadrícula · carrito.
            Positioned(
              top: 158,
              left: 140,
              right: 144,
              height: 538,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (featured != null) ...[
                    // Entra suave con las tarjetas (§ 8.39).
                    SoftEntry(
                      index: 1,
                      child: FeaturedCard(
                        width: _featuredWidth,
                        height: _catalogCardsHeight,
                        product: featured,
                        quantity: state.quantityFor(featured),
                        maxQuantity: maxQuantity,
                        onAdd: () => cubit.incrementProduct(featured),
                        onRemove: () => cubit.decrementProduct(featured),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: ProductCarousel(
                      key: ValueKey(
                        '${state.selectedMerchantId}_${state.operatorFocusRevision}'),
                      pages: state.pages,
                      currentIndex: state.currentIndex,
                      quantityFor: state.quantityFor,
                      maxQuantity: maxQuantity,
                      onAdd: cubit.incrementProduct,
                      onRemove: cubit.decrementProduct,
                      onPageChanged: cubit.updateCurrentIndex,
                      position: _catalogPosition,
                      revealIndex: firstTile,
                      controlsShift:
                          _carouselControlsShift(hasFeatured: featured != null),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Llega con la hoja (§ 8.39).
                  RevealIn(
                    enabled: false,
                    index: firstTile + ProductCarousel.tilesPerPage,
                    child: FloatingCart(
                      height: _catalogCardsHeight,
                      products: state.cartProducts,
                      quantityFor: state.quantityFor,
                      totalItems: state.cartTotalItems,
                      totalAmount: state.cartTotal,
                      onPay: () => _goToPayment(context, state),
                    ),
                  ),
                ],
              ),
            ),
            // Fuera de la esquina de abajo a la izquierda (§ 8.46).
            const Positioned(
              left: 320,
              top: 636,
              child: _NexusTechnologySignature(),
            ),
          ],
        ),
      ),
    );
  }

  /// Cuánto correr flechas y puntos del carrusel para que queden en el
  /// CENTRO DE LA PANTALLA (720 en el lienzo de 1440) y no solo bajo las
  /// tarjetas (§ 8.23). Medidas de la fila del catálogo en [_buildContent]:
  /// márgenes 40, destacado 446 + 16, carrito 152 + 16.
  /// Alto de tarjetas, destacado y carrito en el catálogo (§ 8.46): terminan
  /// en y = 640, por encima de la curva de abajo del marco.
  static const double _catalogCardsHeight = 482;
  static const double _featuredWidth = 400;

  static double _carouselControlsShift({required bool hasFeatured}) {
    const canvasCenter = 1440 / 2;
    final left = 140.0 + (hasFeatured ? _featuredWidth + 16 : 0);
    const right = 1440 - 144 - 152 - 16.0;
    return canvasCenter - (left + right) / 2;
  }

  /// 07 · Sin productos.
  Widget _buildNoProducts(BuildContext context) {
    return PaymentResultWidget(
      icon: Icons.shopping_bag_outlined,
      color: AppColors.warning,
      faceGif: 'assets/images/sleep.gif',
      bubbleTitle: 'Se acabó todo…',
      bubbleSubtitle: 'Vuelve en un ratito',
      title: 'Sin productos',
      message: 'No hay productos disponibles en este momento.',
      onBack: () => context.read<HomeCubit>().showAttract(),
    );
  }

  void _showCartSyncNoticeIfNeeded(
    BuildContext context,
    HomeState state,
  ) {
    if (state.displayMode != DisplayMode.product ||
        _activePaymentCubit != null ||
        state.cartSyncRevision <= _lastCartSyncRevision ||
        state.cartSyncMessage == null) {
      return;
    }

    _lastCartSyncRevision = state.cartSyncRevision;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(state.cartSyncMessage!),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RevealIn(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2.6),
            ),
          ),
          SizedBox(height: 16),
          RevealIn(
            index: 1,
            child: Text(
              'Cargando productos...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// 06 · Error de carga.
  Widget _buildError(BuildContext context) {
    return PaymentResultWidget(
      icon: Icons.question_mark,
      color: AppColors.error,
      faceGif: 'assets/images/confused.gif',
      bubbleTitle: 'Ups, me perdí…',
      bubbleSubtitle: 'No pude cargar el menú',
      title: 'Error de carga',
      message:
          'No se pudieron cargar los productos. Revisa la conexión e inténtalo de nuevo.',
      showRetry: true,
      onRetry: () => context.read<HomeCubit>().load(),
      showBack: false,
      // Sin botón de volver: a los 10 s sin tocar, a la cara (§ 8.42).
      onAutoReturn: () => context.read<HomeCubit>().showAttract(),
    );
  }

  Future<void> _goToPayment(BuildContext context, HomeState state) async {
    if (_isPreparingPayment || _activePaymentCubit != null) return;
    if (state.cartProducts.isEmpty) return;

    _isPreparingPayment = true;
    final homeCubit = context.read<HomeCubit>();
    final previousSyncRevision = homeCubit.state.cartSyncRevision;
    homeCubit.pauseCustomerSessionTimeout();

    // Fase 8 (rendimiento): "Tu pedido" se abre YA; el menú se revisa en
    // paralelo (antes se esperaban 1-3 s de red con la pantalla quieta).
    // El cobro sigue seguro: el QR vuelve a validar precios contra la API.
    final menuRefresh = homeCubit.forcePoll();

    // Se cobra al restaurante elegido (antes: al del primer producto).
    final merchantId =
        state.selectedMerchantId ?? state.cartProducts.first.merchantId;

    final billingDetails = state.merchantUsesBilling(merchantId)
        ? await _collectBillingDetails()
        : const BillingFlowResult.withoutInvoice();
    if (!mounted) return;
    if (billingDetails == null) {
      _isPreparingPayment = false;
      homeCubit.resumeCustomerSessionTimeout();
      return;
    }

    final payment = _openPaymentPage(
      homeCubit: homeCubit,
      merchantId: merchantId,
      nit: billingDetails.nit,
      businessName: billingDetails.businessName,
    );
    unawaited(menuRefresh.then(
        (_) => _afterMenuRefresh(homeCubit, payment, previousSyncRevision)));
  }

  /// Cuando termina la revisión del menú con "Tu pedido" ya abierto:
  /// - carrito vacío (se acabó todo) → vuelve al catálogo y avisa;
  /// - carrito ajustado (precio o producto) → avisa en "Tu pedido".
  /// Si el cliente ya tocó PAGAR CON QR no se toca nada: el cubit del pago
  /// valida cada producto contra la API antes de generar el QR.
  void _afterMenuRefresh(
    HomeCubit homeCubit,
    QrPaymentCubit payment,
    int previousSyncRevision,
  ) {
    if (!mounted || _activePaymentCubit != payment) return;
    if (payment.state.status != QrPaymentStatus.initial) return;

    final refreshed = homeCubit.state;
    if (refreshed.cartProducts.isEmpty) {
      // El .then de _openPaymentPage muestra el aviso al volver.
      _popPaymentIfOpen();
      return;
    }
    if (refreshed.cartSyncRevision > previousSyncRevision &&
        refreshed.cartSyncMessage != null) {
      _lastCartSyncRevision = refreshed.cartSyncRevision;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(refreshed.cartSyncMessage!),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  /// Abre "Tu pedido + pago" y devuelve su cubit.
  QrPaymentCubit _openPaymentPage({
    required HomeCubit homeCubit,
    required int merchantId,
    String? nit,
    String? businessName,
  }) {
    _activePaymentCubit?.close();
    final cubit = sl.qrPaymentCubit();
    _activePaymentCubit = cubit;
    _isPreparingPayment = false;

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: homeCubit),
          ],
          child: QrPaymentPage(
            merchantId: merchantId,
            nit: nit,
            businessName: businessName,
            onSuccess: () {
              // No llamar cancel(): sobrescribiría success → cancelled en la UI.
              _activePaymentCubit?.stopPollingOnly();
              final cubit = _activePaymentCubit;
              _activePaymentCubit = null;
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              cubit?.close();
              if (mounted) {
                context.read<HomeCubit>().showAttract();
              }
            },
          ),
        ),
      ),
    )
        .then((_) {
      // Al salir de la página (back / pop): detener sin forzar UI cancelada.
      _activePaymentCubit?.stopPollingOnly();
      _activePaymentCubit?.close();
      _activePaymentCubit = null;
      if (!mounted) return;
      final homeCubit = context.read<HomeCubit>();
      homeCubit.resumeCustomerSessionTimeout();
      _showCartSyncNoticeIfNeeded(context, homeCubit.state);
    });
    return cubit;
  }

  /// Solo debug (F9): lleva la app real a [screen] con los datos ya cargados.
  /// No crea órdenes ni llama a endpoints nuevos (ver .claude/DEV_PANTALLAS.md).
  Future<void> _devPreview(DevScreen screen) async {
    final cubit = context.read<HomeCubit>();
    _cancelActivePayment();
    _popPaymentIfOpen();
    cubit.devRestore();
    final s = cubit.state;
    final merchantId = s.selectedMerchantId ??
        (s.merchantIds.isEmpty ? null : s.merchantIds.first);

    void notice(String text) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('DEV · $text')));

    switch (screen) {
      case DevScreen.idle:
        await cubit.showIdle();
      case DevScreen.attract:
        await cubit.showAttract();
      case DevScreen.merchantPicker:
        if (!s.hasMerchantChoice) {
          notice(
              '"Elige restaurante" necesita 2+ restaurantes en MERCHANT_IDS');
          return;
        }
        await cubit.showProduct();
        cubit.selectMerchant(null);
      case DevScreen.catalog:
        await cubit.showProduct();
        if (merchantId != null) cubit.selectMerchant(merchantId);
      case DevScreen.loading:
        cubit.devPreview(s.copyWith(
            displayMode: DisplayMode.product, status: HomeStatus.loading));
      case DevScreen.loadError:
        cubit.devPreview(s.copyWith(
            displayMode: DisplayMode.product, status: HomeStatus.error));
      case DevScreen.noProducts:
        cubit.devPreview(s.copyWith(
          displayMode: DisplayMode.product,
          status: HomeStatus.loaded,
          products: const [],
          selectedMerchantId: merchantId,
        ));
      case DevScreen.order ||
            DevScreen.qrLoading ||
            DevScreen.qrReady ||
            DevScreen.paySuccess ||
            DevScreen.payFailed ||
            DevScreen.payCancelled:
        if (merchantId == null) return;
        await cubit.showProduct();
        cubit.selectMerchant(merchantId);
        // Carrito real; si está vacío, 1 unidad del primer producto real.
        if (cubit.state.cartProducts.isEmpty) {
          final first = cubit.state.merchantProducts.firstOrNull;
          if (first == null) {
            notice('El restaurante no tiene productos');
            return;
          }
          cubit.incrementProduct(first);
        }
        final amount = cubit.state.cartTotal;
        // QR de ejemplo que ya está en assets (no sirve para pagar).
        final exampleQr = screen == DevScreen.qrReady
            ? base64Encode(
                (await rootBundle.load('assets/images/qr_example.png'))
                    .buffer
                    .asUint8List())
            : null;
        if (!mounted) return;
        final pay = _openPaymentPage(homeCubit: cubit, merchantId: merchantId);
        pay.isDevPreview = true;
        final preview = switch (screen) {
          DevScreen.qrLoading =>
            QrPaymentState(status: QrPaymentStatus.loading, amount: amount),
          DevScreen.qrReady => QrPaymentState(
              status: QrPaymentStatus.qrReady,
              amount: amount,
              qrBase64: exampleQr,
              orderId: 0,
            ),
          DevScreen.paySuccess =>
            QrPaymentState(status: QrPaymentStatus.success, amount: amount),
          DevScreen.payFailed => QrPaymentState(
              status: QrPaymentStatus.failed,
              amount: amount,
              errorMessage:
                  'El pago fue rechazado o expiró. Por favor intenta de nuevo.',
            ),
          DevScreen.payCancelled =>
            QrPaymentState(status: QrPaymentStatus.cancelled, amount: amount),
          _ => null, // 03c Tu pedido: estado inicial
        };
        if (preview != null) pay.devPreview(preview);
    }
  }

  Future<BillingFlowResult?> _collectBillingDetails() {
    return showDialog<BillingFlowResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const BillingFlowDialog(),
    );
  }
}

class _MegacenterLogo extends StatelessWidget {
  const _MegacenterLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 144,
      height: 144,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.borderLight, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'assets/images/logo_megacenter.jpg',
          fit: BoxFit.contain,
          semanticLabel: 'Logo Megacenter',
        ),
      ),
    );
  }
}

class _NexusTechnologySignature extends StatelessWidget {
  const _NexusTechnologySignature();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            'Tecnología de',
            style: TextStyle(
              color: AppColors.textCaption,
              fontSize: 11,
              letterSpacing: .4,
            ),
          ),
        ),
        SizedBox(
          width: 150,
          height: 58,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 210,
              maxWidth: 210,
              minHeight: 210,
              maxHeight: 210,
              child: Image(
                image: AssetImage(
                  'assets/images/logo_nexus_patio_tech.png',
                ),
                fit: BoxFit.contain,
                semanticLabel: 'Logo Nexus Patio Tech',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
