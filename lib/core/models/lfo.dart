// lib/core/models/lfo.dart
import 'dart:math' as math;

import 'lfo_curve_math.dart';

/// Waveform types.
/// Note: the visual editor can still be curve-mode while the "wave" enum is kept for quick presets.
enum LfoWave { sine, triangle, sawUp, sawDown, square, random, curve }

extension LfoWaveX on LfoWave {
  String get label {
    switch (this) {
      case LfoWave.sine:
        return 'Sine';
      case LfoWave.triangle:
        return 'Triangle';
      case LfoWave.sawUp:
        return 'Saw Up';
      case LfoWave.sawDown:
        return 'Saw Down';
      case LfoWave.square:
        return 'Square';
      case LfoWave.random:
        return 'Random';
      case LfoWave.curve:
        return 'Curve';
    }
  }
}

/// How the curve is interpreted visually (your editor supports these).
enum LfoCurveMode { bulge, bend }

/// Shape source for the LFO output.
enum LfoShapeMode { wave, curve }

/// A control point in the breakpoint curve.
/// x: 0..1
/// y: -1..1
///
/// Handle params:
/// - bias: 0..1 (segment-local x position of handle)
/// - bulgeAmt: -2.5..2.5 (matches your old core range; editor may normalize)
/// - bendY: -1..1 (bend mode vertical influence)
class LfoNode {
  final double x;
  final double y;

  final double bias;
  final double bulgeAmt;
  final double bendY;

  const LfoNode(
    this.x,
    this.y, {
    this.bias = 0.5,
    this.bulgeAmt = 0.0,
    this.bendY = 0.0,
  });

  LfoNode copyWith({
    double? x,
    double? y,
    double? bias,
    double? bulgeAmt,
    double? bendY,
  }) {
    return LfoNode(
      x ?? this.x,
      y ?? this.y,
      bias: bias ?? this.bias,
      bulgeAmt: bulgeAmt ?? this.bulgeAmt,
      bendY: bendY ?? this.bendY,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'bias': bias,
        'bulgeAmt': bulgeAmt,
        'bendY': bendY,
      };

  static double _asDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return fallback;
  }

  factory LfoNode.fromJson(Map<String, dynamic> j) {
    return LfoNode(
      _asDouble(j['x'], 0.0),
      _asDouble(j['y'], 0.0),
      bias: _asDouble(j['bias'], 0.5),
      bulgeAmt: _asDouble(j['bulgeAmt'], 0.0),
      bendY: _asDouble(j['bendY'], 0.0),
    );
  }
}

class Lfo {
  final String id;
  final String name;
  final bool enabled;

  final LfoWave wave;

  /// Cycles per second.
  final double rateHz;

  /// 0..1
  final double phase;

  /// -1..1
  final double offset;

  /// Curve settings
  final LfoShapeMode shapeMode;
  final LfoCurveMode curveMode;

  /// Breakpoint curve nodes (sorted by x).
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
    this.curveMode = LfoCurveMode.bulge,
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
    LfoCurveMode? curveMode,
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
      curveMode: curveMode ?? this.curveMode,
      nodes: nodes ?? this.nodes,
    );
  }

  // ---------------------------------------------------------------------------
  // Eval
  // ---------------------------------------------------------------------------

  /// Output in [-1..1] (then offset applied & clamped).
  double eval(double timeSec) {
    if (!enabled) return 0.0;

    final hz = rateHz.abs() < 0.000001 ? 0.0 : rateHz;
    final t = (timeSec * hz) + phase; // cycles
    final frac = t - t.floorToDouble(); // 0..1

    double out;

    final wantsCurve =
        (shapeMode == LfoShapeMode.curve || wave == LfoWave.curve);

    // ✅ CRITICAL FIX:
    // If we're in curve mode but nodes are empty (can happen on load/seed timing),
    // fall back to wave evaluation so the LFO still moves.
    if (wantsCurve) {
      if (nodes.isEmpty) {
        out = _evalWave(frac, (wave == LfoWave.curve) ? LfoWave.sine : wave);
      } else {
        out = _evalCurve(frac);
      }
    } else {
      out = _evalWave(frac, wave);
    }

    out = (out + offset).clamp(-1.0, 1.0).toDouble();
    return out;
  }

  double _evalWave(double x01, LfoWave w) {
    final x = x01.clamp(0.0, 1.0).toDouble();

    switch (w) {
      case LfoWave.sine:
        return math.sin(x * 2.0 * math.pi);
      case LfoWave.triangle:
        // 0..1 -> -1..1 triangle
        final v = (x < 0.5) ? (x * 2.0) : (2.0 - x * 2.0);
        return (v * 2.0) - 1.0;
      case LfoWave.sawUp:
        return (x * 2.0) - 1.0;
      case LfoWave.sawDown:
        return ((1.0 - x) * 2.0) - 1.0;
      case LfoWave.square:
        return (x < 0.5) ? 1.0 : -1.0;
      case LfoWave.random:
        // Deterministic-ish pseudo random based on x
        final s = math.sin((x * 999.0) * 12.9898) * 43758.5453;
        final r = s - s.floorToDouble(); // 0..1
        return (r * 2.0) - 1.0;
      case LfoWave.curve:
        // If someone calls this directly, keep behaviour: curve if possible, else 0.
        return nodes.isEmpty ? 0.0 : _evalCurve(x);
    }
  }

  double _evalCurve(double x01) {
    // nodes are guaranteed non-empty by eval() fallback,
    // but keep this guard anyway.
    if (nodes.isEmpty) return 0.0;

    // Ensure nodes sorted (they should already be sorted on load)
    // but do a cheap check if you want:
    // final pts = [...nodes]..sort((a,b)=>a.x.compareTo(b.x));

    return LfoCurveMath.eval01(
      x01: x01,
      nodes: nodes,
      curveMode: curveMode,
    );
  }

  double _bulge(LfoNode a, LfoNode b, double t, double yLin) {
    final bias = a.bias.clamp(0.05, 0.95).toDouble();
    final amt = a.bulgeAmt.clamp(-2.5, 2.5).toDouble();
    if (amt.abs() < 1e-6) return yLin.clamp(-1.0, 1.0).toDouble();

    double bulge01(double tt) {
      tt = tt.clamp(0.0, 1.0);
      if (tt <= bias) {
        final u = tt / bias;
        return math.sin(u * math.pi * 0.5);
      } else {
        final u = (1.0 - tt) / (1.0 - bias);
        return math.sin(u * math.pi * 0.5);
      }
    }

    // editor math, BUT in shared y-space (-1..1)
    // yLin is already in -1..1, so subtract in that same scale.
    final y = yLin - (amt * 0.45) * bulge01(t);
    return y.clamp(-1.0, 1.0).toDouble();
  }

  double _bend(LfoNode a, LfoNode b, double t, double yLin) {
    final bias = a.bias.clamp(0.0, 1.0).toDouble();
    final bendY = a.bendY.clamp(-1.0, 1.0).toDouble();

    if (bendY.abs() < 1e-6) return yLin.clamp(-1.0, 1.0).toDouble();

    // Bias the curve's "time" locally
    final tb = _bias(t, bias);

    // Then bend vertically but clamp between endpoints
    final y = _lerp(a.y, b.y, tb) + (bendY * 0.35);
    final lo = math.min(a.y, b.y);
    final hi = math.max(a.y, b.y);
    return y.clamp(lo, hi).clamp(-1.0, 1.0).toDouble();
  }

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'wave': wave.name,
        'rateHz': rateHz,
        'phase': phase,
        'offset': offset,
        'shapeMode': shapeMode.name,
        'curveMode': curveMode.name,
        'nodes': nodes.map((n) => n.toJson()).toList(),
      };

  static double _asDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return fallback;
  }

  static bool _asBool(dynamic v, bool fallback) {
    if (v is bool) return v;
    return fallback;
  }

  static String _asString(dynamic v, String fallback) {
    if (v is String) return v;
    return fallback;
  }

  static T _enumByName<T extends Enum>(
      List<T> values, String name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  factory Lfo.fromJson(Map<String, dynamic> j) {
    final nodesJson = j['nodes'];
    final nodes = <LfoNode>[];
    if (nodesJson is List) {
      for (final it in nodesJson) {
        if (it is Map<String, dynamic>) {
          nodes.add(LfoNode.fromJson(it));
        } else if (it is Map) {
          nodes.add(LfoNode.fromJson(Map<String, dynamic>.from(it)));
        }
      }
    }

    nodes.sort((a, b) => a.x.compareTo(b.x));

    return Lfo(
      id: _asString(j['id'], ''),
      name: _asString(j['name'], 'LFO'),
      enabled: _asBool(j['enabled'], true),
      wave: _enumByName(
          LfoWave.values, _asString(j['wave'], 'sine'), LfoWave.sine),
      rateHz: _asDouble(j['rateHz'], 0.25),
      phase: _asDouble(j['phase'], 0.0).clamp(0.0, 1.0).toDouble(),
      offset: _asDouble(j['offset'], 0.0).clamp(-1.0, 1.0).toDouble(),
      shapeMode: _enumByName(
        LfoShapeMode.values,
        _asString(j['shapeMode'], 'wave'),
        LfoShapeMode.wave,
      ),
      curveMode: _enumByName(
        LfoCurveMode.values,
        _asString(j['curveMode'], 'bulge'),
        LfoCurveMode.bulge,
      ),
      nodes: nodes,
    );
  }
}

// ---------------------------------------------------------------------------
// Small math helpers (no dart:ui dependencies)
// ---------------------------------------------------------------------------

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Bias function: bias=0.5 keeps linear. <0.5 pushes early, >0.5 pushes late.
double _bias(double t, double bias) {
  final b = bias.clamp(0.000001, 0.999999).toDouble();
  final k = math.log(b) / math.log(0.5);
  return math.pow(t, k).toDouble().clamp(0.0, 1.0);
}

/// Smooth bump in [0..1] with peak at `center` and 0 at ends.
double _bump(double t, double center) {
  final c = center.clamp(0.0, 1.0).toDouble();
  // Two smoothsteps stitched together
  if (t <= c) {
    final u = (c <= 1e-9) ? 0.0 : (t / c);
    return _smoothstep(u);
  } else {
    final denom = (1.0 - c);
    final u = (denom <= 1e-9) ? 0.0 : ((1.0 - t) / denom);
    return _smoothstep(u);
  }
}

double _smoothstep(double t) {
  final x = t.clamp(0.0, 1.0).toDouble();
  return x * x * (3.0 - 2.0 * x);
}
