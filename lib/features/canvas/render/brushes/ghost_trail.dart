import 'dart:ui';
import 'dart:math' as math;

import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

/// Ghost trail: low-opacity, smeared glow for foggy / motion trails.
class GhostTrailBrush {
  const GhostTrailBrush();

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

    final double radiusFactor = math.pow(g, 0.9).toDouble();
    final double sigma = size * (1.6 + 7.0 * radiusFactor);
    final double haloWidth = size * (1.8 + 3.5 * radiusFactor);

    final double brightFactor = math.pow(g, 0.9).toDouble();
    final int haloAlpha = (20 + 130 * brightFactor).clamp(0, 255).toInt();
    final int coreAlpha = (40 + 80 * brightFactor).clamp(0, 255).toInt();

    final Color base = Color(s.color);

    final Paint halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = haloWidth
      ..color = base.withAlpha((haloAlpha * gb.GlowBlendState.I.intensity.clamp(0.0, 1.0)).toInt())
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
      ..blendMode = (gb.GlowBlendState.I.mode == gb.GlowBlend.screen)
          ? BlendMode.screen
          : BlendMode.plus;

    final Paint faintCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(size * 0.6, 1.0)
      ..color = base.withAlpha((coreAlpha * gb.GlowBlendState.I.intensity.clamp(0.0, 1.0)).toInt());

    canvas.drawPath(path, halo);
    canvas.drawPath(path, faintCore);
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
