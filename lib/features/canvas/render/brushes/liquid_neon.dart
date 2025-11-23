import 'dart:ui';
import 'dart:math' as math;

import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

/// LiquidNeonBrush
/// ----------------
/// Bright neon tube with a soft glow band.
///
/// This implementation uses the *per-channel* glow fields on [Stroke]:
/// - [glowRadius]     -> how far the glow spreads (geometry only)
/// - [glowBrightness] -> how intense / colourful the glow band is
/// - [glowOpacity]    -> how visible everything is (alpha only)
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
    double b = s.glowBrightness;
    if (b.isNaN) b = 0.6;
    b = b.clamp(0.0, 1.0);

    // Master opacity (0..1) from glowOpacity.
    double o = s.glowOpacity;
    if (o.isNaN) o = 1.0;
    o = o.clamp(0.0, 1.0);

    int _boostChannel(int c, double factor) =>
        (c * factor).clamp(0.0, 255.0).toInt();

    // ---------------- CORE STROKE ----------------
    //
    // Core respects the user’s chosen colour; we only scale alpha.
    // Core tube alpha comes from coreOpacity (0..1).
    final double co =
        (s.coreOpacity.isNaN ? 0.86 : s.coreOpacity).clamp(0.0, 1.0);
    final int coreAlpha = (co * 255.0).toInt();
    final Color coreColor = base.withAlpha(coreAlpha);

    final Paint corePaint = Paint()
      ..color = coreColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ---------------- GLOW STROKE ----------------
    //
    // Radius (r) controls how far the glow spreads. It ONLY affects
    // geometry (width & blur), not colour.
    //
    // You can tweak these two factors if you want even more / less range:
    const double maxWidthFactor = 7.0; // how fat the halo can get
    const double maxBlurFactor = 5.0; // how soft the glow can get

    final double widthFactor = 1.4 + maxWidthFactor * r; // ~1.4x .. 8.4x at r=1
    final double glowWidth = size * widthFactor;

    final double sigmaFactor = math.pow(r, 1.3).toDouble(); // bias to high end
    final double sigma = size * (0.4 + maxBlurFactor * sigmaFactor);

    // Glow alpha depends on opacity only; radius does NOT affect alpha.
    final int glowAlpha = (255.0 * o).clamp(0.0, 255.0).toInt();

    // Brightness heavily affects COLOUR intensity of the glow.
    //
    // Give it lots of low range:
    //   b=0   -> factor ~0.00 (almost black)
    //   b=0.5 -> factor ~0.32
    //   b=1   -> factor ~1.30  (very hot)
    final double brightnessFactor = b * b;
    final double glowColorFactor = 0.00 + 1.30 * brightnessFactor;

    final Color glowColor = Color.fromARGB(
      glowAlpha,
      _boostChannel(base.red, glowColorFactor),
      _boostChannel(base.green, glowColorFactor),
      _boostChannel(base.blue, glowColorFactor),
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
