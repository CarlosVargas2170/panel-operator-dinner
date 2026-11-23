import 'dart:convert';
import 'package:flutter/material.dart';

/// Widget que renderiza una imagen QR desde base64, URL o muestra un fallback.
///
/// La pantalla de pago se redibuja cada segundo (cuentas "VENCE EN" y
/// "Cancelar en N s"). Antes, en cada redibujo se decodificaba el base64 de
/// nuevo y `Image.memory` recibía bytes nuevos: Flutter lo tomaba como otra
/// imagen, la descartaba y la volvía a cargar → el QR parpadeaba cada
/// segundo. Ahora la imagen se arma UNA vez por cada QR distinto.
class QrImageWidget extends StatefulWidget {
  final String? qrBase64;
  const QrImageWidget({super.key, this.qrBase64});

  @override
  State<QrImageWidget> createState() => _QrImageWidgetState();
}

class _QrImageWidgetState extends State<QrImageWidget> {
  /// Imagen del QR actual (null = cargando o inválido).
  ImageProvider? _image;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(QrImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo si llegó OTRO QR (p. ej. REINTENTAR).
    if (oldWidget.qrBase64 != widget.qrBase64) _decode();
  }

  void _decode() {
    final qr = widget.qrBase64;
    _image = null;
    _invalid = false;
    if (qr == null || qr.isEmpty) return;
    if (qr.startsWith('http')) {
      _image = NetworkImage(qr);
      return;
    }
    try {
      final raw = qr.contains(',') ? qr.split(',').last : qr;
      _image = MemoryImage(base64Decode(raw));
    } catch (_) {
      _invalid = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (_invalid) return const _Fallback();
    if (image == null) return const _Loading();

    return Image(
      image: image,
      fit: BoxFit.contain,
      // Si cambia el QR, se queda el anterior hasta que el nuevo esté listo.
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _Loading(),
      errorBuilder: (context, error, stackTrace) => const _Fallback(),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.black45, strokeWidth: 3),
          SizedBox(height: 16),
          Text(
            'Generando QR...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2_rounded, color: Colors.black54, size: 80),
          SizedBox(height: 8),
          Text(
            'QR no disponible',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
