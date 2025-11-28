import 'dart:ui';
import 'dart:math' as math;

import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart' show SymmetryMode;
import '../../state/glow_blend.dart' as gb;

/// Softer, hazier neon – meant to be smoother than Liquid Neon.
class SoftGlowBrush {
  SoftGlowBrush();

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

    // Glow slider 0–1 controlling radius/softness/brightness.
    final double g = s.glow.clamp(0.0, 1.0);

    // Keep a minimum softness so 0 isn't totally dead.
    final double radiusFactor = math.pow(g, 0.8).toDouble();
    final double sigma = size * (1.2 + 5.0 * radiusFactor);
    final double haloWidth = size * (1.4 + 3.0 * radiusFactor);

    final double brightFactor = math.pow(g, 0.7).toDouble();
    final int haloAlpha = (40 + 180 * brightFactor).clamp(0, 255).toInt();
    final int coreAlpha = (150 + 80 * brightFactor).clamp(0, 255).toInt();

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

    final Paint core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size * 0.8
      ..color = base.withAlpha((coreAlpha * gb.GlowBlendState.I.intensity.clamp(0.0, 1.0)).toInt());

    canvas.drawPath(path, halo);
    canvas.drawPath(path, core);
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
