import 'dart:ui';
import 'dart:math' as math;

import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

/// Edge glow: bright neon rim, tighter core – “outlined tube” look.
class EdgeGlowBrush {
  const EdgeGlowBrush();

  Path _buildPath(List<PointSample> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    return path;
  }

  void _draw(Canvas canvas, Path path, Stroke s) {
    final double size = s.size;
    if (size <= 0) return;

    final double g = s.glow.clamp(0.0, 1.0);

    final double radiusFactor = math.pow(g, 0.8).toDouble();
    final double sigma = size * (0.6 + 4.5 * radiusFactor);
    final double outerWidth = size * (1.5 + 2.5 * radiusFactor);
    final double innerWidth = size * 0.7;

    final double brightFactor = math.pow(g, 0.75).toDouble();
    final int outerAlpha = (60 + 150 * brightFactor).clamp(0, 255).toInt();
    final int innerAlpha = (180 + 60 * brightFactor).clamp(0, 255).toInt();

    final Color base = Color(s.color);

    final Paint outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = outerWidth
      ..color = base.withAlpha(outerAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
      ..blendMode = (gb.GlowBlendState.I.mode == gb.GlowBlend.screen)
          ? BlendMode.screen
          : BlendMode.plus;

    final Paint inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = innerWidth
      ..color = base.withAlpha(innerAlpha);

    canvas.drawPath(path, outer);
    canvas.drawPath(path, inner);
  }

  List<PointSample> _mirrorV(List<PointSample> src, Size size) =>
      src.map((pt) => PointSample(size.width - pt.x, pt.y, pt.t)).toList();

  List<PointSample> _mirrorH(List<PointSample> src, Size size) =>
      src.map((pt) => PointSample(pt.x, size.height - pt.y, pt.t)).toList();

  void drawFullWithSymmetry(
    Canvas canvas,
    Stroke s,
    Size sz,
    SymmetryMode mode,
  ) {
    Path pathFrom(List<PointSample> pts) => _buildPath(pts);

    _draw(canvas, pathFrom(s.points), s);

    if (mode == SymmetryMode.mirrorV || mode == SymmetryMode.quad) {
      _draw(canvas, pathFrom(_mirrorV(s.points, sz)), s);
    }
    if (mode == SymmetryMode.mirrorH || mode == SymmetryMode.quad) {
      _draw(canvas, pathFrom(_mirrorH(s.points, sz)), s);
    }
    if (mode == SymmetryMode.quad) {
      _draw(canvas, pathFrom(_mirrorH(_mirrorV(s.points, sz), sz)), s);
    }
  }
}
