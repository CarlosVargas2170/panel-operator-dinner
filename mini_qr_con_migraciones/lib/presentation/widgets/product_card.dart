import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import '../../domain/entities/product.dart';
import 'adaptive_product_image.dart';
import 'product_quantity_selector.dart';

/// Tarjeta de la cuadrícula del catálogo: nombre, precio y − / + a la
/// izquierda; foto a la derecha.
class ProductCard extends StatelessWidget {
  final Product product;
  final int quantity;
  final int maxQuantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const ProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.maxQuantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 3 : 1,
        ),
      ),
      // Se adapta al ancho (§ 8.47): normal, precio y − / + en la fila de
      // abajo; angosta (p. ej. con destacado, ~270 px), versión compacta con
      // foto más chica, precio arriba y botones abajo.
      child: LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth - c.maxHeight - 24 < _rowMinWidth;
        final photo =
            compact ? math.min(c.maxHeight, c.maxWidth * .36) : c.maxHeight;
        final price = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              _Badge(
                label: '${product.price.toStringAsFixed(2)} Bs',
                color: AppColors.accent,
              ),
              if (product.oldPrice != null) ...[
                const SizedBox(width: 6),
                const _Badge(label: 'Oferta', color: AppColors.brandRed),
              ],
            ],
          ),
        );
        final selector = ProductQuantitySelector(
          quantity: quantity,
          maxQuantity: maxQuantity,
          onIncrement: onAdd,
          onDecrement: onRemove,
          size: compact ? 38 : 44,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                    : const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre con su alto completo (1 o 2 líneas) arriba. Con
                    // las tarjetas más bajas de la zona segura, precio y
                    // botones uno debajo del otro ya no entraban.
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: compact ? 17 : 20,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(height: 4),
                      SizedBox(height: 26, child: price),
                    ],
                    const Spacer(),
                    if (compact)
                      selector
                    else
                      Row(
                        children: [
                          // Se achica si no entra al lado de los botones.
                          Flexible(child: price),
                          const SizedBox(width: 12),
                          selector,
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // Foto cuadrada del alto de la tarjeta (en la compacta, algo
            // menor): las fotos de producto se ven completas, sin recortes.
            SizedBox(
              width: photo,
              child: product.urlImage.isEmpty
                  ? const _Placeholder()
                  : AdaptiveProductImage(
                      imageUrl: product.urlImage,
                      errorWidget: const _Placeholder(),
                    ),
            ),
          ],
        );
      }),
    );
  }
}

/// Ancho mínimo del texto para poner precio y − / + en la misma fila.
const double _rowMinWidth = 230;

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceAlt,
      child: Center(
        child: Icon(Icons.fastfood, color: AppColors.textMuted, size: 48),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: const TextStyle(
            color: AppColors.onAccent,
            fontWeight: FontWeight.bold,
            fontSize: 14),
      ),
    );
  }
}
