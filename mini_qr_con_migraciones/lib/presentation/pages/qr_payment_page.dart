import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_settings.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/payment_counter.dart';
import '../../core/services/payment_polling_status.dart';
import '../../core/ui/themes/app_colors.dart';
import '../../presentation/bloc/home_cubit.dart';
import '../../presentation/bloc/home_state.dart';
import '../../presentation/bloc/qr_payment_cubit.dart';
import '../../presentation/bloc/qr_payment_state.dart';
import '../widgets/flip_card.dart';
import '../widgets/motion/pop.dart';
import '../widgets/motion/reveal.dart';
import '../widgets/motion/sheet_transition.dart';
import '../widgets/order_lines.dart';
import '../widgets/payment_result.dart';
import '../widgets/qr_payment_content.dart';

class QrPaymentPage extends StatefulWidget {
  final int merchantId;
  final String? customerName;
  final String phoneNumber;
  final String whereEat;
  final String? nit;
  final String? businessName;
  final String? paymentReferenceOverride;
  final VoidCallback? onSuccess;

  const QrPaymentPage({
    super.key,
    required this.merchantId,
    this.customerName,
    this.phoneNumber = '',
    this.whereEat = 'dineIn',
    this.nit,
    this.businessName,
    this.paymentReferenceOverride,
    this.onSuccess,
  });

  @override
  State<QrPaymentPage> createState() => _QrPaymentPageState();
}

class _QrPaymentPageState extends State<QrPaymentPage> {
  static const _cancelDelay = 7;
  static const _successReturnDelay = Duration(seconds: 5);
  int _secondsLeft = _cancelDelay;
  Timer? _countdownTimer;

  /// Segundos para que venza el QR (QR_EXPIRATION_MINUTES × 60).
  Timer? _expiryTimer;
  int _expiresIn = AppSettings.qrExpirationMinutes * 60;

  /// Bloqueo local: una vez éxito, la UI no vuelve a cancelado/fallido.
  bool _paymentSucceeded = false;

  /// Snapshot del carrito: se toma al tocar PAGAR CON QR.
  List<Map<String, dynamic>> _cartItems = const [];
  Map<String, dynamic>? _menuData;
  double _amount = 0;

  /// Toma el carrito en este momento y arranca el pago (mismo startQrPayment).
  void _startPayment() {
    final home = context.read<HomeCubit>().state;
    final products = List.of(home.cartProducts);
    if (products.isEmpty) return;

    _cartItems = products
        .map<Map<String, dynamic>>((product) => {
              'id': product.id,
              'name': product.name,
              'quantity': home.quantityFor(product),
              'price': product.price,
            })
        .toList(growable: false);
    _menuData = {
      'merchantName': home.getMerchantNameForProduct(products.first),
      'categories': [
        {
          'products': products
              .map<Map<String, dynamic>>((product) => {
                    'id': product.id,
                    'name': product.name,
                    'price': product.price,
                    'urlImage': product.urlImage,
                    'description': product.description,
                  })
              .toList(growable: false),
        },
      ],
    };
    _amount = home.cartTotal;

    final cubit = context.read<QrPaymentCubit>();
    // Vista previa (F9): no crear órdenes reales.
    if (cubit.isDevPreview) {
      cubit.devPreview(
          QrPaymentState(status: QrPaymentStatus.loading, amount: _amount));
      return;
    }
    cubit.startQrPayment(
      merchantId: widget.merchantId,
      productId: products.first.id,
      amount: _amount,
      customerName: widget.customerName ?? AppSettings.customerName,
      phoneNumber: widget.phoneNumber,
      whereEat: widget.whereEat,
      cartItems: _cartItems,
      menuData: _menuData,
      nit: widget.nit,
      businessName: widget.businessName,
      paymentReferenceOverride: widget.paymentReferenceOverride,
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsLeft = _cancelDelay;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _startExpiry() {
    _expiryTimer?.cancel();
    _expiresIn = AppSettings.qrExpirationMinutes * 60;
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_expiresIn <= 1) {
        timer.cancel();
        setState(() => _expiresIn = 0);
        context.read<QrPaymentCubit>().expire(); // → 17 Pago fallido
        return;
      }
      setState(() => _expiresIn--);
    });
  }

  /// VOLVER AL INICIO: cierra el pago, vacía el carrito y vuelve a la cara
  /// del robot (lo hace `onSuccess` de home_page).
  void _goHome() {
    if (widget.onSuccess != null) {
      widget.onSuccess!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _expiryTimer?.cancel();
    PaymentPollingStatus().setIdle();
    // Solo detener polling: NO emitir cancelled (evita flash de UI cancelada
    // después del éxito al hacer pop / dispose).
    try {
      context.read<QrPaymentCubit>().stopPollingOnly();
    } catch (_) {
      // Cubit ya cerrado o no disponible en el árbol.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocConsumer<QrPaymentCubit, QrPaymentState>(
          listener: (context, state) {
            _publishToRemoteControl(state);

            // Cancelar (7 s) y vencimiento cuentan solo mientras se ve el QR.
            if (state.status == QrPaymentStatus.qrReady) {
              if (_expiryTimer == null) {
                _startCountdown();
                _startExpiry();
              }
            } else {
              _expiryTimer?.cancel();
              _expiryTimer = null;
            }

            if (state.status == QrPaymentStatus.success) {
              if (_paymentSucceeded) return;
              _paymentSucceeded = true;
              AudioService.playThanks();
              // Vista previa (F9): no suma al contador de pagos.
              if (!context.read<QrPaymentCubit>().isDevPreview) {
                PaymentCounter().increment(
                  amount: state.amount ?? _amount,
                  productId: _productId ?? 0,
                  productName: _productName,
                  merchantId: widget.merchantId,
                  cartItems: _cartItems,
                );
              }
              // La vuelta automática la hace la pantalla de éxito (§ 8.42).
            }
          },
          builder: (context, state) {
            // Fase 8: el paso a un resultado sube como una hoja; REINTENTAR
            // la baja de vuelta a "Tu pedido".
            final screen = _PayScreen.of(state, succeeded: _paymentSucceeded);
            return SheetSwitcher(
              screen: screen,
              order: screen.index,
              background: AppColors.background,
              child: _buildScreen(context, state),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, QrPaymentState state) {
    // Prioridad absoluta al éxito: no dejar que cancelled pise la UI.
    if (_paymentSucceeded || state.status == QrPaymentStatus.success) {
      return _buildSuccess(state);
    }

    return switch (state.status) {
      QrPaymentStatus.initial ||
      QrPaymentStatus.loading ||
      QrPaymentStatus.qrReady =>
        _buildOrder(context, state),
      QrPaymentStatus.success => _buildSuccess(state),
      QrPaymentStatus.failed => PaymentResultWidget(
          icon: Icons.priority_high,
          color: AppColors.error,
          faceGif: 'assets/images/cry.gif',
          bubbleTitle: 'Uy, no pasó…',
          bubbleSubtitle: 'Probemos otra vez',
          title: 'Pago fallido',
          message: state.errorMessage ?? 'El pago fue rechazado o expiró.',
          amount: state.amount ?? _amount,
          showRetry: true,
          onRetry: _startPayment,
          onBack: _goHome,
        ),
      QrPaymentStatus.cancelled => PaymentResultWidget(
          icon: Icons.close,
          color: AppColors.cancelled,
          faceGif: 'assets/images/sad.gif',
          bubbleTitle: 'Está bien',
          bubbleSubtitle: 'Cuando quieras, aquí estoy',
          title: 'Pago cancelado',
          message: 'Cancelaste el pago.',
          amount: state.amount ?? _amount,
          onBack: _goHome,
        ),
    };
  }

  /// 16 · Pago exitoso.
  Widget _buildSuccess(QrPaymentState state) {
    return PaymentResultWidget(
      icon: Icons.check,
      color: AppColors.success,
      faceGif: 'assets/images/happy.gif',
      bubbleTitle: '¡Gracias!',
      bubbleSubtitle: 'Pago recibido',
      title: 'Pago exitoso',
      message: 'Tu pedido ha sido confirmado. En un momento te lo traigo.',
      amount: state.amount ?? _amount,
      onBack: _goHome,
      // El éxito vuelve antes que los demás (5 s), como siempre.
      autoReturnAfter: _successReturnDelay,
    );
  }

  /// 03c "Tu pedido": lista con − / + y tarjeta oscura con el total.
  Widget _buildOrder(BuildContext context, QrPaymentState pay) {
    final homeCubit = context.read<HomeCubit>();
    // Al pagar, la tarjeta gira y la lista queda bloqueada.
    final flipped = pay.status != QrPaymentStatus.initial;

    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, home) {
        return FittedBox(
          child: SizedBox(
            width: 1440,
            height: 810,
            child: Padding(
              // Zona segura del robot (§ 8.46): nada en las esquinas ni en
              // la franja de abajo que tapa el marco.
              padding: const EdgeInsets.fromLTRB(160, 68, 184, 150),
              child: Column(
                children: [
                  SizedBox(
                    height: 68,
                    child: RevealIn(
                      // Lejos de las esquinas de arriba (§ 8.46): logo en
                      // x = 250 y SEGUIR COMPRANDO termina en x = 1190.
                      child: Padding(
                        padding: const EdgeInsets.only(left: 90, right: 66),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.asset(
                                'assets/images/logo_megacenter.jpg',
                                width: 64,
                                height: 64,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 20),
                            const Text(
                              'TU PEDIDO',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            if (!flipped)
                              SizedBox(
                                height: 60,
                                child: PopPress(
                                  child: OutlinedButton(
                                    key: const ValueKey('order-back-button'),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textPrimary,
                                      side: const BorderSide(
                                          color: AppColors.accent, width: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 28),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text(
                                      '← SEGUIR COMPRANDO',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          // Al pagar: el pedido (atenuado) y debajo el
                          // saludo, total y cuenta atrás; así el QR de la
                          // derecha queda grande (§ 8.32).
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: IgnorePointer(
                                  ignoring: flipped,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 300),
                                    opacity: flipped ? 0.35 : 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(28),
                                        border:
                                            Border.all(color: AppColors.border),
                                      ),
                                      child: OrderLines(
                                        products: home.cartProducts,
                                        quantityFor: home.quantityFor,
                                        maxQuantity:
                                            AppSettings().maxCartItemQuantity,
                                        onAdd: homeCubit.incrementProduct,
                                        revealIndex: 1,
                                        onRemove: (product) {
                                          homeCubit.decrementProduct(product);
                                          // Sin productos → de vuelta al catálogo.
                                          if (homeCubit.state.cartTotalItems ==
                                              0) {
                                            Navigator.of(context).pop();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (flipped) ...[
                                const SizedBox(height: 20),
                                RevealIn(
                                  child: QrPaymentInfo(
                                    state: pay,
                                    expiresIn: _expiresIn,
                                    amount: pay.amount ?? _amount,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 496,
                          child: RevealIn(
                            // Después de la cabecera y las filas visibles.
                            index: 1 + home.cartProducts.length,
                            child: FlipCard(
                              flipped: flipped,
                              front: _buildSummary(home),
                              back: QrPaymentContent(
                                state: pay,
                                secondsLeft: _secondsLeft,
                                loadingIndicator: _buildLoading(),
                                onCancel: context.read<QrPaymentCubit>().cancel,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tarjeta oscura de la derecha: total y PAGAR CON QR.
  Widget _buildSummary(HomeState home) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.featured,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'RESUMEN',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${home.cartTotalItems} productos',
            style: const TextStyle(
              color: AppColors.onAccent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${home.cartTotal.toStringAsFixed(2)} Bs',
              style: const TextStyle(
                color: AppColors.onAccent,
                fontSize: 60,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.textSecondary, width: 2),
            ),
            child: const Row(
              children: [
                Icon(Icons.qr_code_2, color: AppColors.onAccent, size: 36),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pago con QR',
                      style: TextStyle(
                        color: AppColors.onAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Con la app de tu banco',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 100,
            child: PopPress(
              child: FilledButton(
                key: const ValueKey('order-pay-button'),
                onPressed: _startPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandRed,
                  foregroundColor: AppColors.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'PAGAR CON QR',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.accent, strokeWidth: 3),
          SizedBox(height: 24),
          Text(
            'Generando QR…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Remote-control: publica estado al singleton global
  // ─────────────────────────────────────────────────────────────
  /// Nombre resumido de la compra para el estado remoto.
  String get _productName {
    if (_cartItems.isEmpty) return '';
    if (_cartItems.length == 1) {
      return (_cartItems.first['name'] as String?) ?? '';
    }
    return 'Pedido (${_cartItems.length} productos)';
  }

  /// ID del producto desde menuData (primer producto de la primera categoria).
  int? get _productId {
    final menuData = _menuData;
    if (menuData == null) return null;
    final categories = menuData['categories'] as List?;
    if (categories == null || categories.isEmpty) return null;
    final firstCategory = categories.first as Map?;
    if (firstCategory == null) return null;
    final products = firstCategory['products'] as List?;
    if (products == null || products.isEmpty) return null;
    final firstProduct = products.first as Map?;
    return firstProduct?['id'] as int?;
  }

  /// Sincroniza el estado del cubit con [PaymentPollingStatus]
  /// para que el remote-control refleje el progreso del pago.
  void _publishToRemoteControl(QrPaymentState state) {
    // Vista previa (F9): no se publica al panel remoto.
    if (context.read<QrPaymentCubit>().isDevPreview) return;
    final pub = PaymentPollingStatus();

    switch (state.status) {
      case QrPaymentStatus.initial:
      case QrPaymentStatus.loading:
        pub.setWaiting(
          productId: _productId ?? 0,
          merchantId: widget.merchantId,
          orderId: state.orderId,
          amount: state.amount ?? _amount,
          productName: _productName,
        );
      case QrPaymentStatus.qrReady:
        if (state.isPolling) {
          pub.setPolling(
            productId: _productId ?? 0,
            merchantId: widget.merchantId,
            orderId: state.orderId!,
            amount: state.amount ?? _amount,
            productName: _productName,
          );
        } else {
          pub.setWaiting(
            productId: _productId ?? 0,
            merchantId: widget.merchantId,
            orderId: state.orderId,
            amount: state.amount ?? _amount,
            productName: _productName,
          );
        }
      case QrPaymentStatus.success:
        pub.setSuccess(
          productId: _productId,
          merchantId: widget.merchantId,
          orderId: state.orderId,
          amount: state.amount ?? _amount,
          productName: _productName,
        );
      case QrPaymentStatus.failed:
        pub.setFailed(
          productId: _productId,
          merchantId: widget.merchantId,
          orderId: state.orderId,
        );
      case QrPaymentStatus.cancelled:
        pub.setIdle();
    }
  }
}

/// Pantallas de "Tu pedido + pago", en el orden del diseño (03c → 18).
enum _PayScreen {
  order,
  success,
  failed,
  cancelled;

  static _PayScreen of(QrPaymentState state, {required bool succeeded}) {
    if (succeeded || state.status == QrPaymentStatus.success) return success;
    return switch (state.status) {
      QrPaymentStatus.initial ||
      QrPaymentStatus.loading ||
      QrPaymentStatus.qrReady =>
        order,
      QrPaymentStatus.success => success,
      QrPaymentStatus.failed => failed,
      QrPaymentStatus.cancelled => cancelled,
    };
  }
}
