import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/audio_service.dart';
import '../services/ui_command_bus.dart';
import 'dev_screen_menu.dart';

/// Atajos de teclado SOLO para desarrollo (simulan los comandos del robot).
///
/// En builds release/profile ([kDebugMode] == false) este widget devuelve
/// [child] sin cambios: no registra teclas ni dibuja nada.
///
/// | Tecla | Equivale a              | Efecto                          |
/// |-------|-------------------------|---------------------------------|
/// | F1    | POST /greet             | Catálogo + saludo con audio     |
/// | F2    | POST /product           | Catálogo sin audio              |
/// | F3    | POST /proximity/near    | Cara del robot (atracción)      |
/// | F4    | POST /proximity/away    | Reposo "Esperando..."           |
/// | F5    | POST /cancel-payment    | Cancela el pago QR abierto      |
/// | F12   | —                       | Muestra/oculta la ayuda en pantalla |
class DevShortcuts extends StatefulWidget {
  final Widget child;

  const DevShortcuts({super.key, required this.child});

  /// Atajo de toque: en debug, tocar la cara del robot o "Esperando..."
  /// abre el catálogo (equivale a F2). En release no hace nada.
  static void onIdleOrAttractTap() {
    if (!kDebugMode) return;
    debugPrint('[DevShortcuts] Toque en pantalla -> ShowProductResetCarousel');
    UiCommandBus.emit(const ShowProductResetCarousel());
  }

  @override
  State<DevShortcuts> createState() => _DevShortcutsState();
}

class _DevShortcutsState extends State<DevShortcuts> {
  bool _showHelp = true;

  /// F9: menú de pantallas.
  bool _showMenu = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (kDebugMode) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.f1) {
      _log('F1 -> /greet');
      UiCommandBus.emit(const ShowProductResetCarousel());
      AudioService.setRemoteCall(true);
      AudioService.playQuestion();
    } else if (key == LogicalKeyboardKey.f2) {
      _log('F2 -> /product');
      UiCommandBus.emit(const ShowProduct());
    } else if (key == LogicalKeyboardKey.f3) {
      _log('F3 -> /proximity/near');
      UiCommandBus.emit(const ShowAttract());
    } else if (key == LogicalKeyboardKey.f4) {
      _log('F4 -> /proximity/away');
      UiCommandBus.emit(const ShowIdle());
    } else if (key == LogicalKeyboardKey.f5) {
      _log('F5 -> /cancel-payment');
      UiCommandBus.emit(const CancelPayment());
    } else if (key == LogicalKeyboardKey.f9) {
      setState(() => _showMenu = !_showMenu);
    } else if (key == LogicalKeyboardKey.f12) {
      setState(() => _showHelp = !_showHelp);
    } else {
      return false;
    }
    return true;
  }

  void _log(String msg) => debugPrint('[DevShortcuts] $msg');

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_showHelp)
          const Positioned(
            left: 8,
            top: 8,
            child: IgnorePointer(child: _DevHelpChip()),
          ),
        if (_showMenu)
          Positioned(
            left: 8,
            top: 44,
            child: DevScreenMenu(
              onClose: () => setState(() => _showMenu = false),
              onSelect: (screen) {
                _log('F9 -> ${screen.label}');
                setState(() => _showMenu = false);
                UiCommandBus.emit(DevPreviewScreen(screen));
              },
            ),
          ),
      ],
    );
  }
}

class _DevHelpChip extends StatelessWidget {
  const _DevHelpChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x55FF9800)),
      ),
      child: const Text(
        'DEV  F1 saludo · F2 catálogo · F3 cara · F4 reposo · '
        'F5 cancelar pago · F9 pantallas · clic en la cara = catálogo · F12 ocultar',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: Color(0xFFFF9800),
          fontSize: 11,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
