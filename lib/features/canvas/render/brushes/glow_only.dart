import 'dart:ui';
import 'dart:math' as math;
import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;

/// A pure-glow brush (no opaque core). Great for neon trails and light painting.
class GlowOnlyBrush {
  const GlowOnlyBrush();

  Path _buildPath(List<PointSample> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    return path;
  }

  void _drawGlow(Canvas canvas, Path path, int argbColor, double size, double glow) {
    // Normalize glow [0..1]
    if (glow.isNaN) glow = 0.5;
    glow = glow.clamp(0.0, 1.0);

    // Map glow to blur sigma, width and alpha curves
    final double gSigma = math.pow(glow, 1.6).toDouble();
    final double gAlpha = math.pow(glow, 1.3).toDouble();
    final double sigma = size * (0.08 + 4.5 * gSigma);           // heavier bloom at higher glow
    final double width = size * (1.2 + 0.8 * gAlpha);            // wider as it glows more
    final int alpha = (40 + 210 * gAlpha).clamp(0, 255).toInt(); // brighter as it glows more

    final paint = Paint()
      ..color = Color(argbColor).withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

    // Draw 2 passes for a slightly fuller glow body without a hard core
    canvas.drawPath(path, paint);
    final paint2 = paint
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * 0.6)
      ..strokeWidth = width * 0.8
      ..color = paint.color.withAlpha((alpha * 0.8).toInt());
    canvas.drawPath(path, paint2);
  }

  void drawFullWithSymmetry(Canvas canvas, Stroke s, Size sz, SymmetryMode mode) {
    final path = _buildPath(s.points);
    _drawGlow(canvas, path, s.color, s.size, s.glow);

    List<PointSample> _mirrorV(List<PointSample> src, Size size) =>
      src.map((pt) => PointSample(size.width - pt.x, pt.y, pt.t)).toList();
    List<PointSample> _mirrorH(List<PointSample> src, Size size) =>
      src.map((pt) => PointSample(pt.x, size.height - pt.y, pt.t)).toList();

    if (mode == SymmetryMode.mirrorV || mode == SymmetryMode.quad) {
      _drawGlow(canvas, _buildPath(_mirrorV(s.points, sz)), s.color, s.size, s.glow);
    }
    if (mode == SymmetryMode.mirrorH || mode == SymmetryMode.quad) {
      _drawGlow(canvas, _buildPath(_mirrorH(s.points, sz)), s.color, s.size, s.glow);
    }
    if (mode == SymmetryMode.quad) {
      _drawGlow(canvas, _buildPath(_mirrorH(_mirrorV(s.points, sz), sz)), s.color, s.size, s.glow);
    }
  }
}
