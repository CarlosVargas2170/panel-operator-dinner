import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/ui/themes/app_colors.dart';
import 'motion/pop.dart';
import 'motion/reveal.dart';

/// Tiempo sin tocar tras el cual una pantalla de resultado vuelve sola al
/// inicio (§ 8.42).
const kResultAutoReturn = Duration(seconds: 10);

/// Plantilla de resultado (pago exitoso / fallido / cancelado, error de carga
/// y sin productos): cara del robot a la izquierda, mensaje y botones a la
/// derecha. Lienzo de 1440×810 del diseño escalado a la pantalla.
///
/// Vuelve SOLA al inicio si nadie toca la pantalla durante
/// [autoReturnAfter] (§ 8.42); tocar en cualquier lado reinicia la cuenta.
/// Un aviso chico bajo los botones muestra los segundos que faltan.
class PaymentResultWidget extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final bool showRetry;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  /// Cara del robot (GIF de assets/images/).
  final String faceGif;

  /// Burbuja de diálogo (null = sin burbuja).
  final String? bubbleTitle;
  final String? bubbleSubtitle;

  /// Monto bajo la cara (null = no se muestra).
  final double? amount;

  /// Muestra "VOLVER AL INICIO".
  final bool showBack;

  /// Tiempo sin tocar para volver solo (null = no vuelve solo).
  final Duration? autoReturnAfter;

  /// Qué hace al volver solo (null = lo mismo que "VOLVER AL INICIO").
  final VoidCallback? onAutoReturn;

  const PaymentResultWidget({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.showRetry = false,
    this.onRetry,
    this.onBack,
    this.faceGif = 'assets/images/normal.gif',
    this.bubbleTitle,
    this.bubbleSubtitle,
    this.amount,
    this.showBack = true,
    this.autoReturnAfter = kResultAutoReturn,
    this.onAutoReturn,
  });

  @override
  State<PaymentResultWidget> createState() => _PaymentResultWidgetState();
}

class _PaymentResultWidgetState extends State<PaymentResultWidget> {
  /// Segundos que faltan para volver solo (null = no vuelve solo).
  late final ValueNotifier<int?> _left =
      ValueNotifier(widget.autoReturnAfter?.inSeconds);
  Timer? _tick;
  bool _returned = false;

  IconData get icon => widget.icon;
  Color get color => widget.color;
  String get title => widget.title;
  String get message => widget.message;
  bool get showRetry => widget.showRetry;
  VoidCallback? get onRetry => widget.onRetry;
  String get faceGif => widget.faceGif;
  String? get bubbleTitle => widget.bubbleTitle;
  String? get bubbleSubtitle => widget.bubbleSubtitle;
  double? get amount => widget.amount;
  bool get showBack => widget.showBack;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  /// (Re)arranca la cuenta: al aparecer y cada vez que alguien toca.
  void _restart() {
    final total = widget.autoReturnAfter;
    _tick?.cancel();
    if (total == null || _returned) return;
    _left.value = total.inSeconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (_left.value ?? 0) - 1;
      if (left > 0) {
        _left.value = left;
        return;
      }
      _tick?.cancel();
      if (!mounted || _returned) return;
      _returned = true;
      (widget.onAutoReturn ?? _back(context))();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cualquier toque en la pantalla reinicia la cuenta (hay alguien).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    const buttonText = TextStyle(fontSize: 24, fontWeight: FontWeight.w900);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));

    return FittedBox(
      child: SizedBox(
        width: 1440,
        height: 810,
        child: Padding(
          // Zona segura del robot (§ 8.46): la cara lejos de las esquinas de
          // la izquierda y nada en la franja de abajo que tapa el marco.
          padding: const EdgeInsets.fromLTRB(220, 120, 180, 170),
          child: Row(
            children: [
              // Fase 8: orden del revelado: cara, insignia, burbuja, título,
              // mensaje y botones.
              _buildFace(),
              const SizedBox(width: 70),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bubbleTitle != null) ...[
                      RevealIn(
                        index: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 18),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border:
                                Border.all(color: AppColors.border, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bubbleTitle!,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (bubbleSubtitle != null)
                                Text(
                                  bubbleSubtitle!,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 20),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                    RevealIn(
                      index: 3,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: TextStyle(
                            color: color,
                            fontSize: 84,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    RevealIn(
                      index: 4,
                      child: Text(
                        message,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 24),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        if (showRetry)
                          Expanded(
                            child: RevealIn(
                              index: 5,
                              child: PopPress(
                                child: SizedBox(
                                  height: 84,
                                  child: FilledButton(
                                    key: const ValueKey('result-retry-button'),
                                    onPressed: onRetry,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.brandRed,
                                      foregroundColor: AppColors.onAccent,
                                      shape: shape,
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child:
                                          Text('REINTENTAR', style: buttonText),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (showRetry && showBack) const SizedBox(width: 16),
                        if (showBack)
                          Expanded(
                            child: RevealIn(
                              index: showRetry ? 6 : 5,
                              child: PopPress(
                                child: SizedBox(
                                  height: 84,
                                  child: showRetry
                                      ? OutlinedButton(
                                          key: const ValueKey(
                                              'result-back-button'),
                                          onPressed: _back(context),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.textPrimary,
                                            side: const BorderSide(
                                                color: AppColors.accent,
                                                width: 2),
                                            shape: shape,
                                          ),
                                          child: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('VOLVER AL INICIO',
                                                style: buttonText),
                                          ),
                                        )
                                      : FilledButton(
                                          key: const ValueKey(
                                              'result-back-button'),
                                          onPressed: _back(context),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.accent,
                                            foregroundColor: AppColors.onAccent,
                                            shape: shape,
                                          ),
                                          child: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('VOLVER AL INICIO',
                                                style: buttonText),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Aviso de la vuelta automática (§ 8.42).
                    ValueListenableBuilder<int?>(
                      valueListenable: _left,
                      builder: (context, left, _) => left == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                'Vuelve al inicio en $left s',
                                key: const ValueKey('result-auto-return'),
                                style: const TextStyle(
                                    color: AppColors.textMuted, fontSize: 18),
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
  }

  VoidCallback _back(BuildContext context) =>
      widget.onBack ?? () => Navigator.of(context).pop();

  /// Recuadro oscuro con la cara, el monto e insignia de color.
  Widget _buildFace() {
    return SizedBox(
      width: 480,
      height: 520,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RevealIn(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.faceBg,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Image.asset(faceGif,
                          fit: BoxFit.contain, gaplessPlayback: true),
                    ),
                    if (amount != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Text(
                          '${amount!.toStringAsFixed(2)} Bs',
                          style: const TextStyle(
                            color: AppColors.onAccent,
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -18,
            right: -18,
            child: RevealIn(
              index: 1,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 6),
                ),
                child: Icon(icon, color: AppColors.onAccent, size: 44),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
