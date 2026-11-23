import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import 'motion/pop.dart';

class ProductQuantitySelector extends StatelessWidget {
  final int quantity;
  final int maxQuantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Tamaño de los botones redondos.
  final double size;

  /// true = botones blancos (sobre la tarjeta oscura del destacado).
  final bool onDark;

  const ProductQuantitySelector({
    super.key,
    required this.quantity,
    required this.maxQuantity,
    required this.onIncrement,
    required this.onDecrement,
    this.size = 52,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuantityButton(
          icon: Icons.remove,
          size: size,
          onDark: onDark,
          onPressed: quantity > 0 ? onDecrement : null,
        ),
        Container(
          constraints: BoxConstraints(minWidth: size * 0.75),
          alignment: Alignment.center,
          // Fase 8: el número da un "pop" cada vez que sube.
          child: PopCount(
            value: quantity,
            child: Text(
              '$quantity',
              style: TextStyle(
                color: onDark ? AppColors.onAccent : AppColors.textPrimary,
                fontSize: size * 0.45,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        _QuantityButton(
          icon: Icons.add,
          size: size,
          onDark: onDark,
          burst: true,
          onPressed: quantity < maxQuantity ? onIncrement : null,
        ),
      ],
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool onDark;
  final VoidCallback? onPressed;

  /// true = al tocarlo salen chispas (el botón +).
  final bool burst;

  const _QuantityButton({
    required this.icon,
    required this.size,
    required this.onDark,
    this.onPressed,
    this.burst = false,
  });

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    return PopPress(
      enabled: onPressed != null,
      child: Builder(
        builder: (context) => IconButton.filled(
          onPressed: onPressed == null
              ? null
              : () {
                  if (burst) PopBurst.show(context, onDark: onDark);
                  onPressed();
                },
          icon: Icon(icon, size: size * 0.5),
          style: IconButton.styleFrom(
            backgroundColor: onDark ? AppColors.surface : AppColors.accent,
            foregroundColor: onDark ? AppColors.accent : AppColors.onAccent,
            disabledBackgroundColor:
                onDark ? AppColors.textSecondary : AppColors.border,
            disabledForegroundColor: AppColors.textMuted,
            fixedSize: Size(size, size),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
