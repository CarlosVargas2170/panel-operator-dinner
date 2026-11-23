import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Transiciones entre pantallas (fase 8).
///
/// - **Hoja que sube** (diseño `Robot Mesero · Pantallas`, T4): en todos los
///   cambios de pantalla (§ 8.31). Avanzar: la nueva sube desde abajo (esquinas de
///   arriba 32 → 0) y la anterior se aleja un poco al fondo. Volver: lo mismo
///   en espejo, la anterior baja desde arriba. Misma duración y curva.
/// - **Fundido**: disponible con [SheetSwitcher.pages], hoy sin uso.
///
/// Todo usa el mismo lenguaje: curvas "enfatizadas" (arrancan suave, se
/// posan largo) y duraciones de la misma familia (§ 8.16).

/// Velocidad de todo el movimiento de la fase 8 (hoja, fundido, revelado y
/// pop). El diseño trae Rápida × 0,7 · Normal × 1 · Lenta × 1,9. Para cambiar
/// la velocidad, tocar solo esto.
const double kMotionSlowdown = 1.4;

/// [ms] base multiplicados por [kMotionSlowdown].
Duration motionMs(num ms) =>
    Duration(microseconds: (ms * 1000 * kMotionSlowdown).round());

abstract final class SheetMotion {
  /// Hoja que sube: 900 × 1,4 = 1260 ms (§ 8.24; antes 952, 728 y 560 ms).
  static final duration = motionMs(900);

  /// Fundido entre estados: 350 × 1,4 = 490 ms (§ 8.24; antes 308 ms).
  static final fadeDuration = motionMs(350);

  /// Pantalla de atrás: se aleja poco (0,95) y se oscurece 25 %. Con 0,93 y
  /// 40 % se veía pesado en cambios que se repiten mucho.
  static const backScale = .95;
  static const backDim = .25;
  static const sheetRadius = 32.0;
  static const backRadius = 28.0;

  /// Curvas del diseño: `cubic-bezier(.2,.8,.2,1)` y `(.4,0,1,1)`.
  /// Se usan en el pop de los botones (movimientos cortos).
  static const easeOut = Cubic(.2, .8, .2, 1);
  static const easeIn = Cubic(.4, 0, 1, 1);

  /// Curva de la hoja al ENTRAR (§ 8.23): arranca suave, va pareja y frena
  /// suave (`easeInOutCubic`), como se siente la vuelta. Historia: `easeOut`
  /// del diseño y `easeOutCubic` hacían casi todo el recorrido al principio
  /// (salto); la "enfatizada" de Material 3 también cargaba el recorrido al
  /// principio y la ida se sentía rápida comparada con la vuelta.
  static const Curve enter = Curves.easeInOutCubic;

  /// Curva para lo que vuelve al frente y para los fundidos.
  static const Curve settle = Curves.easeOutCubic;
}

/// Reloj de la hoja que trae una pantalla (§ 8.24). Lo leen los bloques que
/// se revelan ([RevealIn]) para crearse RECIÉN CUANDO la hoja se posó
/// (§ 8.25: primero pasa la página, después se crean las tarjetas).
///
/// - Pantalla que llega: el controlador de la hoja (0 → 1).
/// - Pantalla que se va o pantalla quieta: completo (1).
class SheetProgress extends InheritedWidget {
  final Animation<double> animation;

  const SheetProgress({
    super.key,
    required this.animation,
    required super.child,
  });

  /// La animación de la hoja si todavía no terminó; si no, null.
  static Animation<double>? runningOf(BuildContext context) {
    final a = context.getInheritedWidgetOfExactType<SheetProgress>()?.animation;
    return a != null && a.value < 1 ? a : null;
  }

  @override
  bool updateShouldNotify(SheetProgress oldWidget) => false;
}

/// Una pantalla dentro de la transición.
///
/// [slide]: 0 = en su sitio, 1 = fuera por abajo, -1 = fuera por arriba.
/// [back]: 0 = al frente, 1 = alejada al fondo.
/// [veil]: 0 = sin velo, 1 = cubierta por el color de fondo (fundidos).
/// Se usa un velo y no `Opacity`: la transparencia de una pantalla entera
/// obliga a dibujarla en una capa aparte y daba picos de 50-90 ms al
/// empezar cada fundido (medido corriendo la app, § 8.16).
///
/// Siempre arma el mismo árbol (aunque los valores sean 0) para que la
/// pantalla no pierda su estado al empezar o terminar la animación.
class SheetLayer extends StatelessWidget {
  final double slide;
  final double back;
  final double veil;
  final Color background;
  final Widget child;

  /// La pantalla está QUIETA mientras se mueve (la que queda detrás o la que
  /// se va): se dibuja como una foto (§ 8.40). Una vez y listo; cada cuadro
  /// solo la achica/corre. Sin esto, cada cuadro redibujaba la pantalla
  /// entera escalada (fotos, textos, bordes): 16-27 ms por cuadro medidos
  /// al abrir "Tu pedido" = tirones.
  final bool snapshot;

  const SheetLayer({
    super.key,
    required this.slide,
    required this.back,
    required this.child,
    this.veil = 0,
    this.background = Colors.transparent,
    this.snapshot = false,
  });

  @override
  Widget build(BuildContext context) {
    // El borde que entra va redondeado: el de arriba si sube (slide > 0), el
    // de abajo si baja desde arriba (slide < 0, vuelta en espejo, § 8.31).
    final lead = SheetMotion.sheetRadius * slide.abs();
    final backR = SheetMotion.backRadius * back;
    final top = math.max(slide > 0 ? lead : 0.0, backR);
    final bottom = math.max(slide < 0 ? lead : 0.0, backR);
    final rounded = top > 0 || bottom > 0;
    // Fondo que se ve alrededor de la pantalla alejada: el crema de la app
    // oscurecido igual que la pantalla (sin marco crema claro).
    final backdrop = back > 0
        ? Color.lerp(Theme.of(context).scaffoldBackgroundColor, Colors.black,
            SheetMotion.backDim * back)!
        : Colors.transparent;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: ColoredBox(color: backdrop)),
        _scaled(context, top: top, bottom: bottom, rounded: rounded),
      ],
    );
  }

  Widget _scaled(BuildContext context,
      {required double top, required double bottom, required bool rounded}) {
    final veilColor = Theme.of(context)
        .scaffoldBackgroundColor
        .withValues(alpha: veil.clamp(0.0, 1.0));
    return Transform.scale(
      scale: 1 - (1 - SheetMotion.backScale) * back,
      child: FractionalTranslation(
        translation: Offset(0, slide),
        child: ClipRRect(
          clipBehavior: rounded ? Clip.antiAlias : Clip.none,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(top),
            bottom: Radius.circular(bottom),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // RepaintBoundary: la pantalla se pinta UNA vez y la animación
              // solo la mueve/escala (sin repintar fotos y textos cada cuadro).
              // Con [snapshot], además se dibuja como foto (§ 8.40).
              _Snapshot(
                enabled: snapshot,
                child: RepaintBoundary(
                  child: ColoredBox(color: background, child: child),
                ),
              ),
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black
                      .withValues(alpha: SheetMotion.backDim * back),
                ),
              ),
              IgnorePointer(child: ColoredBox(color: veilColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foto de la pantalla mientras [enabled] (§ 8.40): `SnapshotWidget` de
/// Flutter (lo que usan sus propias transiciones). Siempre el mismo árbol:
/// prender/apagar la foto no rearma la pantalla. Si la pantalla cambia
/// durante la foto, se vuelve a tomar.
class _Snapshot extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const _Snapshot({required this.enabled, required this.child});

  @override
  State<_Snapshot> createState() => _SnapshotState();
}

class _SnapshotState extends State<_Snapshot> {
  late final SnapshotController _controller =
      SnapshotController(allowSnapshotting: widget.enabled);

  @override
  void didUpdateWidget(_Snapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.allowSnapshotting = widget.enabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
        controller: _controller,
        // Si adentro hubiera una vista nativa, se dibuja normal (sin foto).
        mode: SnapshotMode.permissive,
        child: widget.child,
      );
}

/// Cambia de pantalla cuando cambia [screen]: con la hoja si las dos son
/// [pages] (o si [pages] es null), y con un fundido si no.
///
/// [order] da la dirección de la hoja: si la nueva pantalla tiene un orden
/// mayor o igual se "avanza" (la hoja sube); si es menor se "vuelve" (baja).
class SheetSwitcher extends StatefulWidget {
  final Object screen;
  final int order;
  final Color background;

  /// Pantallas que son PÁGINAS (entre ellas: hoja). Entre cualquier otra
  /// pareja: fundido. null = todo con hoja.
  final Set<Object>? pages;
  final Widget child;

  const SheetSwitcher({
    super.key,
    required this.screen,
    required this.order,
    required this.child,
    this.pages,
    this.background = Colors.transparent,
  });

  @override
  State<SheetSwitcher> createState() => _SheetSwitcherState();
}

enum _Mode { up, down, fade }

/// Punto del fundido en que la vieja ya está cubierta y empieza la nueva.
const _fadeCut = .35;

class _SheetSwitcherState extends State<SheetSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: SheetMotion.duration, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _old != null) {
            setState(() => _old = null);
          }
        });

  /// Pantalla que se va (solo mientras dura la animación).
  ({Object screen, Widget child})? _old;
  _Mode _mode = _Mode.up;

  @override
  void didUpdateWidget(SheetSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screen == widget.screen) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _old = null;
      return;
    }
    final pages = widget.pages;
    final isPageChange = pages == null ||
        (pages.contains(oldWidget.screen) && pages.contains(widget.screen));
    _mode = !isPageChange
        ? _Mode.fade
        : widget.order >= oldWidget.order
            ? _Mode.up
            : _Mode.down;
    // Si otra pantalla (p. ej. "Tu pedido") está encima o cerrándose, el
    // cambio es directo: lo que se ve es la hoja de esa ruta (§ 8.31). Así,
    // al volver a la cara después de pagar, no hay dos hojas a la vez.
    final covering = ModalRoute.of(context)?.secondaryAnimation;
    if (covering != null && covering.status != AnimationStatus.dismissed) {
      ++_startToken;
      _old = null;
      _controller
        ..stop()
        ..value = 1;
      return;
    }
    _old = (screen: oldWidget.screen, child: oldWidget.child);
    // Ida y vuelta iguales (§ 8.31): misma duración y curva.
    _controller.duration =
        _mode == _Mode.fade ? SheetMotion.fadeDuration : SheetMotion.duration;
    // Fase 8 (§ 8.21): la animación ARRANCA cuando la pantalla nueva ya se
    // armó y se dibujó una vez (2 cuadros). Antes arrancaba en el mismo
    // cuadro en que se armaba el catálogo entero (~65 ms la 1.ª vez): se veía
    // quieto al inicio y luego un salto. Mientras, queda en 0 (la nueva fuera
    // de la vista, la vieja quieta).
    _controller
      ..stop()
      ..value = 0;
    final token = ++_startToken;
    void startAfterFrames(int frames) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _startToken) return;
        if (frames > 1) {
          startAfterFrames(frames - 1);
          SchedulerBinding.instance.scheduleFrame();
        } else {
          _controller.forward(from: 0);
        }
      });
    }

    startAfterFrames(2);
  }

  /// Evita que un arranque pendiente de un cambio anterior pise al nuevo.
  int _startToken = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _layer(Object screen, Widget child,
      {required double slide,
      required double back,
      required double veil,
      required bool old}) {
    // La clave va en el hijo DIRECTO del Stack (este Positioned): así cada
    // pantalla conserva su estado aunque cambie de capa o se quite la otra.
    // Si la clave quedara más adentro, al terminar la hoja la pantalla nueva
    // se volvería a crear y "cargaría" dos veces.
    return Positioned.fill(
      key: ValueKey(screen),
      child: IgnorePointer(
        ignoring: old,
        child: SheetLayer(
          slide: slide,
          back: back,
          veil: veil,
          background: widget.background,
          // La que se va está quieta: foto (§ 8.40).
          snapshot: old,
          // Reloj para los bloques de la pantalla que llega (§ 8.24).
          child: SheetProgress(
            animation: old ? kAlwaysCompleteAnimation : _controller,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: lo que se mueve aquí no obliga a repintar el resto
    // de la página (overlay de audio, etc.).
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final old = _old;
          final c = _controller.value;
          var newSlide = 0.0, newBack = 0.0, newVeil = 0.0;
          var oldSlide = 0.0, oldBack = 0.0, oldVeil = 0.0;
          if (old != null) {
            switch (_mode) {
              case _Mode.up:
                final t = SheetMotion.enter.transform(c);
                newSlide = 1 - t;
                oldBack = t;
              case _Mode.down:
                // Espejo de subir (§ 8.31): la anterior baja desde arriba y
                // la actual se aleja al fondo.
                final t = SheetMotion.enter.transform(c);
                newSlide = -(1 - t);
                oldBack = t;
              case _Mode.fade:
                // Fundido a través del color de fondo: la vieja se cubre
                // RÁPIDO (primer 35 %) y la nueva aparece enseguida (65 %).
                // Con mitad y mitad la nueva tardaba en asomar y se sentía
                // como una espera (§ 8.25). Sin transparencias.
                if (c < _fadeCut) {
                  oldVeil = Curves.easeOut.transform(c / _fadeCut);
                  newVeil = 1;
                } else {
                  newVeil = 1 -
                      SheetMotion.settle
                          .transform((c - _fadeCut) / (1 - _fadeCut));
                  oldVeil = 1;
                }
            }
          }

          final current = _layer(widget.screen, widget.child,
              slide: newSlide, back: newBack, veil: newVeil, old: false);
          if (old == null) return Stack(children: [current]);

          final leaving = _layer(old.screen, old.child,
              slide: oldSlide, back: oldBack, veil: oldVeil, old: true);
          // Arriba va la nueva (sube o baja como hoja). En el fundido, la que
          // se está viendo (la vieja y luego la nueva).
          final oldOnTop = _mode == _Mode.fade && c < _fadeCut;
          return Stack(
            children: oldOnTop ? [current, leaving] : [leaving, current],
          );
        },
      ),
    );
  }
}

/// La misma hoja para las rutas del [Navigator] (p. ej. "Tu pedido").
///
/// Se registra en `ThemeData.pageTransitionsTheme`.
/// - Abrir: la ruta nueva sube y la de abajo se aleja (`secondaryAnimation`).
/// - Cerrar (§ 8.31): espejo, la de abajo BAJA desde arriba encima y la que
///   se cierra se aleja al fondo. Misma duración y curva.
class SheetPageTransitionsBuilder extends PageTransitionsBuilder {
  const SheetPageTransitionsBuilder();

  @override
  Duration get transitionDuration => SheetMotion.duration;

  @override
  Duration get reverseTransitionDuration => SheetMotion.duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SheetRouteTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _SheetRouteTransition extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _SheetRouteTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  State<_SheetRouteTransition> createState() => _SheetRouteTransitionState();
}

class _SheetRouteTransitionState extends State<_SheetRouteTransition> {
  final _own = _StartHold();
  final _above = _StartHold();

  @override
  Widget build(BuildContext context) {
    final animation = widget.animation;
    final secondaryAnimation = widget.secondaryAnimation;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: widget.child,
      builder: (context, child) {
        // Avance con la espera del arranque (§ 8.40).
        final a = _own.value(animation);
        final s2 = _above.value(secondaryAnimation);
        var slide = 0.0, back = 0.0, cut = 0.0;
        // Foto (§ 8.40) para la ruta que se aleja al fondo mientras pasa la
        // otra: la de abajo al abrir la de arriba, o la que se cierra.
        final still = animation.status == AnimationStatus.reverse ||
            secondaryAnimation.status == AnimationStatus.forward;
        if (animation.status == AnimationStatus.reverse) {
          // Esta ruta se cierra: se aleja al fondo y la de abajo la tapa
          // bajando desde arriba. Como Navigator pinta esta ENCIMA, se
          // recorta la parte que ya cubre la que baja.
          back = cut = SheetMotion.enter.transform(1 - a);
        } else if (secondaryAnimation.status == AnimationStatus.reverse) {
          // La de arriba se cierra: esta baja desde arriba.
          slide = -(1 - SheetMotion.enter.transform(1 - s2));
        } else {
          slide = 1 - SheetMotion.enter.transform(a);
          back = SheetMotion.enter.transform(s2);
        }
        // Siempre el mismo árbol (ClipPath aunque no recorte) para no perder
        // el estado de la pantalla.
        return ClipPath(
          clipper: _BelowSheetClipper(cut),
          clipBehavior: cut > 0 ? Clip.antiAlias : Clip.none,
          child: SheetLayer(
              slide: slide, back: back, snapshot: still, child: child!),
        );
      },
    );
  }
}

/// Espera del arranque de una ruta (§ 8.40): en los primeros cuadros se
/// arma la pantalla nueva y se toma la foto de la de atrás (35-85 ms medidos
/// al abrir "Tu pedido"). Si la hoja ya corría, al terminar esos cuadros
/// saltaba. Ahora queda quieta esos [frames] cuadros y después recorre TODO
/// el camino desde ahí (sin salto), como la hoja entre pantallas (§ 8.21).
class _StartHold {
  static const frames = 3;

  AnimationStatus? _status;
  int _seen = 0;
  double _base = 0;

  /// Valor de [a] remapeado: 0 → 1 al abrir y 1 → 0 al cerrar.
  double value(Animation<double> a) {
    final status = a.status;
    if (status != _status) {
      _status = status;
      _seen = 0;
    }
    switch (status) {
      case AnimationStatus.forward:
        if (_seen < frames) {
          _seen++;
          _base = a.value;
          return 0;
        }
        return _base >= 1 ? 1 : ((a.value - _base) / (1 - _base)).clamp(0, 1);
      case AnimationStatus.reverse:
        if (_seen < frames) {
          _seen++;
          _base = a.value;
          return 1;
        }
        return _base <= 0 ? 0 : (a.value / _base).clamp(0, 1);
      case AnimationStatus.completed:
      case AnimationStatus.dismissed:
        return a.value;
    }
  }
}

/// Deja ver solo lo que está DEBAJO de la hoja que baja desde arriba
/// ([cut] = cuánto bajó, 0 a 1), con sus esquinas de abajo redondeadas.
class _BelowSheetClipper extends CustomClipper<Path> {
  final double cut;

  const _BelowSheetClipper(this.cut);

  @override
  Path getClip(Size size) {
    final all = Path()..addRect(Offset.zero & size);
    if (cut <= 0) return all;
    final r = Radius.circular(SheetMotion.sheetRadius * (1 - cut));
    final sheet = Path()
      ..addRRect(RRect.fromLTRBAndCorners(0, -1, size.width, size.height * cut,
          bottomLeft: r, bottomRight: r));
    return Path.combine(PathOperation.difference, all, sheet);
  }

  @override
  bool shouldReclip(_BelowSheetClipper old) => old.cut != cut;
}
