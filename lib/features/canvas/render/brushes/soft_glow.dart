import 'dart:ui';
import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart';

class SoftGlowBrush {
  Path _buildPath(List<PointSample> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    return path;
  }

  void _draw(Canvas canvas, Path path, int argbColor, double size) {
    final base = Color(argbColor);

    // Soft Glow: very wide, soft halo + slightly translucent core
    final outerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size * 2.8
      ..color = base.withValues(alpha: 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(path, outerGlow);

    final innerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size * 1.6
      ..color = base.withValues(alpha: 0.50)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, innerGlow);

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size * 0.85
      ..color = base.withValues(alpha: 0.85);
    canvas.drawPath(path, corePaint);
  }

  void drawFull(Canvas canvas, Stroke s) {
    _draw(canvas, _buildPath(s.points), s.color, s.size);
  }

  void drawFullWithSymmetry(Canvas canvas, Stroke s, Size size, SymmetryMode mode) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    Path buildFrom(List<PointSample> pts) {
      final p = Path();
      if (pts.isEmpty) return p;
      p.moveTo(pts.first.x, pts.first.y);
      for (var i = 1; i < pts.length; i++) {
        p.lineTo(pts[i].x, pts[i].y);
      }
      return p;
    }

    List<PointSample> mirrorV(List<PointSample> src) =>
      src.map((pt) => PointSample(2*cx - pt.x, pt.y, pt.t)).toList();
    List<PointSample> mirrorH(List<PointSample> src) =>
      src.map((pt) => PointSample(pt.x, 2*cy - pt.y, pt.t)).toList();

    _draw(canvas, buildFrom(s.points), s.color, s.size);

    if (mode == SymmetryMode.mirrorV || mode == SymmetryMode.quad) {
      _draw(canvas, buildFrom(mirrorV(s.points)), s.color, s.size);
    }
    if (mode == SymmetryMode.mirrorH || mode == SymmetryMode.quad) {
      _draw(canvas, buildFrom(mirrorH(s.points)), s.color, s.size);
    }
    if (mode == SymmetryMode.quad) {
      _draw(canvas, buildFrom(mirrorH(mirrorV(s.points))), s.color, s.size);
    }
  }
}
