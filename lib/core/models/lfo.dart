// lib/core/models/lfo.dart
import 'dart:math' as math;

/// Built-in oscillator waves (your current behavior).
enum LfoWave { sine, triangle, sawUp, sawDown, square }

extension LfoWaveLabel on LfoWave {
  String get label {
    // IMPORTANT:
    // Replace the case names below to EXACTLY match your enum values.
    switch (this) {
      case LfoWave.sine:
        return 'Sine';
      case LfoWave.triangle:
        return 'Triangle';
      case LfoWave.sawUp:
        return 'Saw ↑';
      case LfoWave.sawDown:
        return 'Saw ↓';
      case LfoWave.square:
        return 'Square';
    }
  }
}

/// Shape mode:
/// - wave: classic oscillator
/// - curve: Vital-style node curve (0..1 -> -1..1)
enum LfoShapeMode { wave, curve }

class LfoNode {
  /// Normalized x in [0..1]
  final double x;

  /// Normalized y in [-1..1]
  final double y;

  const LfoNode(this.x, this.y);

  LfoNode copyWith({double? x, double? y}) => LfoNode(x ?? this.x, y ?? this.y);
}

class LfoRoute {
  final String id;
  final String lfoId;
  final String layerId;

  /// If null => layer-level route.
  /// If not null => stroke-level route.
  final String? strokeId;

  final bool enabled;
  final LfoParam param;

  /// If true: shaped signal is [-1..1].
  /// If false: shaped signal is [0..1].
  final bool bipolar;

  /// Generic amount:
  /// - rotation: degrees
  /// - x/y: pixels
  /// - scale: delta multiplier
  /// - visual params: depth (-1..1)
  final double amount;

  const LfoRoute({
    required this.id,
    required this.lfoId,
    required this.layerId,
    this.strokeId,
    required this.enabled,
    required this.param,
    required this.bipolar,
    required this.amount,
  });

  bool get isStrokeTarget => strokeId != null;

  LfoRoute copyWith({
    String? id,
    String? lfoId,
    String? layerId,
    String? strokeId,
    bool? enabled,
    LfoParam? param,
    bool? bipolar,
    double? amount,
  }) {
    return LfoRoute(
      id: id ?? this.id,
      lfoId: lfoId ?? this.lfoId,
      layerId: layerId ?? this.layerId,
      strokeId: strokeId ?? this.strokeId,
      enabled: enabled ?? this.enabled,
      param: param ?? this.param,
      bipolar: bipolar ?? this.bipolar,
      amount: amount ?? this.amount,
    );
  }
}

/// IMPORTANT: This enum must match what your controller expects.
/// If you already have LfoParam elsewhere, delete this and import yours.
enum LfoParam {
  // layer
  layerRotationDeg,
  layerX,
  layerY,
  layerScale,
  layerOpacity,

  // stroke transform
  strokeX,
  strokeY,
  strokeRotationDeg,

  // stroke size
  strokeSize,

  // stroke visuals (0..1)
  strokeCoreOpacity,
  strokeGlowRadius,
  strokeGlowOpacity,
  strokeGlowBrightness,
}

/// LFO model:
/// - When shapeMode == wave => same math as before.
/// - When shapeMode == curve => evaluate by sampling node curve (Vital-ish).
class Lfo {
  final String id;
  final String name;
  final bool enabled;

  final LfoWave wave;
  final double rateHz;

  /// Phase offset in [0..1] (0 = start)
  final double phase;

  /// Additive output offset in [-1..1]
  final double offset;

  /// ✅ NEW: curve mode for the visual editor.
  final LfoShapeMode shapeMode;

  /// ✅ NEW: nodes for curve mode.
  /// x in [0..1], y in [-1..1], sorted by x.
  final List<LfoNode> nodes;

  const Lfo({
    required this.id,
    required this.name,
    required this.enabled,
    required this.wave,
    required this.rateHz,
    required this.phase,
    required this.offset,
    this.shapeMode = LfoShapeMode.wave,
    this.nodes = const [],
  });

  Lfo copyWith({
    String? id,
    String? name,
    bool? enabled,
    LfoWave? wave,
    double? rateHz,
    double? phase,
    double? offset,
    LfoShapeMode? shapeMode,
    List<LfoNode>? nodes,
  }) {
    return Lfo(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      wave: wave ?? this.wave,
      rateHz: rateHz ?? this.rateHz,
      phase: phase ?? this.phase,
      offset: offset ?? this.offset,
      shapeMode: shapeMode ?? this.shapeMode,
      nodes: nodes ?? this.nodes,
    );
  }

  /// Evaluate output in [-1..1].
  double eval(double timeSec) {
    if (!enabled) return 0.0;

    final hz = rateHz <= 0 ? 0.0 : rateHz;
    final baseT = (hz == 0.0) ? 0.0 : (timeSec * hz);

    // Apply phase (normalized)
    double t01 = (baseT + phase).remainder(1.0);
    if (t01 < 0) t01 += 1.0;

    double out;
    if (shapeMode == LfoShapeMode.curve) {
      out = _evalCurve(t01);
    } else {
      out = _evalWave(t01);
    }

    // offset (additive) + clamp
    out = (out + offset).clamp(-1.0, 1.0).toDouble();
    return out;
  }

  double _evalWave(double t01) {
    switch (wave) {
      case LfoWave.sine:
        return math.sin(t01 * math.pi * 2.0);
      case LfoWave.triangle:
        // triangle in [-1..1]
        final v = (t01 * 4.0);
        if (v < 1.0) return v;
        if (v < 3.0) return 2.0 - v;
        return v - 4.0;
      case LfoWave.sawUp:
        return (t01 * 2.0) - 1.0;
      case LfoWave.sawDown:
        return 1.0 - (t01 * 2.0);
      case LfoWave.square:
        return (t01 < 0.5) ? 1.0 : -1.0;
    }
  }

  /// Vital-ish curve sampling:
  /// - nodes define y at x
  /// - we do smooth interpolation (Catmull-Rom style) for "curvy" feel
  /// - curve loops: we treat x=0 and x=1 as connected
  double _evalCurve(double t01) {
    final n = nodes;
    if (n.isEmpty) {
      // fallback to sine if no nodes exist
      return math.sin(t01 * math.pi * 2.0);
    }
    if (n.length == 1) return n.first.y.clamp(-1.0, 1.0).toDouble();

    // Ensure sorted copy (defensive)
    final pts = List<LfoNode>.from(n)..sort((a, b) => a.x.compareTo(b.x));

    // Find segment [i..i+1] that contains t01
    int i1 = 0;
    while (i1 < pts.length && pts[i1].x < t01) {
      i1++;
    }

    // Wrap segments for loop:
    // If t is before first point or after last, segment crosses boundary.
    if (i1 == 0) {
      // between last -> first across wrap
      final a = pts.last;
      final b = pts.first.copyWith(x: pts.first.x + 1.0);
      return _catmullSegment(pts, a, b, t01 + 1.0);
    }
    if (i1 >= pts.length) {
      // between last -> first
      final a = pts.last;
      final b = pts.first.copyWith(x: pts.first.x + 1.0);
      return _catmullSegment(pts, a, b, t01 + 1.0);
    }

    final a = pts[i1 - 1];
    final b = pts[i1];

    return _catmullSegment(pts, a, b, t01);
  }

  double _catmullSegment(List<LfoNode> pts, LfoNode a, LfoNode b, double t) {
    // Local u in [0..1]
    final dx = (b.x - a.x);
    if (dx.abs() < 1e-9) return a.y.clamp(-1.0, 1.0).toDouble();
    final u = ((t - a.x) / dx).clamp(0.0, 1.0).toDouble();

    // For Catmull-Rom we need p0,p1,p2,p3:
    // p1=a, p2=b, p0=prev(a), p3=next(b), with wrap.
    LfoNode p1 = a;
    LfoNode p2 = b;

    LfoNode p0 = _prevPoint(pts, a);
    LfoNode p3 = _nextPoint(pts, b);

    // Convert into scalar y values; x spacing varies so we still do a
    // standard Catmull-Rom on y only (good enough for editor feel).
    final y0 = p0.y;
    final y1 = p1.y;
    final y2 = p2.y;
    final y3 = p3.y;

    // Catmull-Rom spline (uniform)
    final u2 = u * u;
    final u3 = u2 * u;

    final y = 0.5 *
        ((2.0 * y1) +
            (-y0 + y2) * u +
            (2.0 * y0 - 5.0 * y1 + 4.0 * y2 - y3) * u2 +
            (-y0 + 3.0 * y1 - 3.0 * y2 + y3) * u3);

    return y.clamp(-1.0, 1.0).toDouble();
  }

  LfoNode _prevPoint(List<LfoNode> pts, LfoNode p) {
    // find exact by x/y match in sorted list
    final i = pts.indexWhere((x) => x.x == p.x && x.y == p.y);
    if (i <= 0) {
      // wrap to last, but shift x -1 so continuity works conceptually
      final last = pts.last;
      return last.copyWith(x: last.x - 1.0);
    }
    return pts[i - 1];
  }

  LfoNode _nextPoint(List<LfoNode> pts, LfoNode p) {
    final i = pts.indexWhere((x) => x.x == p.x && x.y == p.y);
    if (i < 0 || i >= pts.length - 1) {
      // wrap to first, shift x +1
      final first = pts.first;
      return first.copyWith(x: first.x + 1.0);
    }
    return pts[i + 1];
  }
}
