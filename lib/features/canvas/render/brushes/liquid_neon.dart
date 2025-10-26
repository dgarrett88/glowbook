
import 'dart:ui';
import '../../../../core/models/stroke.dart';

class LiquidNeonBrush {
  void drawFull(Canvas canvas, Stroke s) {
    if (s.points.length < 2) return;
    final path = Path()..moveTo(s.points.first.x, s.points.first.y);
    for (var i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].x, s.points[i].y);
    }
    final base = Color(s.color);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.size * 1.8
      ..color = base.withValues(alpha: 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(path, glowPaint);

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.size
      ..color = base;
    canvas.drawPath(path, corePaint);
  }
}
