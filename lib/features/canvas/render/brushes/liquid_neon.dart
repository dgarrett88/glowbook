import 'dart:ui';
import 'dart:math' as math;

import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

/// LiquidNeonBrush
/// ----------------
/// Bright neon tube with a soft glow band.
///
/// Uses per-channel glow fields on [Stroke]:
/// - [glowRadius]     -> how far the glow spreads (geometry)
/// - [glowBrightness] -> how intense the glow colour is
/// - [glowOpacity]    -> how visible the glow is (alpha)
///
/// It intentionally ignores the legacy [Stroke.glow] value for look,
/// so radius / brightness / opacity stay logically separated.
class LiquidNeonBrush {
  /// If true, the glow is drawn over the stroke instead of under it.
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

    // Geometry / spread driver (0..1) from glowRadius.
    double r = s.glowRadius;
    if (r.isNaN) r = 0.6;
    r = r.clamp(0.0, 1.0);

    // ---------------- GLOW BRIGHTNESS (0–100 logical scale) ----------------
    //
    // s.glowBrightness is stored 0.0–1.0 but conceptually is 0–100 in UI:
    //
    //   UI 0   -> b = 0.0  -> brightnessMul = 0.0   (black, no glow colour)
    //   UI 70  -> b = 0.7  -> brightnessMul = 1.0   (base colour)
    //   UI 100 -> b = 1.0  -> brightnessMul ≈ 1.7   (brighter than base)
    //
    // 1–69 are darker than base, 71–100 brighter than base.
    double b = s.glowBrightness;
    if (b.isNaN) {
      // Default = 70 on the 0–100 scale.
      b = 0.7;
    }
    b = b.clamp(0.0, 1.0);

    // Map 0.0–1.0 to 0–100 UI-style brightness.
    final double uiBrightness = b * 100.0;
    const double pivot = 70.0;

    double brightnessMul;
    if (uiBrightness <= 0.0) {
      // 0 → black glow (no colour contribution)
      brightnessMul = 0.0;
    } else {
      // Linear scale around 70 as the "base colour" point.
      //  uiBrightness = 70  -> 70/70 = 1.0 (base colour)
      //  uiBrightness < 70  -> <1.0 (darker)
      //  uiBrightness > 70  -> >1.0 (brighter)
      brightnessMul = uiBrightness / pivot;

      // Dial brightness up a little overall without changing the pivot:
      // 70 still maps to 1.0, but the top end (100) now reaches ~1.7.
      brightnessMul *= 1.2;
    }

    // Master opacity (0..1) from glowOpacity.
    double o = s.glowOpacity;
    if (o.isNaN) o = 1.0;
    o = o.clamp(0.0, 1.0);

    // Global blend intensity 0..1 from blend sheet slider.
    final double intensity = gb.GlowBlendState.I.intensity.clamp(0.0, 1.0);

    int boostChannel(int c, double factor) =>
        (c * factor).clamp(0.0, 255.0).toInt();

    // ---------------- CORE STROKE ----------------
    //
    // Core respects the user’s chosen colour; we only scale alpha.
    final double coreStrength = s.coreOpacity.clamp(0.0, 1.0);
    final int coreAlpha = (255.0 * coreStrength).round();
    final Color coreColor = base.withAlpha(coreAlpha);

    final Paint corePaint = Paint()
      ..color = coreColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // If radius / opacity / brightness are effectively zero,
    // draw ONLY the core tube (no halo at all).
    if (r <= 0.0 || o <= 0.0 || brightnessMul <= 0.0) {
      canvas.drawPath(path, corePaint);
      return;
    }

    // ---------------- GLOW STROKE ----------------
    //
    // Radius controls halo thickness in absolute pixels.
    const double maxHaloThickness = 120.0; // px of glow beyond the core
    final double baseHalo = maxHaloThickness * r; // 0..maxHaloThickness

    final bool scaleWithSize = s.glowRadiusScalesWithSize;
    const double kSizeRef = 24.0;
    final double sizeFactor =
        (size / kSizeRef).clamp(0.5, 4.0); // avoid outrageous extremes

    final double halo = scaleWithSize ? baseHalo * sizeFactor : baseHalo;

    // Total width of the glow stroke.
    final double glowWidth = size + halo;

    // Blur radius: tie it more to halo than to size
    final double sigma = 0.3 * size + 0.7 * halo;

    // Glow alpha depends on opacity only; radius does NOT affect alpha.
    final int glowAlpha = (255.0 * o * intensity).clamp(0, 255).toInt();

    // Brightness affects COLOUR intensity of the glow.
    final double glowColorFactor = brightnessMul;

    final Color glowColor = Color.fromARGB(
      glowAlpha,
      boostChannel(base.red, glowColorFactor),
      boostChannel(base.green, glowColorFactor),
      boostChannel(base.blue, glowColorFactor),
    );

    final Paint glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = glowWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
      ..blendMode = gb.GlowBlendState.I.mode.toBlendMode();

    // Draw order.
    if (glowOverStroke) {
      canvas.drawPath(path, corePaint);
      canvas.drawPath(path, glowPaint);
    } else {
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);
    }
  }

  void drawFullWithSymmetry(
    Canvas canvas,
    Stroke s,
    Size sz,
    SymmetryMode mode,
  ) {
    final Path basePath = _buildPath(s.points);
    _drawGlowAndCore(canvas, basePath, s);

    if (mode == SymmetryMode.mirrorV || mode == SymmetryMode.quad) {
      final p2 = _buildPath(_mirrorV(s.points, sz));
      _drawGlowAndCore(canvas, p2, s);
    }
    if (mode == SymmetryMode.mirrorH || mode == SymmetryMode.quad) {
      final p3 = _buildPath(_mirrorH(s.points, sz));
      _drawGlowAndCore(canvas, p3, s);
    }
    if (mode == SymmetryMode.quad) {
      final p4 = _buildPath(_mirrorH(_mirrorV(s.points, sz), sz));
      _drawGlowAndCore(canvas, p4, s);
    }
  }
}
