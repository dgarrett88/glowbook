// lib/core/models/lfo_curve_math.dart
import 'dart:math' as math;

import 'lfo.dart'; // for LfoNode, LfoCurveMode

class LfoCurveMath {
  /// Evaluate the curve at x01 (0..1) returning y in [-1..1].
  static double eval01({
    required double x01,
    required List<LfoNode> nodes,
    required LfoCurveMode curveMode,
  }) {
    if (nodes.isEmpty) return 0.0;

    final x = x01.clamp(0.0, 1.0).toDouble();

    // Nodes should already be sorted by x; assume sorted for speed.
    final pts = nodes;

    if (x <= pts.first.x) return pts.first.y.clamp(-1.0, 1.0).toDouble();
    if (x >= pts.last.x) return pts.last.y.clamp(-1.0, 1.0).toDouble();

    int hi = 1;
    while (hi < pts.length && pts[hi].x < x) {
      hi++;
    }
    final lo = (hi - 1).clamp(0, pts.length - 2);

    final a = pts[lo];
    final b = pts[lo + 1];

    final ax = a.x;
    final bx = b.x;
    final span = (bx - ax).abs() < 1e-9 ? 1e-9 : (bx - ax);

    final t = ((x - ax) / span).clamp(0.0, 1.0).toDouble();
    final yLin = _lerp(a.y, b.y, t);

    switch (curveMode) {
      case LfoCurveMode.bulge:
        return _bulge(a, b, t, yLin);
      case LfoCurveMode.bend:
        return _bend(a, b, t, yLin);
    }
  }

  /// Convenience: generate samples to draw a path.
  static List<double> sampleYs({
    required int steps,
    required List<LfoNode> nodes,
    required LfoCurveMode curveMode,
  }) {
    final out = <double>[];
    if (steps <= 1) return out;

    for (int i = 0; i < steps; i++) {
      final x01 = i / (steps - 1);
      out.add(eval01(x01: x01, nodes: nodes, curveMode: curveMode));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Math helpers (keep identical behaviour)
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

double _bulge(LfoNode a, LfoNode b, double t, double yLin) {
  final amt = a.bulgeAmt.clamp(-2.5, 2.5).toDouble();
  if (amt.abs() < 1e-6) return yLin.clamp(-1.0, 1.0).toDouble();

  final bias = a.bias.clamp(0.0, 1.0).toDouble();
  final bump = _bump(t, bias);

  final y = yLin + (bump * (amt / 2.5));
  return y.clamp(-1.0, 1.0).toDouble();
}

double _bend(LfoNode a, LfoNode b, double t, double yLin) {
  final bias = a.bias.clamp(0.0, 1.0).toDouble();
  final bendY = a.bendY.clamp(-1.0, 1.0).toDouble();

  if (bendY.abs() < 1e-6) return yLin.clamp(-1.0, 1.0).toDouble();

  final tb = _bias(t, bias);

  final y = _lerp(a.y, b.y, tb) + (bendY * 0.35);
  final lo = math.min(a.y, b.y);
  final hi = math.max(a.y, b.y);
  return y.clamp(lo, hi).clamp(-1.0, 1.0).toDouble();
}
