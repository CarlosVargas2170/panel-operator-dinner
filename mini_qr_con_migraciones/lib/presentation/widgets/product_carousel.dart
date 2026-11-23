import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import '../../core/services/image_preloader.dart';
import '../../core/ui/themes/app_colors.dart';
import '../../domain/entities/product.dart';
import 'motion/pop.dart';
import 'motion/reveal.dart';
import 'motion/sheet_transition.dart';
import 'product_card.dart';

/// Carrusel del catálogo, rediseñado como carrusel de verdad (§ 8.38).
///
/// Una sola tira horizontal con todas las páginas, que se desliza igual con
/// flechas, puntos, pestañas o el dedo. Antes era `carousel_slider` con una
/// capa encima (copias de dos páginas que se movían y al final se cambiaban
/// por el carrusel real): dos mundos que había que empalmar en cada paso.
///
/// - Todas las páginas quedan armadas de antemano (se arman de a una
///   después de entrar al catálogo): al deslizar nunca se arma nada.
/// - Cada página se dibuja una vez (RepaintBoundary) y en cada cuadro solo
///   se corre, alineada a píxeles enteros de la pantalla (sin temblor).
/// - La posición, cuadro a cuadro, sale en [ProductCarousel.position]: la
///   barra de categorías se mueve a la par.

const int _maxVisibleIndicators = 7;

/// Paso de una página con flechas, puntos o pestañas: 360 × 1,4 = 504 ms
/// (§ 8.44; antes 630 ms § 8.43, 1610 ms § 8.35). Saltos de varias páginas
/// tardan apenas más (ver `_goTo`).
final _pageSlideDuration = motionMs(360);

/// Curva del paso con flechas/puntos/pestañas (la de la hoja, § 8.23).
const Curve _pageSlideCurve = Curves.easeInOutCubic;

/// Animación de los puntos (el activo se estira).
final _dotDuration = motionMs(220); // 308 ms

@visibleForTesting
List<int> buildVisibleIndicatorIndices({
  required int count,
  required int current,
  int maxVisible = _maxVisibleIndicators,
}) {
  if (count <= 0 || maxVisible <= 0) return const [];

  final visibleCount = count < maxVisible ? count : maxVisible;
  final safeCurrent = current.clamp(0, count - 1);
  final halfWindow = visibleCount ~/ 2;
  final maxStart = count - visibleCount;
  final start = (safeCurrent - halfWindow).clamp(0, maxStart);

  return List.generate(visibleCount, (offset) => start + offset);
}

class ProductCarousel extends StatefulWidget {
  /// Productos en páginas de 6 (`HomeState.pages`).
  final List<List<Product>> pages;

  /// Página actual del carrusel.
  final int currentIndex;
  final int Function(Product product) quantityFor;
  final int maxQuantity;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onRemove;

  /// Avisa la página que quedó a la vista (deslizar, flechas, puntos) cuando
  /// ya se posó. En la home: `HomeCubit.updateCurrentIndex` (reloj de
  /// inactividad).
  final ValueChanged<int>? onPageChanged;

  /// Posición del carrusel en páginas, cuadro a cuadro (1.5 = a mitad entre
  /// la 2.ª y la 3.ª). La lee la barra de categorías para moverse a la par
  /// (§ 8.38). Si es null, el carrusel usa una propia.
  final ValueNotifier<double>? position;

  /// Turno de la primera tarjeta en el revelado (fase 8): va después de la
  /// cabecera y el destacado.
  final int revealIndex;

  /// Corrimiento horizontal (px del lienzo) de flechas y puntos para que
  /// queden centrados en la PANTALLA y no solo bajo las tarjetas (§ 8.23).
  final double controlsShift;

  /// Tarjetas por página (cuadrícula 3 × 2).
  static const tilesPerPage = 6;

  const ProductCarousel({
    super.key,
    required this.pages,
    required this.currentIndex,
    required this.quantityFor,
    required this.maxQuantity,
    required this.onAdd,
    required this.onRemove,
    this.onPageChanged,
    this.position,
    this.revealIndex = 0,
    this.controlsShift = 0,
  });

  @override
  State<ProductCarousel> createState() => _ProductCarouselState();
}

class _ProductCarouselState extends State<ProductCarousel> {
  /// Se crea con el primer ancho conocido (para abrir en la página justa).
  ScrollController? _controller;
  double _pageWidth = 0;

  late final ValueNotifier<double> _ownPosition =
      ValueNotifier(_safeIndex.toDouble());
  ValueNotifier<double> get _position => widget.position ?? _ownPosition;

  /// Página con la que se abre el catálogo: la ÚNICA cuyas tarjetas se
  /// arman animadas (§ 8.26). Las demás ya están dibujadas.
  late final int _entryPage = _safeIndex;

  /// Destino conocido (para no repetir un paso que llega desde fuera).
  late int _target = _safeIndex;

  /// Última página avisada con [ProductCarousel.onPageChanged].
  late int _reportedIndex = _safeIndex;

  /// Páginas armadas por adelantado a cada lado de la vista. Empieza en 0
  /// (la entrada al catálogo no carga más) y sube de a una cuando la hoja
  /// que trae el catálogo ya pasó, hasta cubrir todas.
  int _warmPages = 0;
  Timer? _warmTimer;

  /// Cada página armada una vez y reusada mientras no cambien sus productos
  /// ni sus cantidades: las reconstrucciones de la home (cambio de página,
  /// reloj, etc.) no rearman tarjetas.
  final Map<int, ({String sign, Widget page})> _pageCache = {};

  int get _safeIndex => widget.pages.isEmpty
      ? 0
      : widget.currentIndex.clamp(0, widget.pages.length - 1);

  @override
  void initState() {
    super.initState();
    if (widget.position != null) {
      // Se avisa después del primer cuadro (no se puede durante el armado).
      final start = _safeIndex.toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setPosition(start);
      });
    }
    _preloadImages();
    _warmTimer = Timer(
        SheetMotion.duration + const Duration(milliseconds: 300), _warmStep);
  }

  void _warmStep() {
    if (!mounted || _warmPages >= widget.pages.length) return;
    // De a una página (6 tarjetas, < 1 cuadro de trabajo) y con pausa.
    setState(() => _warmPages++);
    _warmTimer = Timer(const Duration(milliseconds: 150), _warmStep);
  }

  /// Fotos de TODAS las páginas a memoria apenas se abre el catálogo (y
  /// cuando el polling trae productos nuevos): al llegar a cualquier página
  /// sus fotos ya están (§ 8.19).
  void _preloadImages() {
    // Fase 8 (§ 8.21): se espera a que termine la hoja que trae el catálogo
    // y se va de a 2: decodificar fotos le competía a la animación por la
    // CPU justo al inicio (se veía congelado).
    Future<void>.delayed(
        SheetMotion.duration + const Duration(milliseconds: 250), () {
      if (!mounted) return;
      ImagePreloader.preload(
        context,
        [
          for (final page in widget.pages)
            for (final product in page) product.urlImage,
        ],
        concurrency: 2,
      );
    });
  }

  @override
  void dispose() {
    _warmTimer?.cancel();
    _controller?.dispose();
    _ownPosition.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProductCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pages, widget.pages)) _preloadImages();
    if (widget.pages.length != oldWidget.pages.length) {
      _pageCache.removeWhere((i, _) => i >= widget.pages.length);
      if (_warmPages < widget.pages.length && _warmTimer?.isActive != true) {
        _warmTimer = Timer(const Duration(milliseconds: 150), _warmStep);
      }
    }
    // Página pedida desde fuera (pestañas): se desliza hasta ahí.
    final target = _safeIndex;
    if (target != _target) {
      _target = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goTo(target);
      });
    }
  }

  /// Actualiza la posición sin avisar en medio de un armado/acomodo (la
  /// barra de categorías se reconstruye con ella).
  void _setPosition(double page) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _position.value = page;
      });
    } else {
      _position.value = page;
    }
  }

  void _onScroll() {
    final c = _controller;
    if (c == null || !c.hasClients || _pageWidth <= 0) return;
    _setPosition(c.offset / _pageWidth);
  }

  /// Se avisa la página cuando YA SE POSÓ (§ 8.19): avisar a mitad del paso
  /// reconstruía la home en medio del movimiento.
  bool _onScrollEnd(ScrollEndNotification n) {
    if (_pageWidth <= 0 || n.depth != 0) return false;
    final page = n.metrics.pixels / _pageWidth;
    final rest = page.roundToDouble();
    if ((page - rest).abs() < .01) {
      final index = rest.toInt().clamp(0, widget.pages.length - 1);
      _target = index;
      if (index != _reportedIndex) {
        _reportedIndex = index;
        widget.onPageChanged?.call(index);
      }
    }
    return false;
  }

  /// Flechas, puntos y pestañas: la tira se desliza hasta [page].
  void _goTo(int page) {
    final c = _controller;
    if (c == null || !c.hasClients || _pageWidth <= 0) return;
    page = page.clamp(0, widget.pages.length - 1);
    _target = page;
    final to = page * _pageWidth;
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      c.jumpTo(to);
      return;
    }
    final distance = (c.offset - to).abs() / _pageWidth;
    if (distance < .001) return;
    // Una página: 504 ms. Varias (pestaña lejana): casi lo mismo, como
    // mucho ~680 ms aunque haya muchas páginas en el medio (§ 8.43; antes
    // hasta 3,2 s).
    final factor =
        distance <= 1 ? distance.clamp(.35, 1.0) : 1 + .12 * (distance - 1);
    c.animateTo(
      to,
      duration: _pageSlideDuration * math.min(factor, 1.35),
      curve: _pageSlideCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (_controller == null) {
                _controller =
                    ScrollController(initialScrollOffset: _safeIndex * w)
                      ..addListener(_onScroll);
              } else if (_pageWidth > 0 && w != _pageWidth) {
                // Cambió el ancho: quedarse en la misma página.
                final page = _position.value.round();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final c = _controller;
                  if (mounted && c != null && c.hasClients) {
                    c.jumpTo(page * _pageWidth);
                  }
                });
              }
              _pageWidth = w;
              return ScrollConfiguration(
                // Deslizar con dedo, mouse, lápiz o touchpad; sin barra de
                // desplazamiento ni rebote.
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: PointerDeviceKind.values.toSet(),
                  scrollbars: false,
                  overscroll: false,
                ),
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: _onScrollEnd,
                  child: ListView.builder(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    physics: const _PagePhysics(),
                    itemExtent: w,
                    scrollCacheExtent:
                        ScrollCacheExtent.viewport(_warmPages.toDouble()),
                    itemCount: widget.pages.length,
                    // Cada página trae su propio RepaintBoundary, DENTRO del
                    // alineado a píxeles (que se pinta en cada cuadro).
                    addRepaintBoundaries: false,
                    itemBuilder: (context, index) => _page(index),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.pages.length > 1) ...[
          const SizedBox(height: 8),
          // Flechas y puntos llegan con la hoja (§ 8.39); solo ellos se
          // redibujan al deslizar (§ 8.19).
          RepaintBoundary(
            child: Transform.translate(
              offset: Offset(widget.controlsShift, 0),
              child: ValueListenableBuilder<double>(
                valueListenable: _position,
                builder: (context, page, _) => _buildControls(
                  page.round().clamp(0, widget.pages.length - 1),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Página [i], armada una vez y reusada mientras no cambien sus productos
  /// ni sus cantidades.
  Widget _page(int i) {
    final products = widget.pages[i];
    final sign = [
      widget.maxQuantity,
      for (final p in products) '${p.id}:${widget.quantityFor(p)}',
    ].join(',');
    final cached = _pageCache[i];
    if (cached != null && cached.sign == sign) return cached.page;
    final page = _PixelAlign(
      child: RepaintBoundary(child: _buildPage(products, pageIndex: i)),
    );
    _pageCache[i] = (sign: sign, page: page);
    return page;
  }

  /// Una página: 3 filas × 2 columnas de [ProductCard].
  Widget _buildPage(List<Product> page, {required int pageIndex}) {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 2; col++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      // Solo la página de entrada: entra suave mientras la
                      // hoja se posa (§ 8.39). Las demás ya están dibujadas.
                      child: SoftEntry(
                        enabled: pageIndex == _entryPage,
                        index: widget.revealIndex + row * 2 + col,
                        child: _buildCell(page, row * 2 + col),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(List<Product> page, int index) {
    if (index >= page.length) return const SizedBox.shrink();
    final product = page[index];
    return ProductCard(
      product: product,
      quantity: widget.quantityFor(product),
      maxQuantity: widget.maxQuantity,
      // `widget` se lee al tocar: siempre el actual (la página se reusa).
      onAdd: () => widget.onAdd(product),
      onRemove: () => widget.onRemove(product),
    );
  }

  /// ‹ · · · › : flechas (se apagan en la primera / última) y, entre ellas,
  /// un punto por página; el actual se estira.
  Widget _buildControls(int current) {
    final isFirst = current <= 0;
    final isLast = current >= widget.pages.length - 1;

    Widget arrow(IconData icon, String key, VoidCallback? onPressed) {
      return PopPress(
        enabled: onPressed != null,
        child: IconButton.filled(
          key: ValueKey(key),
          onPressed: onPressed,
          icon: Icon(icon, size: 30),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            disabledBackgroundColor: AppColors.border,
            disabledForegroundColor: AppColors.textMuted,
            fixedSize: const Size(48, 48),
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(
          Icons.chevron_left,
          'carousel-prev',
          isFirst ? null : () => _goTo(_target - 1),
        ),
        const SizedBox(width: 20),
        for (final i in buildVisibleIndicatorIndices(
          count: widget.pages.length,
          current: current,
        ))
          _Dot(
            key: ValueKey('carousel-dot-$i'),
            active: i == current,
            onTap: () => _goTo(i),
          ),
        const SizedBox(width: 20),
        arrow(
          Icons.chevron_right,
          'carousel-next',
          isLast ? null : () => _goTo(_target + 1),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _Dot({super.key, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Zona de toque más grande que el punto (es un kiosco táctil).
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 15),
        child: AnimatedContainer(
          duration: _dotDuration,
          curve: SheetMotion.settle,
          width: active ? 52 : 18,
          height: 18,
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(9),
          ),
        ),
      ),
    );
  }
}

/// Física de la tira (§ 8.36, 8.38): mientras el dedo arrastra, la página lo
/// sigue; al soltar, termina en la página más cercana (o la siguiente si
/// hubo impulso) con el MISMO tiempo que las flechas (proporcional a lo que
/// falte) y una curva que sigue el impulso y se posa suave. Sin rebote en
/// los bordes.
class _PagePhysics extends ScrollPhysics {
  const _PagePhysics({super.parent});

  @override
  _PagePhysics applyTo(ScrollPhysics? ancestor) => _PagePhysics(
      parent: buildParent(ancestor ?? const ClampingScrollPhysics()));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent) ||
        position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final extent = position.viewportDimension;
    if (extent <= 0) return null;
    final tolerance = toleranceFor(position);
    var page = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * extent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final distance = (target - position.pixels).abs();
    if (distance < tolerance.distance) return null;
    final ms =
        math.max(200.0, distance / extent * _pageSlideDuration.inMilliseconds);
    return _CurveSimulation(
      from: position.pixels,
      to: target,
      seconds: ms / 1000,
      curve: SheetMotion.settle,
    );
  }
}

/// Va de [from] a [to] en [seconds] siguiendo [curve].
class _CurveSimulation extends Simulation {
  final double from;
  final double to;
  final double seconds;
  final Curve curve;

  _CurveSimulation({
    required this.from,
    required this.to,
    required this.seconds,
    required this.curve,
  });

  double _p(double time) => (time / seconds).clamp(0.0, 1.0);

  @override
  double x(double time) => from + (to - from) * curve.transform(_p(time));

  @override
  double dx(double time) {
    const h = 1 / 240;
    return (x(time + h) - x(time)) / h;
  }

  @override
  bool isDone(double time) => time >= seconds;
}

/// Alinea a su hijo a píxeles enteros de la pantalla (§ 8.34, 8.38).
///
/// La tira se corre de a fracciones de píxel (y además el lienzo de 1440
/// está escalado): sin esto, textos y bordes se redibujan un poco distinto
/// en cada cuadro y "tiemblan". Se pinta en cada cuadro del deslizamiento
/// (corrige solo la fracción, < 1 píxel) y su hijo es un RepaintBoundary
/// que NO se vuelve a dibujar: solo se coloca.
class _PixelAlign extends SingleChildRenderObjectWidget {
  const _PixelAlign({super.child});

  @override
  _RenderPixelAlign createRenderObject(BuildContext context) =>
      _RenderPixelAlign(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderPixelAlign r) {
    r.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderPixelAlign extends RenderProxyBox {
  _RenderPixelAlign(this._devicePixelRatio);

  double _devicePixelRatio;
  set devicePixelRatio(double v) {
    if (v == _devicePixelRatio) return;
    _devicePixelRatio = v;
    markNeedsPaint();
  }

  Offset _shift = Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final m = getTransformTo(null);
    final fx = m.entry(0, 0).abs() * _devicePixelRatio;
    final fy = m.entry(1, 1).abs() * _devicePixelRatio;
    if (fx > 0 && fy > 0) {
      final gx = m.entry(0, 3) * _devicePixelRatio;
      final gy = m.entry(1, 3) * _devicePixelRatio;
      _shift = Offset(
          (gx.roundToDouble() - gx) / fx, (gy.roundToDouble() - gy) / fy);
    } else {
      _shift = Offset.zero;
    }
    context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, p) => child.hitTest(result, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }
}
