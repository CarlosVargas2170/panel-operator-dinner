import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import '../../domain/entities/product.dart';
import 'app_image.dart';
import 'motion/reveal.dart';
import 'product_quantity_selector.dart';

/// Lista de "Tu pedido": foto, nombre, precio c/u, − cantidad + y subtotal.
class OrderLines extends StatelessWidget {
  final List<Product> products;
  final int Function(Product product) quantityFor;
  final int maxQuantity;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onRemove;

  /// Turno de la primera fila en el revelado de entrada (fase 8).
  final int revealIndex;

  /// Filas que caben a la vista: solo ellas se revelan (las de más abajo
  /// aparecen al desplazar y no deben "saltar").
  static const _visibleRows = 7;

  const OrderLines({
    super.key,
    required this.products,
    required this.quantityFor,
    required this.maxQuantity,
    required this.onAdd,
    required this.onRemove,
    this.revealIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.surfaceAlt,
      child: Center(child: Icon(Icons.fastfood, color: AppColors.textMuted)),
    );

    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.border, height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        final quantity = quantityFor(product);
        return RevealIn(
          index: revealIndex + index,
          enabled: index < _visibleRows,
          child: SizedBox(
            height: 86,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: product.urlImage.isEmpty
                        ? placeholder
                        : AppImage(
                            imageUrl: product.urlImage,
                            errorWidget: placeholder,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${product.price.toStringAsFixed(2)} Bs c/u',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                ProductQuantitySelector(
                  quantity: quantity,
                  maxQuantity: maxQuantity,
                  onIncrement: () => onAdd(product),
                  onDecrement: () => onRemove(product),
                  size: 48,
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    '${(product.price * quantity).toStringAsFixed(2)} Bs',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
