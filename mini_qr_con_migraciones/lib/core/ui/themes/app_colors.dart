import 'package:flutter/material.dart';

/// Paleta de colores centralizada (tema "Cálido" del diseño 2026).
abstract final class AppColors {
  // Fondos
  static const background = Color(0xFFEAE4DA); // crema, fondo de todo
  static const surface = Color(0xFFFFFFFF); // tarjetas, carrito, modales
  static const surfaceAlt = Color(0xFFF1ECE4); // chips, teclas
  static const surfaceDark = Color(0xFFE2DACD); // crema más oscuro

  // Bordes
  static const border = Color(0xFFC9BFAE);
  static const borderMuted = Color(0xFFA89C89);
  static const borderLight = Color(0xFF8A7F6E);

  // Textos (de más fuerte a más suave)
  static const textPrimary = Color(0xFF241E17);
  static const textLabel = Color(0xFF3A3229);
  static const textSecondary = Color(0xFF51483C);
  static const textCaption = Color(0xFF7A6F60);
  static const textMuted = Color(0xFF8A7F70);
  static const textDisabled = Color(0xFFB5AB9C);

  // Acento = café oscuro (botones, pestaña activa, − / +)
  static const accent = Color(0xFF241E17);
  static const accentSubtle = Color(0x1F241E17);
  static const accentGlow = Color(0x33241E17);
  static const onAccent = Color(0xFFFFFFFF); // texto sobre accent

  // Estados
  static const error = Color(0xFFC62828);
  static const warning = Color(0xFFA34A00); // total en Bs
  static const success = Color(0xFF2E7D32);
  static const cancelled = Color(0xFF5C564E);

  // Nuevos del diseño
  static const featured = Color(0xFF1F2023); // tarjeta del destacado
  static const brandRed = Color(0xFFC71012); // PAGAR, "MEGACENTER"
  static const faceBg =
      Color(0xFF000000); // recuadro de la cara = fondo de los GIF
}
