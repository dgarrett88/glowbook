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

    // Colour driver (0..1) from glowBrightness.
    //
    // UI is 0..300, mapped to stored 0..1 using /300 in the HUD.
    // We interpret stored b as a 0..3x brightness multiplier:
    //   UI 100 -> b ≈ 1/3 -> 1x base colour
    //   UI 300 -> b = 1   -> 3x brighter
    double b = s.glowBrightness;
    if (b.isNaN) {
      // default near "100" UI -> ~1x
      b = 1.0 / 3.0;
    }
    b = b.clamp(0.0, 1.0);
    final double brightnessMul = 3.0 * b; // 0..3

    // Master opacity (0..1) from glowOpacity.
    double o = s.glowOpacity;
    if (o.isNaN) o = 1.0;
    o = o.clamp(0.0, 1.0);

    int boostChannel(int c, double factor) =>
        (c * factor).clamp(0.0, 255.0).toInt();

    // ---------------- CORE STROKE ----------------
    //
    // Core respects the user’s chosen colour; we only scale alpha.
    // (Assuming Stroke has coreOpacity 0..1 – this is what your
    // "Core strength" slider writes to.)
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
    // NEW behaviour:
    //   - radius controls *halo thickness* in absolute pixels
    //   - brush size controls the core tube only
    //   - changing size does NOT massively change the halo reach
    //
    // By default, the "extra" glow beyond the core is independent of size.
    // When [glowRadiusScalesWithSize] is true on the stroke, we additionally
    // scale the halo by the brush size so bigger brushes have a larger reach.
    const double maxHaloThickness = 120.0; // px of glow beyond the core
    final double baseHalo = maxHaloThickness * r; // 0..maxHaloThickness

    final bool scaleWithSize = s.glowRadiusScalesWithSize;
    const double kSizeRef = 24.0;
    final double sizeFactor =
        (size / kSizeRef).clamp(0.5, 4.0); // avoid outrageous extremes

    final double halo = scaleWithSize ? baseHalo * sizeFactor : baseHalo;

    // Total width of the glow stroke.
    // core tube (size) + halo thickness (possibly size-scaled)
    final double glowWidth = size + halo;

    // Blur radius: tie it more to halo than to size
    final double sigma = 0.3 * size + 0.7 * halo;

    // Glow alpha depends on opacity only; radius does NOT affect alpha.
    final int glowAlpha = (255.0 * o).clamp(0.0, 255.0).toInt();

    // Brightness affects COLOUR intensity of the glow.
    // brightnessMul = 1  -> base colour
    // brightnessMul = 3  -> 3x brighter
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
      ..blendMode = (gb.GlowBlendState.I.mode == gb.GlowBlend.screen)
          ? BlendMode.screen
          : BlendMode.plus;

    // Draw order:
    // - Default (glowOverStroke == false):
    //     glow first, then core on top (stroke over glow).
    // - If glowOverStroke == true:
    //     core first, then glow over stroke.
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
