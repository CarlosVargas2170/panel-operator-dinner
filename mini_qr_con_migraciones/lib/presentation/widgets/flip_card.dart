import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tarjeta que gira como una carta (eje Y) entre [front] y [back].
class FlipCard extends StatelessWidget {
  final Widget front;
  final Widget back;
  final bool flipped;

  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.flipped,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: flipped ? math.pi : 0),
      // Fase 8 (§ 8.16): misma familia de curvas que el resto.
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      builder: (context, angle, _) {
        final showBack = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspectiva
            ..rotateY(angle),
          child: showBack
              // La cara trasera se espeja para que no se lea al revés.
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: back,
                )
              : front,
        );
      },
    );
  }
}
