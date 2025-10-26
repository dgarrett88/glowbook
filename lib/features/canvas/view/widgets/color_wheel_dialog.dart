import 'dart:math' as math;
import 'package:flutter/material.dart';

class ColorWheelDialog extends StatefulWidget {
  final Color initial;
  const ColorWheelDialog({super.key, required this.initial});

  @override
  State<ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<ColorWheelDialog> {
  double hue = 300; // default near magenta
  double sat = 1.0;
  double val = 1.0;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    hue = hsv.hue;
    sat = hsv.saturation;
    val = hsv.value;
  }

  Color get current => HSVColor.fromAHSV(1.0, hue, sat, val).toColor();

  void _onPanWheel(Offset localPos, Size size){
    final center = size.center(Offset.zero);
    final v = localPos - center;
    final angle = math.atan2(v.dy, v.dx); // -pi..pi
    double degrees = angle * 180 / math.pi; // -180..180
    if (degrees < 0) degrees += 360;
    setState(() { hue = degrees; });
  }

  @override
  Widget build(BuildContext context) {
    final ringSize = 220.0;
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.95),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      title: const Text('Pick color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: GestureDetector(
              onPanDown: (d) => _onPanWheel(d.localPosition, const Size.square(220)),
              onPanUpdate: (d) => _onPanWheel(d.localPosition, const Size.square(220)),
              child: CustomPaint(
                painter: _HueRingPainter(),
                child: Center(
                  child: Container(
                    width: ringSize - 60,
                    height: ringSize - 60,
                    decoration: BoxDecoration(
                      color: current,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _slider('Saturation', sat, (v)=> setState(()=> sat=v)),
          _slider('Brightness', val, (v)=> setState(()=> val=v)),
        ],
      ),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: ()=> Navigator.pop(context, current), child: const Text('Select')),
      ],
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged){
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const SizedBox(width: 8),
            Container(width: 14, height: 14, decoration: BoxDecoration(color: current, shape: BoxShape.circle, border: Border.all(color: Colors.white24))),
          ],
        ),
        Slider(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _HueRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    final ringWidth = 30.0;

    // Hue sweep
    final sweep = SweepGradient(colors: [
      const Color(0xFFFF0000),
      const Color(0xFFFFFF00),
      const Color(0xFF00FF00),
      const Color(0xFF00FFFF),
      const Color(0xFF0000FF),
      const Color(0xFFFF00FF),
      const Color(0xFFFF0000),
    ]);

    final paint = Paint()
      ..shader = sweep.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;

    canvas.drawCircle(center, radius - ringWidth/2, paint);

    // Inner shadow for aesthetics
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, radius - ringWidth/2, shadow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
