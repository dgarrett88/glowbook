import 'package:flutter/material.dart';

enum DiceDotsPattern { one, twoH, twoV, four }

class DiceDotsIcon extends StatelessWidget {
  final DiceDotsPattern pattern;
  final double size;
  final Color color;

  const DiceDotsIcon({
    super.key,
    required this.pattern,
    this.size = 22,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final s = size;
    final dot = s * 0.16;
    final off = s * 0.28;
    List<Offset> pts;

    switch (pattern) {
      case DiceDotsPattern.one:
        pts = [const Offset(0, 0)];
        break;
      case DiceDotsPattern.twoH:
        pts = [Offset(-off, 0), Offset(off, 0)];
        break;
      case DiceDotsPattern.twoV:
        pts = [Offset(0, -off), Offset(0, off)];
        break;
      case DiceDotsPattern.four:
        pts = [
          Offset(-off, -off),
          Offset(off, -off),
          Offset(-off, off),
          Offset(off, off),
        ];
        break;
    }

    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        painter: _DotsPainter(pts, dot, color),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final List<Offset> pts;
  final double d;
  final Color color;
  _DotsPainter(this.pts, this.d, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..isAntiAlias = true;
    for (final p in pts) {
      canvas.drawCircle(center + p, d / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.pts != pts || old.d != d || old.color != color;
}
