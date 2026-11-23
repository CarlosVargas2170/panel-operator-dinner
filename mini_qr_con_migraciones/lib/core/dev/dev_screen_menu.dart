import 'package:flutter/material.dart';

/// Pantallas a las que se puede saltar desde el menú de desarrollo (F9).
enum DevScreen {
  idle('01 · Reposo', 'Inicio'),
  attract('02 · Cara del robot', 'Inicio'),
  merchantPicker('03 · Elige restaurante', 'Menú'),
  catalog('03a · Catálogo', 'Menú'),
  loading('05 · Cargando', 'Estados'),
  loadError('06 · Error de carga', 'Estados'),
  noProducts('07 · Sin productos', 'Estados'),
  order('03c · Tu pedido', 'Pago'),
  qrLoading('14 · Generando QR', 'Pago'),
  qrReady('15 · QR + cuenta atrás', 'Pago'),
  paySuccess('16 · Pago exitoso', 'Pago'),
  payFailed('17 · Pago fallido', 'Pago'),
  payCancelled('18 · Pago cancelado', 'Pago');

  final String label;
  final String group;
  const DevScreen(this.label, this.group);
}

/// Panel con la lista de pantallas. Solo se dibuja en debug (ver DevShortcuts).
class DevScreenMenu extends StatelessWidget {
  final ValueChanged<DevScreen> onSelect;
  final VoidCallback onClose;

  const DevScreenMenu({
    super.key,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DevScreen>>{};
    for (final s in DevScreen.values) {
      groups.putIfAbsent(s.group, () => []).add(s);
    }

    return Material(
      color: Colors.white,
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'DEV · Pantallas (F9)',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                for (final screen in entry.value)
                  InkWell(
                    key: ValueKey('dev-screen-${screen.name}'),
                    onTap: () => onSelect(screen),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(screen.label,
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
