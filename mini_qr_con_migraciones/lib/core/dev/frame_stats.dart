import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Medidor de fluidez (solo desarrollo). Se activa con
/// `flutter run --profile --dart-define=FRAME_STATS=true`.
///
/// Agrupa los cuadros en "ráfagas" (una animación o transición: cuadros
/// seguidos sin pausa de más de 250 ms) y al terminar cada una escribe:
///
/// ```
/// [FRAMES] 41 cuadros en 690 ms · lentos(>16,7 ms) 2 · build máx 9,1 ms · raster máx 21,3 ms (prom 4,2) · salteados 1 · hueco máx 33,3 ms
/// ```
///
/// "lentos" son los cuadros cuyo TRABAJO (build + raster) pasó de un
/// refresco de 60 Hz: los que se ven como tirón. No se usa el tiempo total
/// del cuadro porque incluye esperas del sistema (p. ej. Windows espacia el
/// dibujo de una ventana tapada). En profile/release conviene que sean 0.
abstract final class FrameStats {
  static const enabled = bool.fromEnvironment('FRAME_STATS');

  static const _gap = Duration(milliseconds: 250);
  static const _budgetUs = 16667; // 60 Hz

  static final List<FrameTiming> _burst = [];
  static DateTime? _lastFrame;

  static void startIfEnabled() {
    if (!enabled) return;
    debugPrint('[FRAMES] medidor activo');
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    final last = _lastFrame;
    // Los cuadros llegan en lotes (~cada 100 ms); si pasó una pausa larga
    // desde el lote anterior, la ráfaga anterior ya terminó.
    if (last != null && now.difference(last) > _gap * 2) _flush();
    // Cada cuadro lento, con la hora (para saber en qué transición pasó).
    for (final f in timings) {
      if (_work(f) > _budgetUs) {
        final t = now.toIso8601String().substring(11, 23);
        debugPrint('[FRAME-LENTO] $t · build '
            '${(f.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} ms · '
            'raster ${(f.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)} ms');
      }
    }
    _burst.addAll(timings);
    _lastFrame = now;
    Future<void>.delayed(_gap * 2, () {
      final l = _lastFrame;
      if (l != null && DateTime.now().difference(l) >= _gap * 2) _flush();
    });
  }

  static int _work(FrameTiming f) =>
      f.buildDuration.inMicroseconds + f.rasterDuration.inMicroseconds;

  static void _flush() {
    if (_burst.isEmpty) return;
    final frames = List.of(_burst);
    _burst.clear();
    if (frames.length < 3) return; // un cuadro suelto no es animación

    int us(Duration d) => d.inMicroseconds;
    final first = frames.first.timestampInMicroseconds(FramePhase.vsyncStart);
    final end = frames.last.timestampInMicroseconds(FramePhase.rasterFinish);
    final slow = frames.where((f) => _work(f) > _budgetUs).length;
    final build = frames.map((f) => us(f.buildDuration)).reduce(math.max);
    final raster = frames.map((f) => us(f.rasterDuration)).reduce(math.max);
    final avgRaster =
        frames.map((f) => us(f.rasterDuration)).reduce((a, b) => a + b) /
            frames.length;
    String ms(num v) => (v / 1000).toStringAsFixed(1);
    // Ritmo (§ 8.37): separación entre el inicio de cuadros seguidos. Si
    // algún hueco pasa de 1,5 refrescos, ese cuadro se salteó y el movimiento
    // da un saltito aunque ningún cuadro haya sido "lento".
    var gapMax = 0;
    var skipped = 0;
    for (var i = 1; i < frames.length; i++) {
      final gap = frames[i].timestampInMicroseconds(FramePhase.vsyncStart) -
          frames[i - 1].timestampInMicroseconds(FramePhase.vsyncStart);
      gapMax = math.max(gapMax, gap);
      if (gap > _budgetUs * 1.5) skipped++;
    }
    debugPrint('[FRAMES] ${frames.length} cuadros en ${ms(end - first)} ms · '
        'lentos(>16,7 ms) $slow · build máx ${ms(build)} ms · '
        'raster máx ${ms(raster)} ms (prom ${ms(avgRaster)}) · '
        'salteados $skipped · hueco máx ${ms(gapMax)} ms');
  }
}
