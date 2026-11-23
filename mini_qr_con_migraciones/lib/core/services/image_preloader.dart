import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../config/app_settings.dart';

/// Ancho máximo (px) al que se DECODIFICAN las fotos de red (fase 8, § 8.19).
///
/// Algunas fotos de producto vienen de 6250 × 6250 px: decodificadas ocupaban
/// ~156 MB cada una (no entraban en el caché de 100 MB de Flutter, se volvían
/// a decodificar cada vez y llegaban tarde). En pantalla se dibujan a ~400 px
/// (la tarjeta destacada, ~770 px), así que 800 alcanza y cada foto queda en
/// ~2,5 MB. Las fotos más chicas se decodifican a su tamaño (no se agrandan).
const kImageDecodeWidth = 800;

/// La MISMA foto (misma clave de caché) que dibuja `AppImage`: la usan la
/// medición de `AdaptiveProductImage` y la precarga, para que las tres
/// compartan la foto ya decodificada.
ImageProvider<Object> productImageProvider(String url) =>
    ResizeImage.resizeIfNeeded(
      kImageDecodeWidth,
      null,
      AppSettings().enableImageCache
          ? CachedNetworkImageProvider(url) as ImageProvider<Object>
          : NetworkImage(url),
    );

/// Precarga de fotos de productos (fase 8, § 8.19; punto R1 de
/// PROPUESTA_RENDIMIENTO.md).
///
/// Descarga y decodifica las fotos ANTES de que se vean, con el mismo
/// proveedor que usan las tarjetas (`productImageProvider(url)`), así
/// que al llegar a una página del catálogo las fotos ya están en memoria y
/// aparecen con la página (antes la página entraba con los cuadros de foto
/// vacíos y se llenaban después).
abstract final class ImagePreloader {
  /// URLs ya pedidas en esta sesión (no se piden dos veces).
  static final Set<String> _requested = {};

  /// Precarga [urls] de a [concurrency] a la vez (para no saturar la red del
  /// robot). Errores de red se ignoran: la tarjeta lo volverá a intentar.
  static Future<void> preload(
    BuildContext context,
    Iterable<String> urls, {
    int concurrency = 4,
  }) async {
    final pending = urls
        .where((u) => u.isNotEmpty && _requested.add(u))
        .toList(growable: false);
    if (pending.isEmpty) return;

    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        final url = pending[next++];
        if (!context.mounted) return;
        // La misma clave que dibuja la tarjeta (foto reducida, § 8.19).
        final provider = productImageProvider(url);
        try {
          await precacheImage(provider, context, onError: (_, __) {});
        } catch (_) {
          // Ignorado: la tarjeta reintenta al mostrarse.
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < pending.length; i++) worker(),
    ]);
  }

  /// Solo tests: olvidar lo ya pedido.
  @visibleForTesting
  static void reset() => _requested.clear();
}
