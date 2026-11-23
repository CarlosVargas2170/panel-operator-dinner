import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import 'motion/pop.dart';
import 'motion/reveal.dart';
import '../../domain/entities/merchant.dart';
import 'app_image.dart';

/// Pantalla 03 "Elige restaurante": un círculo por comercio.
///
/// Se dibuja en un lienzo de 1440×810 (medidas del diseño) y se escala
/// a la pantalla con [FittedBox].
class MerchantPicker extends StatelessWidget {
  final List<Merchant> merchants;
  final ValueChanged<int> onSelect;
  final Widget logo;

  const MerchantPicker({
    super.key,
    required this.merchants,
    required this.onSelect,
    required this.logo,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        width: 1440,
        height: 810,
        child: Column(
          children: [
            // Zona segura del robot (§ 8.46): más abajo, más compacto y la
            // fila de restaurantes lejos de las curvas de los costados.
            const SizedBox(height: 52),
            // Fase 8: orden del revelado: marca, pregunta, cada restaurante, aviso.
            RevealIn(
              child: Column(
                children: [
                  SizedBox(
                      width: 88, height: 88, child: FittedBox(child: logo)),
                  const SizedBox(height: 10),
                  const Text(
                    'BIENVENIDO A',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                  const Text(
                    'MEGACENTER',
                    style: TextStyle(
                      color: AppColors.brandRed,
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const RevealIn(
              index: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dash(),
                  SizedBox(width: 16),
                  Text(
                    '¿QUÉ SE TE ANTOJA HOY?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(width: 16),
                  _Dash(),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 1180,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, m) in merchants.indexed) ...[
                      RevealIn(
                        index: 2 + i,
                        child: PopPress(
                          child: _MerchantCircle(
                              merchant: m, onTap: () => onSelect(m.id)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            RevealIn(
              index: 2 + merchants.length,
              child: const Text(
                'TOCA UN RESTAURANTE PARA VER SU MENÚ',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ),
            // El marco tapa ~55 px abajo: el aviso queda en y ≈ 660.
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) =>
      Container(width: 48, height: 3, color: AppColors.textPrimary);
}

const double _circleSize = 180;

/// Ancho de cada restaurante (círculo + aire para el nombre): todos iguales
/// para que la fila quede pareja (§ 8.46).
const double _itemWidth = 240;

TextStyle _nameStyle(Color color) => TextStyle(
      color: color,
      fontSize: 24,
      fontWeight: FontWeight.w900,
    );

class _MerchantCircle extends StatelessWidget {
  final Merchant merchant;
  final VoidCallback onTap;

  const _MerchantCircle({required this.merchant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        merchant.name.isEmpty ? '?' : merchant.name[0].toUpperCase(),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 96,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    final logoUrl = merchant.urlLogo;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _itemWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _circleSize,
              height: _circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.accent, width: 6),
              ),
              child: ClipOval(
                child: logoUrl == null || logoUrl.isEmpty
                    ? initial
                    : AppImage(imageUrl: logoUrl, errorWidget: initial),
              ),
            ),
            const SizedBox(height: 14),
            // Nombre largo: se achica para entrar en el ancho del restaurante.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                merchant.name.toUpperCase(),
                style: _nameStyle(AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
