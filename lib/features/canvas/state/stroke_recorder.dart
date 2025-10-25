import 'dart:ui';
import '../../../core/models/stroke.dart';
import '../../../core/utils/uuid.dart';

class StrokeRecorder {
  Stroke? _current;
  int _t0 = 0;

  Stroke? get current => _current;

  void begin(Offset pos, {required String brushId, required int color, required double size, required double glow}) {
    _t0 = DateTime.now().millisecondsSinceEpoch;
    _current = Stroke(
      id: simpleId(),
      brushId: brushId,
      color: color,
      size: size,
      glow: glow,
      seed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      points: [PointSample(pos.dx, pos.dy, 0)],
    );
  }

  void add(Offset pos) {
    final s = _current;
    if (s == null) return;
    final t = DateTime.now().millisecondsSinceEpoch - _t0;
    s.points.add(PointSample(pos.dx, pos.dy, t));
  }

  Stroke? end() {
    final s = _current;
    _current = null;
    return s;
  }
}
