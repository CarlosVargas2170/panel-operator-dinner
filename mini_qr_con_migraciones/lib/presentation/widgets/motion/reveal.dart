import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sheet_transition.dart';

/// Animación "Revelado" (diseño `Robot Mesero · Pantallas`, A8).
///
/// - Entrada: cada bloque se descubre de arriba hacia abajo, como si se
///   levantara una cortina, mientras sube 24 px. Uno tras otro.
/// - Agregar: el total del carrito cuenta hasta su nuevo valor.
///
/// Todas las duraciones van × [kMotionSlowdown] (1,4). Entre paréntesis, el
/// valor en la app.
///
/// "Revelado suave" (§ 8.16): el contenido VIAJA CON LA HOJA. Cada bloque
/// empieza a descubrirse apenas arranca la hoja (la cortina ya abierta un
/// 25 %, con fundido) y está casi completo a mitad del recorrido; el
/// escalonado entre bloques da el toque de "revelado" sin dejar la hoja
/// vacía. Medido corriendo la app: con el revelado esperando a la hoja, la
/// hoja subía crema liso y el contenido aparecía después, por partes.
abstract final class RevealMotion {
  static final duration = motionMs(450); // 630 ms (diseño 540)
  static final stagger = motionMs(40); // 56 ms (diseño 45)

  /// Máximo de pasos de escalonado: del 7.º en adelante entran a la vez que
  /// el 6.º (diseño 12) para que no haya goteo largo.
  static const maxSteps = 6;

  /// Sin espera: el contenido arranca con la hoja.
  static final startDelay = Duration.zero;

  /// Cuánto sube mientras se descubre (px del lienzo de 1440×810).
  static const rise = 12.0;

  /// La cortina arranca abierta este tanto (nunca un bloque en blanco).
  static const startOpen = .25;

  /// Parte del revelado en la que se completa el fundido.
  static const fadePortion = .45;

  static final countDuration = motionMs(520); // 728 ms
}

bool _animationsOff() => WidgetsBinding
    .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

/// Se descubre de arriba hacia abajo al aparecer por primera vez.
/// [index] es su turno en la pantalla (0 = primero). Con [enabled] en false
/// se muestra sin animar.
class RevealIn extends StatefulWidget {
  final int index;
  final bool enabled;
  final Widget child;

  /// Avance 0 → 1 manejado desde afuera (el carrusel decide cuándo se crean
  /// las tarjetas de cada página, § 8.25). Si se pasa, no usa reloj propio.
  final Animation<double>? progress;

  const RevealIn({
    super.key,
    this.index = 0,
    this.enabled = true,
    this.progress,
    required this.child,
  });

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  /// Reloj propio.
  AnimationController? _own;

  /// Avance 0 → 1 del revelado de ESTE bloque.
  late Animation<double> _t;
  bool _ready = false;

  /// Hoja o ruta que está trayendo la pantalla: el bloque espera a que
  /// termine para crearse (§ 8.25).
  Animation<double>? _gate;

  void _onGate() {
    final g = _gate;
    if (g == null || g.value < 1) return;
    g.removeListener(_onGate);
    _gate = null;
    _own?.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;

    final external = widget.progress;
    if (external != null) {
      _t = external;
      return;
    }
    if (!widget.enabled || _animationsOff()) {
      _t = kAlwaysCompleteAnimation;
      return;
    }

    final delay = RevealMotion.startDelay +
        RevealMotion.stagger * math.min(widget.index, RevealMotion.maxSteps);
    final total = delay + RevealMotion.duration;
    final own = AnimationController(vsync: this, duration: total);
    _own = own;
    // La espera va dentro de la animación (Interval) para no usar Timers.
    _t = CurvedAnimation(
      parent: own,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: SheetMotion.settle,
      ),
    );

    // Primero pasa la página (hoja de SheetSwitcher o ruta, p. ej. "Tu
    // pedido"); el bloque se crea cuando se posó (§ 8.25).
    final route = ModalRoute.of(context)?.animation;
    final gate = SheetProgress.runningOf(context) ??
        (route != null &&
                route.value < 1 &&
                route.status != AnimationStatus.reverse
            ? route
            : null);
    if (gate != null) {
      _gate = gate;
      gate.addListener(_onGate);
    } else {
      own.forward();
    }
  }

  @override
  void dispose() {
    _gate?.removeListener(_onGate);
    final t = _t;
    if (t is CurvedAnimation) t.dispose();
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary de AFUERA: el recorte y el desplazamiento que cambian
    // cada cuadro quedan en una capa propia del bloque. Sin ella, cada bloque
    // obligaba a repintar la PANTALLA ENTERA en cada cuadro.
    return RepaintBoundary(
        child: AnimatedBuilder(
      animation: _t,
      // RepaintBoundary de ADENTRO: el bloque se pinta una vez; el revelado
      // solo mueve y recorta esa imagen (sin repintar fotos y textos).
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        // Al volver la hoja (reversa) el bloque ya quedó revelado.
        final t = _t.value.clamp(0.0, 1.0);
        // Diseño: clip-path inset(0 0 100% 0) → inset(0) + translateY → 0,
        // más un fundido que suaviza el borde del corte.
        // Mismo árbol al terminar (sin recorte) para no perder el estado.
        // Velo del color de fondo que se aclara (en vez de `Opacity`: la
        // transparencia obligaba a dibujar cada bloque en una capa aparte y
        // daba picos al empezar, medido corriendo la app, § 8.16).
        final double veil = 1 - math.min(1.0, t / RevealMotion.fadePortion);
        return Transform.translate(
          offset: Offset(0, RevealMotion.rise * (1 - t)),
          child: ClipRect(
            clipper: _TopDown(
                RevealMotion.startOpen + (1 - RevealMotion.startOpen) * t),
            clipBehavior: t >= 1 ? Clip.none : Clip.hardEdge,
            child: Stack(
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: veil),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ));
  }
}

/// Entrada SUAVE de las tarjetas del catálogo (§ 8.39): el bloque sube un
/// poco y se "enciende" (un velo del color de fondo que se aclara), sin
/// cortina que lo recorte a medias. Arranca cuando la hoja que trae la
/// pantalla va por [startAt] de su tiempo (no al final): las tarjetas se
/// arman mientras la hoja se posa, sin quedarse mirando una hoja vacía.
///
/// Antes (§ 8.25) cada tarjeta esperaba a que la hoja TERMINARA y entraba
/// con cortina: ~1,3 s de hoja vacía y tarjetas cortadas a la mitad.
abstract final class SoftEntryMotion {
  static final duration = motionMs(400); // 560 ms
  static final stagger = motionMs(35); // 49 ms
  static const maxSteps = 6;
  static const rise = 18.0;

  /// Punto del tiempo de la hoja en que arrancan (0,6 ≈ 74 % del recorrido
  /// con `easeInOutCubic`: la hoja ya está casi arriba).
  static const startAt = .6;
}

class SoftEntry extends StatefulWidget {
  final int index;
  final bool enabled;
  final Widget child;

  const SoftEntry({
    super.key,
    this.index = 0,
    this.enabled = true,
    required this.child,
  });

  @override
  State<SoftEntry> createState() => _SoftEntryState();
}

class _SoftEntryState extends State<SoftEntry>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;
  Animation<double> _t = kAlwaysCompleteAnimation;
  Animation<double>? _gate;
  bool _ready = false;

  void _onGate() {
    final g = _gate;
    if (g == null || g.value < SoftEntryMotion.startAt) return;
    g.removeListener(_onGate);
    _gate = null;
    _own?.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    if (!widget.enabled || _animationsOff()) return;

    final delay = SoftEntryMotion.stagger *
        math.min(widget.index, SoftEntryMotion.maxSteps);
    final total = delay + SoftEntryMotion.duration;
    final own = AnimationController(vsync: this, duration: total);
    _own = own;
    _t = CurvedAnimation(
      parent: own,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1,
          curve: SheetMotion.settle),
    );
    final gate = SheetProgress.runningOf(context);
    if (gate != null && gate.value < SoftEntryMotion.startAt) {
      _gate = gate;
      gate.addListener(_onGate);
    } else {
      own.forward();
    }
  }

  @override
  void dispose() {
    _gate?.removeListener(_onGate);
    final t = _t;
    if (t is CurvedAnimation) t.dispose();
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    // RepaintBoundary de afuera: lo que cambia cada cuadro queda en su capa;
    // el de adentro: el bloque se pinta una vez y solo se mueve/cubre.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _t,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final t = _t.value.clamp(0.0, 1.0);
          // Mismo árbol al terminar (velo transparente) para no perder estado.
          return Transform.translate(
            offset: Offset(0, SoftEntryMotion.rise * (1 - t)),
            child: Stack(
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: bg.withValues(alpha: 1 - t)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Deja ver solo la parte de arriba del bloque: [visible] de su alto.
class _TopDown extends CustomClipper<Rect> {
  final double visible;
  const _TopDown(this.visible);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height * visible);

  @override
  bool shouldReclip(_TopDown old) => old.visible != visible;
}

/// Texto de un monto que "cuenta" desde el valor anterior hasta el nuevo
/// cada vez que cambia (diseño: `countUp`, salida cúbica).
class CountUpText extends StatefulWidget {
  final double value;
  final String Function(double value) format;
  final TextStyle? style;

  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: RevealMotion.countDuration, value: 1);
  late double _from = widget.value;

  @override
  void didUpdateWidget(CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    // Si cambia a mitad de la cuenta, sigue desde lo que se ve ahora.
    _from = _shown(oldWidget.value);
    if (_animationsOff()) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  double _shown(double to) {
    final p = _controller.value;
    final e = 1 - math.pow(1 - p, 3); // 1 − (1 − p)³, como el diseño
    return _from + (to - _from) * e;
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
      builder: (context, _) =>
          Text(widget.format(_shown(widget.value)), style: widget.style),
    );
  }
}
