import 'dart:ui';
import '../../../../core/models/stroke.dart';

class LiquidNeonBrush {
  void drawPartial(Canvas canvas, Stroke s) {
    if (s.points.length < 2) return;

    final path = Path()..moveTo(s.points.first.x, s.points.first.y);
    for (var i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].x, s.points[i].y);
    }

    final base = Color(s.color);

    // Glow pass (under)
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.size * 1.8
      ..color = base.withOpacity(0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawPath(path, glowPaint);

    // Core pass (over)
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.size
      ..color = base;
    canvas.drawPath(path, corePaint);
  }

  void drawFull(Canvas canvas, Stroke s) => drawPartial(canvas, s);
}
