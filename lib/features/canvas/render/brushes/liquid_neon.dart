import 'dart:ui';
import 'dart:math' as math;
import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

class LiquidNeonBrush {
  const LiquidNeonBrush();

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
    return pts.map((p) => PointSample(cx - (p.x - cx), p.y, p.t)).toList(growable: false);
  }

  List<PointSample> _mirrorH(List<PointSample> pts, Size sz) {
    final double cy = sz.height / 2.0;
    return pts.map((p) => PointSample(p.x, cy - (p.y - cy), p.t)).toList(growable: false);
  }

  void _drawGlowAndCore(Canvas canvas, Path path, int argbColor, double size, double glow) {
    if (glow.isNaN) glow = 0.5;
    glow = glow.clamp(0.0, 1.0);

    final double gSigma = math.pow(glow, 1.6).toDouble();
    final double gAlpha = math.pow(glow, 1.3).toDouble();
    final double sigma = size * (0.05 + 4.0 * gSigma);
    final int alpha = (30 + 225 * gAlpha).clamp(0, 255).toInt();

    final Color base = Color(argbColor);

    final Paint glowPaint = Paint()
      ..color = base.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * (1.0 + 0.6 * gAlpha)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
      ..blendMode = (gb.GlowBlendState.I.mode == gb.GlowBlend.screen) ? BlendMode.screen : BlendMode.plus;

    final Paint corePaint = Paint()
      ..color = base
      ..style = PaintingStyle.stroke
      ..strokeWidth = size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, corePaint);
  }

  void drawFullWithSymmetry(Canvas canvas, Stroke s, Size sz, SymmetryMode mode) {
    final path = _buildPath(s.points);
    _drawGlowAndCore(canvas, path, s.color, s.size, s.glow);

    if (mode == SymmetryMode.mirrorV || mode == SymmetryMode.quad) {
      final p2 = _buildPath(_mirrorV(s.points, sz));
      _drawGlowAndCore(canvas, p2, s.color, s.size, s.glow);
    }
    if (mode == SymmetryMode.mirrorH || mode == SymmetryMode.quad) {
      final p3 = _buildPath(_mirrorH(s.points, sz));
      _drawGlowAndCore(canvas, p3, s.color, s.size, s.glow);
    }
    if (mode == SymmetryMode.quad) {
      final p4 = _buildPath(_mirrorH(_mirrorV(s.points, sz), sz));
      _drawGlowAndCore(canvas, p4, s.color, s.size, s.glow);
    }
  }
}
