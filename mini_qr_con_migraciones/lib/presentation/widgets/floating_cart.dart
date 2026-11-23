import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import 'motion/pop.dart';
import 'motion/reveal.dart';
import '../../domain/entities/product.dart';
import 'app_image.dart';

/// Columna fija del carrito (derecha del catálogo).
/// Tocarla o tocar PAGAR abre "Tu pedido".
class FloatingCart extends StatelessWidget {
  final List<Product> products;
  final int Function(Product product) quantityFor;
  final int totalItems;
  final double totalAmount;
  final VoidCallback onPay;

  /// Máximo de miniaturas; si hay más, la última dice "+N".
  static const maxThumbs = 8;

  const FloatingCart({
    super.key,
    required this.products,
    required this.quantityFor,
    required this.totalItems,
    required this.totalAmount,
    required this.onPay,
    this.height = 600,
  });

  /// Alto del carrito (zona segura del robot, § 8.46: 482).
  final double height;

  @override
  Widget build(BuildContext context) {
    final isEmpty = totalItems == 0;

    return GestureDetector(
      onTap: isEmpty ? null : onPay,
      child: Container(
        width: 152,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              height: 92,
              color: AppColors.accent,
              alignment: Alignment.center,
              child: Badge(
                key: const ValueKey('cart-count'),
                isLabelVisible: !isEmpty,
                label: Text('$totalItems'),
                backgroundColor: AppColors.brandRed,
                child: const Icon(Icons.shopping_cart,
                    color: AppColors.onAccent, size: 40),
              ),
            ),
            Expanded(
              child: isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Toca + para agregar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 16),
                        ),
                      ),
                    )
                  : _buildThumbs(),
            ),
            const Text(
              'TOTAL',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // Fase 8 (revelado): el total cuenta hasta su nuevo valor.
                child: CountUpText(
                  value: totalAmount,
                  format: (v) => '${v.toStringAsFixed(2)} Bs',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: PopPress(
                  enabled: !isEmpty,
                  child: FilledButton(
                    key: const ValueKey('cart-pay-button'),
                    onPressed: isEmpty ? null : onPay,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandRed,
                      foregroundColor: AppColors.onAccent,
                      disabledBackgroundColor: AppColors.border,
                      disabledForegroundColor: AppColors.textMuted,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'PAGAR',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbs() {
    final overflow = products.length > maxThumbs;
    final shown = overflow ? products.take(maxThumbs - 1).toList() : products;
    final twoColumns = products.length > 3;

    return GridView.count(
      crossAxisCount: twoColumns ? 2 : 1,
      childAspectRatio: twoColumns ? 1 : 1.2,
      padding: const EdgeInsets.all(10),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final product in shown)
          _Thumb(product: product, quantity: quantityFor(product)),
        if (overflow) _MoreTile(count: products.length - shown.length),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final Product product;
  final int quantity;

  const _Thumb({required this.product, required this.quantity});

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.surfaceAlt,
      child: Center(child: Icon(Icons.fastfood, color: AppColors.textMuted)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: product.urlImage.isEmpty
              ? placeholder
              : AppImage(imageUrl: product.urlImage, errorWidget: placeholder),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: AppColors.onAccent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  final int count;

  const _MoreTile({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '+$count',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
