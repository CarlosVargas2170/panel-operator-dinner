import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'product_filter_config.dart';

/// Configuracion de la app cargada en runtime.
///
/// Al iniciar, intenta leer valores previamente guardados en disco.
/// Si no existen, aplica los valores por defecto (fallback).
class AppSettings {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  String baseUrl = '';
  String bearerToken = '';
  String ecosystemBaseUrl = '';
  String ecosystemBearerToken = '';
  List<int> merchantIds = [];
  int productId = 0;
  bool enableImageCache = true;
  String baseUrlVpn = '';
  int portVpn = 0;

  /// Configuracion de visibilidad de merchants y productos.
  ProductFilterConfig filterConfig = ProductFilterConfig(
    filterMode: 'all',
  );

  /// Tiempo mínimo entre polls de productos (en segundos).
  /// Si el último poll fue hace menos de este tiempo, se omite.
  /// Default: 60 segundos.
  int productPollingStaleSeconds = 60;

  /// Cantidad maxima permitida de un mismo producto en el carrito.
  int maxCartItemQuantity = 10;

  /// Tiempo sin interaccion antes de iniciar una nueva sesion.
  int customerSessionTimeoutSeconds = 60;

  int get merchantId => merchantIds.isNotEmpty ? merchantIds.first : 0;
  static String customerName = dotenv.env['NAME_MESERO'] ?? 'Robot Mesero';
  static int qrExpirationMinutes =
      int.tryParse(dotenv.env['QR_EXPIRATION_MINUTES'] ?? '') ?? 3;

  bool get isConfigured =>
      baseUrl.isNotEmpty &&
      bearerToken.isNotEmpty &&
      merchantIds.isNotEmpty &&
      productId != 0;

  /// Carga la configuracion desde el archivo .env.
  /// El filterConfig siempre arranca limpio (filterMode: 'all').
  Future<void> load() async {
    applyFallback();
  }

  /// Lee `MERCHANT_IDS` ("53,54,90") sin romper la app por un error de
  /// tipeo: ignora partes vacías (coma final, ",,") y las que no son número,
  /// con aviso en el log. Sin la variable o sin ningún id válido usa el
  /// valor por defecto.
  ///
  /// Antes `int.parse` lanzaba `FormatException` con `MERCHANT_IDS=53,54,90,`
  /// y la app se cerraba al arrancar, sin mostrar nada.
  @visibleForTesting
  static List<int> parseMerchantIds(String? raw) {
    if (raw == null) return List.of(_Defaults.merchantIds);
    final ids = <int>[];
    for (final part in raw.split(',')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final id = int.tryParse(text);
      if (id == null) {
        debugPrint('[AppSettings] MERCHANT_IDS: "$text" no es un número, '
            'se ignora');
        continue;
      }
      if (!ids.contains(id)) ids.add(id);
    }
    if (ids.isEmpty) {
      debugPrint('[AppSettings] MERCHANT_IDS="$raw" sin ids válidos; '
          'se usa el valor por defecto ${_Defaults.merchantIds}');
      return List.of(_Defaults.merchantIds);
    }
    return ids;
  }

  void applyFallback() {
    baseUrl = dotenv.env['BASE_URL'] ?? _Defaults.baseUrl;
    bearerToken = dotenv.env['BEARER_TOKEN'] ?? _Defaults.bearerToken;
    ecosystemBaseUrl =
        dotenv.env['ECOSYSTEM_BASE_URL'] ?? _Defaults.ecosystemBaseUrl;
    ecosystemBearerToken =
        dotenv.env['ECOSYSTEM_BEARER_TOKEN'] ?? _Defaults.ecosystemBearerToken;
    merchantIds = parseMerchantIds(dotenv.env['MERCHANT_IDS']);
    productId =
        int.tryParse(dotenv.env['PRODUCT_ID'] ?? '') ?? _Defaults.productId;
    baseUrlVpn = dotenv.env['BASE_URL_VPN'] ?? _Defaults.baseUrlVpn;
    portVpn = int.tryParse(dotenv.env['PORT_VPN'] ?? '') ?? _Defaults.portVpn;
    productPollingStaleSeconds =
        int.tryParse(dotenv.env['PRODUCT_POLLING_STALE_SECONDS'] ?? '') ??
            _Defaults.productPollingStaleSeconds;
    final configuredMaxCartQuantity =
        int.tryParse(dotenv.env['MAX_CART_ITEM_QUANTITY'] ?? '');
    maxCartItemQuantity =
        configuredMaxCartQuantity != null && configuredMaxCartQuantity > 0
            ? configuredMaxCartQuantity
            : _Defaults.maxCartItemQuantity;
    final configuredSessionTimeout =
        int.tryParse(dotenv.env['CUSTOMER_SESSION_TIMEOUT_SECONDS'] ?? '');
    customerSessionTimeoutSeconds =
        configuredSessionTimeout != null && configuredSessionTimeout > 0
            ? configuredSessionTimeout
            : _Defaults.customerSessionTimeoutSeconds;
    enableImageCache = true;
    // Whitelist: solo mostrar los productos con estos IDs
    filterConfig = ProductFilterConfig(
      // pinnedProducts: {489150, 489161},
      filterMode: 'all',
    );
    if (kDebugMode) {
      debugPrint(
          '[AppSettings] Usando configuracion por defecto (fallback). Merchants: $merchantIds');
    }
  }
}

/// Valores por defecto cuando no hay config guardada.
abstract final class _Defaults {
  static const String baseUrl = 'https://api-totem.nexuspatiotech.com/api';
  static const String bearerToken = '';
  static const String ecosystemBaseUrl =
      'https://api-merchant.nexuspatiotech.com';
  static const String ecosystemBearerToken = '';
  static const List<int> merchantIds = [53];
  static const int productId = 457969;
  static const String baseUrlVpn = "100.99.244.72";
  static const int portVpn = 5050;
  static const int productPollingStaleSeconds = 60;
  static const int maxCartItemQuantity = 10;
  static const int customerSessionTimeoutSeconds = 60;
}
