import 'package:flutter/material.dart';
import '../../core/ui/themes/app_colors.dart';
import '../../presentation/bloc/qr_payment_state.dart';
import 'qr_image_widget.dart';

/// Cara trasera de la tarjeta de "Tu pedido": generando QR (14) y QR listo
/// (15a / 15b). Solo el QR (lo más grande posible) y CANCELAR; el saludo,
/// el total y la cuenta atrás van a la izquierda en [QrPaymentInfo] (§ 8.32).
class QrPaymentContent extends StatelessWidget {
  final QrPaymentState state;

  /// Segundos que faltan para habilitar "CANCELAR PAGO".
  final int secondsLeft;

  /// Spinner del recuadro blanco mientras se genera el QR.
  final Widget loadingIndicator;
  final VoidCallback? onCancel;

  const QrPaymentContent({
    super.key,
    required this.state,
    required this.secondsLeft,
    required this.loadingIndicator,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final ready = state.status == QrPaymentStatus.qrReady;
    final canCancel = ready && secondsLeft <= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.featured,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ready
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: QrImageWidget(qrBase64: state.qrBase64),
                      ),
                    )
                  : loadingIndicator,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 64,
            child: FilledButton(
              key: const ValueKey('qr-cancel-button'),
              onPressed: canCancel ? onCancel : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.textSecondary,
                disabledForegroundColor: AppColors.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                canCancel
                    ? '✕  CANCELAR PAGO'
                    : ready
                        ? 'Cancelar en $secondsLeft s'
                        : 'Cancelar pago',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que acompaña al QR, a la izquierda debajo del pedido (§ 8.32):
/// saludo ("¡Escanea y listo!"), total, cuenta atrás y "Esperando pago".
class QrPaymentInfo extends StatelessWidget {
  final QrPaymentState state;

  /// Segundos que faltan para que venza el QR.
  final int expiresIn;

  /// Total a pagar (el que validó el cubit contra la API).
  final double amount;

  const QrPaymentInfo({
    super.key,
    required this.state,
    required this.expiresIn,
    required this.amount,
  });

  static String _mmss(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ready = state.status == QrPaymentStatus.qrReady;

    const label = TextStyle(
      color: AppColors.textMuted,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    );

    return Container(
      // Más angosta en la zona segura (576 px, § 8.46): todo un poco menor.
      padding: const EdgeInsets.fromLTRB(20, 18, 22, 18),
      decoration: BoxDecoration(
        color: AppColors.featured,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/normal.gif',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ready ? '¡Escanea y listo!' : 'Un momento…',
                    style: const TextStyle(
                      color: AppColors.onAccent,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  ready ? 'Usa la app de tu banco' : 'Estoy generando tu QR',
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  ready ? '●  ●  ●   Esperando pago' : 'Verificando pedido…',
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('TOTAL', style: label),
              Text(
                '${amount.toStringAsFixed(2)} Bs',
                style: const TextStyle(
                  color: AppColors.onAccent,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('VENCE EN', style: label),
              Text(
                _mmss(expiresIn),
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  color: AppColors.onAccent,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
