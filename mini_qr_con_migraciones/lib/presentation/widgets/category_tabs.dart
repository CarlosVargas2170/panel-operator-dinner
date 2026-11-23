import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/ui/themes/app_colors.dart';
import 'motion/pop.dart';

/// Pestañas del catálogo: una por categoría.
///
/// Con [position] y [pageCategories] (§ 8.38), la pastilla oscura de la
/// pestaña activa se DESLIZA a la par del carrusel, cuadro a cuadro: a mitad
/// de un paso entre dos categorías está a mitad de camino entre sus
/// pestañas, y el color de los textos pasa de uno a otro al mismo ritmo.
/// Antes la pestaña saltaba recién cuando la página ya se había posado.
class CategoryTabs extends StatefulWidget {
  final List<String> categories;

  /// Pestaña activa cuando no hay [position] (null = ninguna).
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// Categoría de cada página del carrusel (`HomeState.pageCategories`).
  final List<String?> pageCategories;

  /// Posición del carrusel en páginas, cuadro a cuadro.
  final ValueListenable<double>? position;

  const CategoryTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.pageCategories = const [],
    this.position,
  });

  @override
  State<CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<CategoryTabs> {
  final _stackKey = GlobalKey();
  List<GlobalKey> _tabKeys = [];

  /// Lugar de cada pestaña dentro de la barra (se mide tras dibujarla).
  List<Rect>? _rects;

  static const _pad = 6.0;

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(CategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.categories, widget.categories)) {
      _syncKeys();
      _rects = null;
    }
  }

  void _syncKeys() {
    _tabKeys = [for (final _ in widget.categories) GlobalKey()];
  }

  /// Mide las pestañas después de dibujarlas; solo redibuja si cambiaron.
  void _measure() {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.hasSize) return;
    final rects = <Rect>[];
    for (final key in _tabKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final topLeft = box.localToGlobal(Offset.zero, ancestor: stack);
      rects.add(topLeft & box.size);
    }
    final old = _rects;
    if (old != null && listEquals(old, rects)) return;
    setState(() => _rects = rects);
  }

  /// Pestaña de cada página del carrusel (-1 si la página no tiene).
  int _tabOfPage(int page) {
    final cats = widget.pageCategories;
    if (cats.isEmpty) return -1;
    final c = cats[page.clamp(0, cats.length - 1)];
    return c == null ? -1 : widget.categories.indexOf(c);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final position = widget.position;
    final rects = _rects;
    final sliding =
        position != null && rects != null && widget.pageCategories.isNotEmpty;

    return Container(
      height: 64,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        key: _stackKey,
        children: [
          if (sliding)
            ValueListenableBuilder<double>(
              valueListenable: position,
              builder: (context, page, _) {
                final (rect, _) = _pill(page, rects);
                if (rect == null) return const SizedBox.shrink();
                return Positioned.fromRect(
                  rect: rect,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.all(Radius.circular(26)),
                    ),
                  ),
                );
              },
            ),
          if (sliding)
            ValueListenableBuilder<double>(
              valueListenable: position,
              builder: (context, page, _) {
                final (_, weights) = _pill(page, rects);
                return _row(weights);
              },
            )
          else
            _row([
              for (final c in widget.categories) c == widget.selected ? 1 : 0,
            ], solid: true),
        ],
      ),
    );
  }

  /// Dónde va la pastilla para la posición [page] del carrusel y cuánto
  /// "activa" está cada pestaña (0 a 1, para el color del texto).
  (Rect?, List<double>) _pill(double page, List<Rect> rects) {
    final last = widget.pageCategories.length - 1;
    final p = page.clamp(0.0, last.toDouble());
    final i0 = p.floor();
    final i1 = p.ceil();
    final t = p - i0;
    final a = _tabOfPage(i0);
    final b = _tabOfPage(i1);
    final weights = List<double>.filled(widget.categories.length, 0);
    if (a >= 0) weights[a] += 1 - t;
    if (b >= 0) weights[b] += t;
    Rect? rect;
    if (a >= 0 && b >= 0) {
      rect = Rect.lerp(rects[a], rects[b], t);
    } else if (a >= 0) {
      rect = rects[a];
    } else if (b >= 0) {
      rect = rects[b];
    }
    return (rect, weights);
  }

  Widget _row(List<double> weights, {bool solid = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.categories.length; i++)
          _tab(i, weights[i].clamp(0.0, 1.0), solid: solid),
      ],
    );
  }

  Widget _tab(int i, double active, {required bool solid}) {
    final category = widget.categories[i];
    return PopPress(
      child: GestureDetector(
        onTap: () => widget.onSelect(category),
        child: Container(
          key: _tabKeys[i],
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          // Sin pastilla deslizante (primer cuadro): fondo en la activa.
          decoration: solid && active > .5
              ? BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(26),
                )
              : null,
          child: Text(
            category.toUpperCase(),
            style: TextStyle(
              color:
                  Color.lerp(AppColors.textPrimary, AppColors.onAccent, active),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
