import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/themes/app_colors.dart';
import 'sheet_transition.dart';

/// Animación "Pop" de los botones (diseño `Robot Mesero · Pantallas`, A6).
///
/// Desde la fase 8b la entrada de los bloques es el "Revelado"
/// (`reveal.dart`); el pop queda solo en los botones:
/// - Toque: el botón se HUNDE apenas al apoyar el dedo (0,97) y al soltarlo
///   vuelve suave a su tamaño, SIN pasarse (§ 8.41). Antes rebotaba a 1,05:
///   se veía como un "levantamiento" raro. Sigue el gesto (§ 8.16).
/// - Agregar: salen 8 chispas del botón + y el número crece suave (§ 8.41).
///
/// Todas las duraciones van × [kMotionSlowdown] (1,4). Entre paréntesis, el
/// valor en la app.
abstract final class PopMotion {
  static final pressInDuration = motionMs(90); // 126 ms (hundirse)
  static final releaseDuration = motionMs(220); // 308 ms (volver)
  static final burstDuration = motionMs(480); // 672 ms
  static final countDuration = motionMs(300); // 420 ms

  /// Cuánto se hunde (poco: se nota sin parecer que se encoge).
  static const pressedScale = .97;

  /// El número que cambia arranca en este tamaño y crece a 1.
  static const countFrom = .85;
}

bool _animationsOff() => WidgetsBinding
    .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

/// Se hunde mientras se apoya el dedo y rebota con un pop al soltarlo.
/// No cambia el tamaño que ocupa ni el toque del hijo.
class PopPress extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const PopPress({super.key, this.enabled = true, required this.child});

  @override
  State<PopPress> createState() => _PopPressState();
}

class _PopPressState extends State<PopPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: PopMotion.pressInDuration);

  /// Escala desde la que arranca el rebote (donde quedó al soltar).
  double _releaseFrom = 1;
  bool _pressed = false;

  /// Al soltar: de donde quedó vuelve a 1, frenando suave (sin pasarse).
  double _releaseScale(double t) =>
      _releaseFrom + (1 - _releaseFrom) * Curves.easeOutCubic.transform(t);

  double get _scale {
    final v = _controller.value;
    return _pressed
        ? 1 + (PopMotion.pressedScale - 1) * Curves.easeOutCubic.transform(v)
        : _releaseScale(v);
  }

  void _down(PointerDownEvent _) {
    if (!widget.enabled || _animationsOff()) return;
    setState(() => _pressed = true);
    _controller
      ..duration = PopMotion.pressInDuration
      ..forward(from: 0);
  }

  void _up(PointerEvent _) {
    if (!_pressed) return;
    _releaseFrom = _scale;
    setState(() => _pressed = false);
    _controller
      ..duration = PopMotion.releaseDuration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) =>
            Transform.scale(scale: _scale, child: child),
      ),
    );
  }
}

/// Número que crece suave cada vez que sube (0,85 → 1, con un rebote
/// mínimo). Antes daba un pop fuerte (0,3 → 1,2 → 1).
class PopCount extends StatefulWidget {
  final int value;
  final Widget child;

  const PopCount({super.key, required this.value, required this.child});

  @override
  State<PopCount> createState() => _PopCountState();
}

class _PopCountState extends State<PopCount>
    with SingleTickerProviderStateMixin {
  /// Salida con un rebote mínimo (back con poco "tirón").
  static const _soft = Cubic(.34, 1.3, .64, 1);

  late final AnimationController _controller = AnimationController(
      vsync: this, duration: PopMotion.countDuration, value: 1);

  @override
  void didUpdateWidget(PopCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value > oldWidget.value && !_animationsOff()) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // Salida con rebote mínimo: se pasa ~1 % y se posa (casi no se nota).
        final k = _soft.transform(_controller.value);
        final scale = PopMotion.countFrom + (1 - PopMotion.countFrom) * k;
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

/// 8 chispas que salen del centro de [context] (el botón +) hacia afuera.
///
/// Se dibujan en el [Overlay] para que no las corte la tarjeta, y se
/// escalan igual que el lienzo de 1440×810 (`FittedBox`).
abstract final class PopBurst {
  static void show(BuildContext context, {bool onDark = false}) {
    if (_animationsOff()) return;
    final box = context.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box is! RenderBox || !box.hasSize || overlay == null) return;

    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final center =
        box.localToGlobal(box.size.center(Offset.zero), ancestor: overlayBox);
    // Escala del lienzo: cuánto mide en pantalla 1 px del diseño.
    final scale =
        (box.localToGlobal(Offset(box.size.width, 0), ancestor: overlayBox) -
                    box.localToGlobal(Offset.zero, ancestor: overlayBox))
                .dx /
            box.size.width;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Burst(
        center: center,
        scale: scale,
        colors: [
          onDark ? AppColors.onAccent : AppColors.textPrimary,
          AppColors.brandRed,
        ],
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _Burst extends StatefulWidget {
  final Offset center;
  final double scale;
  final List<Color> colors;
  final VoidCallback onDone;

  const _Burst({
    required this.center,
    required this.scale,
    required this.colors,
    required this.onDone,
  });

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: PopMotion.burstDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        })
        ..forward();
  late final CurvedAnimation _progress =
      CurvedAnimation(parent: _controller, curve: SheetMotion.easeOut);

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BurstPainter(
          progress: _progress,
          center: widget.center,
          scale: widget.scale,
          colors: widget.colors,
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final Animation<double> progress;
  final Offset center;
  final double scale;
  final List<Color> colors;

  _BurstPainter({
    required this.progress,
    required this.center,
    required this.scale,
    required this.colors,
  }) : super(repaint: progress);

  static const _count = 8;
  static const _distance = 62.0;
  static const _radius = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final paint = Paint();
    for (var i = 0; i < _count; i++) {
      final a = i / _count * math.pi * 2;
      // Las impares rojas, como el diseño.
      paint.color = colors[i.isOdd ? 1 : 0].withValues(alpha: 1 - t);
      final offset =
          center + Offset(math.cos(a), math.sin(a)) * (_distance * t * scale);
      canvas.drawCircle(offset, _radius * (1 - .7 * t) * scale, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
