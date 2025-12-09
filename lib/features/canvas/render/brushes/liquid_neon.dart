import 'dart:ui';
import 'dart:math' as math;

import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

/// LiquidNeonBrush
/// ----------------
/// Your ORIGINAL neon brush restored exactly as uploaded,
/// with ONLY the blend-mode & intensity system added back in.
class LiquidNeonBrush {
  final bool glowOverStroke;
  const LiquidNeonBrush({this.glowOverStroke = false});

  Path _buildPath(List<PointSample> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    return path;
  }

  List<PointSample> _mirrorV(List<PointSample> pts, Size sz) {
    final double cx = sz.width / 2.0;
    return pts
        .map((p) => PointSample(cx - (p.x - cx), p.y, p.t))
        .toList(growable: false);
  }

  List<PointSample> _mirrorH(List<PointSample> pts, Size sz) {
    final double cy = sz.height / 2.0;
    return pts
        .map((p) => PointSample(p.x, cy - (p.y - cy), p.t))
        .toList(growable: false);
  }

  void _drawGlowAndCore(Canvas canvas, Path path, Stroke s) {
    final double size = s.size;
    final Color base = Color(s.color);

    // ---------------- CORE ----------------
    final double coreStrength = s.coreOpacity.clamp(0.0, 1.0);
    final int coreAlpha = (255.0 * coreStrength).round();

    final Paint corePaint = Paint()
      ..color = base.withAlpha(coreAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ---------------- GLOW CONTROLS ----------------
    double r = s.glowRadius;
    if (r.isNaN) r = 0.6;
    r = r.clamp(0.0, 1.0);

    double b = s.glowBrightness;
    if (b.isNaN) b = 0.7;
    b = b.clamp(0.0, 1.0);

    // UI brightness 0–100
    final double uiBrightness = b * 100.0;
    const pivot = 70.0;

    double brightnessMul;
    if (uiBrightness <= 0) {
      brightnessMul = 0.0;
    } else {
      brightnessMul = (uiBrightness / pivot);
      brightnessMul *= 1.2;
    }

    double o = s.glowOpacity;
    if (o.isNaN) o = 1.0;
    o = o.clamp(0.0, 1.0);

    // ---------------- GLOBAL BLEND INTENSITY ----------------
    final double intensity = gb.GlowBlendState.I.intensity.clamp(0.0, 1.0);

    // If glow is zero: core only
    if (r <= 0 || o <= 0 || brightnessMul <= 0) {
      canvas.drawPath(path, corePaint);
      return;
    }

    // ---------------- GEOMETRY ----------------
    const double maxHaloThickness = 120.0;
    final double baseHalo = maxHaloThickness * r;

    const double kSizeRef = 24.0;
    final double sizeFactor = (size / kSizeRef).clamp(0.5, 4.0);

    final double halo =
        s.glowRadiusScalesWithSize ? baseHalo * sizeFactor : baseHalo;

    final double glowWidth = size + halo;
    final double sigma = 0.3 * size + 0.7 * halo;

    // Alpha modulated by global intensity
    final int glowAlpha = (255.0 * o * intensity).clamp(0, 255).toInt();

    int boost(int c, double f) => (c * f).clamp(0, 255).toInt();

    final glowColor = Color.fromARGB(
      glowAlpha,
      boost(base.red, brightnessMul),
      boost(base.green, brightnessMul),
      boost(base.blue, brightnessMul),
    );

    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = glowWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
      ..blendMode = gb.GlowBlendState.I.mode.toBlendMode(); // <- re-added

    // ---------------- DRAW ORDER ----------------
    if (glowOverStroke) {
      canvas.drawPath(path, corePaint);
      canvas.drawPath(path, glowPaint);
    } else {
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);
    }
  }

  void drawFullWithSymmetry(
      Canvas canvas, Stroke s, Size sz, SymmetryMode mode) {
    final p1 = _buildPath(s.points);
    _drawGlowAndCore(canvas, p1, s);

    if (mode == SymmetryMode.mirrorV || mode == SymmetryMode.quad) {
      _drawGlowAndCore(canvas, _buildPath(_mirrorV(s.points, sz)), s);
    }
    if (mode == SymmetryMode.mirrorH || mode == SymmetryMode.quad) {
      _drawGlowAndCore(canvas, _buildPath(_mirrorH(s.points, sz)), s);
    }
    if (mode == SymmetryMode.quad) {
      _drawGlowAndCore(
          canvas, _buildPath(_mirrorH(_mirrorV(s.points, sz), sz)), s);
    }
  }
}
