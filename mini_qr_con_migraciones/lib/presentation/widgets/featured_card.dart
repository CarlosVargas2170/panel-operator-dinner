import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import '../../domain/entities/product.dart';
import 'adaptive_product_image.dart';
import 'product_quantity_selector.dart';

/// Tarjeta grande oscura del producto destacado (izquierda del catálogo).
class FeaturedCard extends StatelessWidget {
  final Product product;
  final int quantity;
  final int maxQuantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// Tamaño de la tarjeta (zona segura del robot, § 8.46: 400 × 482).
  final double width;
  final double height;

  const FeaturedCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.maxQuantity,
    required this.onAdd,
    required this.onRemove,
    this.width = 446,
    this.height = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppColors.featured,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // La foto ocupa la mitad del alto (300 de 600 en el original).
            height: height / 2,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (product.urlImage.isEmpty)
                    const ColoredBox(color: AppColors.textSecondary)
                  else
                    AdaptiveProductImage(imageUrl: product.urlImage),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'DESTACADO',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            product.name.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.onAccent,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${product.price.toStringAsFixed(2)} Bs',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ProductQuantitySelector(
                quantity: quantity,
                maxQuantity: maxQuantity,
                onIncrement: onAdd,
                onDecrement: onRemove,
                size: 64,
                onDark: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
