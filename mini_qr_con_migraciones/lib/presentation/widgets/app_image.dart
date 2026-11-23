import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/config/app_settings.dart';
import '../../core/services/image_preloader.dart';

/// Widget que muestra una imagen de red con cache opcional.
/// Si [AppSettings.enableImageCache] es true usa [CachedNetworkImage],
/// si es false usa [Image.network] estándar.
class AppImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// Ancho de decodificación. Por defecto [kImageDecodeWidth]; si se cambia,
  /// la foto ya no comparte caché con la precarga.
  final int? memCacheWidth;
  final int? memCacheHeight;

  const AppImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final decodeWidth = memCacheWidth ?? kImageDecodeWidth;
    if (AppSettings().enableImageCache) {
      // Sin `imageBuilder`: ese callback recibe la foto ORIGINAL (sin
      // reducir) y la volvía a decodificar a tamaño completo (§ 8.19).
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        memCacheWidth: decodeWidth,
        memCacheHeight: memCacheHeight,
        fadeInDuration: const Duration(milliseconds: 250),
        fadeInCurve: Curves.easeOutCubic,
        // Fase 8 (§ 8.16): sin log por cada pedazo descargado (en profile
        // se ejecutaba justo durante las transiciones).
        progressIndicatorBuilder: (context, url, progress) =>
            placeholder ?? const SizedBox.shrink(),
        errorWidget: errorWidget != null ? (_, __, ___) => errorWidget! : null,
      );
    }

    return Image.network(
      imageUrl,
      fit: fit,
      cacheWidth: decodeWidth,
      cacheHeight: memCacheHeight,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder ?? const SizedBox.shrink(),
      errorBuilder: errorWidget != null
          ? (context, error, stackTrace) => errorWidget!
          : null,
    );
  }
}
