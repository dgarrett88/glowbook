import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Vital-ish knob:
/// - Drag up/down to change
/// - Double tap = reset (if defaultValue provided)
/// - Long press = type exact value
/// - Optional value display & label
/// - Notifies parent when interaction starts/ends so ScrollView can be disabled.
/// - ✅ NEW: onChangeStart / onChangeEnd so you can commit undo ONLY on finger lift.
class SynthKnob extends StatefulWidget {
  const SynthKnob({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.defaultValue,
    this.size = 56,
    this.label,
    this.valueFormatter,
    this.sensitivity = 0.006,
    this.showValueText = true,
    this.modTag,
    this.onTapModTag,
    this.enabled = true,
    this.onInteractionChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;

  final double min;
  final double max;
  final double? defaultValue;

  final double size;
  final String? label;
  final String Function(double v)? valueFormatter;

  final double sensitivity;

  final bool showValueText;

  final String? modTag;
  final VoidCallback? onTapModTag;

  final bool enabled;

  /// True while user is touching/dragging this knob (use this to disable ScrollView).
  final ValueChanged<bool>? onInteractionChanged;

  /// ✅ Called when the user starts a drag (finger down + pan start).
  /// Use this to snapshot "before" for undo.
  final VoidCallback? onChangeStart;

  /// ✅ Called when the user ends a drag (finger up / cancel).
  /// Use this to push ONE undo step.
  final VoidCallback? onChangeEnd;

  @override
  State<SynthKnob> createState() => _SynthKnobState();
}

class _SynthKnobState extends State<SynthKnob> {
  double _startValue = 0.0;
  Offset? _dragStart;

  bool _active = false;
  bool _dragging = false;

  double get _clamped => widget.value.clamp(widget.min, widget.max);

  double _norm(double v) {
    final range = (widget.max - widget.min);
    if (range == 0) return 0;
    return ((v - widget.min) / range).clamp(0.0, 1.0);
  }

  double _denorm(double t) {
    final range = (widget.max - widget.min);
    return widget.min + (t.clamp(0.0, 1.0) * range);
  }

  String _format(double v) {
    if (widget.valueFormatter != null) return widget.valueFormatter!(v);
    final range = (widget.max - widget.min).abs();
    if (range <= 2.0) return v.toStringAsFixed(2);
    return v.toStringAsFixed(1);
  }

  void _setActive(bool v) {
    if (_active == v) return;
    _active = v;
    widget.onInteractionChanged?.call(v);
  }

  Future<void> _promptExactValue() async {
    if (!widget.enabled) return;

    final ctrl = TextEditingController(text: _clamped.toStringAsFixed(3));
    final res = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171720),
        title: Text(
          widget.label ?? 'Set value',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter value',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (res == null) return;
    final v = res.clamp(widget.min, widget.max);
    widget.onChanged(v);
  }

  void _reset() {
    if (!widget.enabled) return;
    final d = widget.defaultValue;
    if (d == null) return;
    widget.onChanged(d.clamp(widget.min, widget.max));
  }

  void _endInteraction({bool fireChangeEnd = false}) {
    _dragStart = null;

    if (_dragging) {
      _dragging = false;
      if (fireChangeEnd) {
        widget.onChangeEnd?.call(); // ✅ commit undo step on finger lift/cancel
      }
    }

    _setActive(false);
  }

  @override
  void dispose() {
    if (_active) widget.onInteractionChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _norm(_clamped);

    final knobPaint = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _KnobPainter(
          t: t,
          enabled: widget.enabled,
          accent: cs.primary,
        ),
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ Listener fires immediately on touch (not in gesture arena),
          // so we can disable scrolling BEFORE the list steals the drag.
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.enabled ? (_) => _setActive(true) : null,
            onPointerUp: widget.enabled
                ? (_) => _endInteraction(fireChangeEnd: true)
                : null,
            onPointerCancel: widget.enabled
                ? (_) => _endInteraction(fireChangeEnd: true)
                : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _reset,
              onLongPress: _promptExactValue,
              onPanStart: widget.enabled
                  ? (d) {
                      _dragging = true;
                      widget.onChangeStart?.call(); // ✅ snapshot "before"
                      _startValue = _clamped;
                      _dragStart = d.localPosition;
                    }
                  : null,
              onPanUpdate: widget.enabled
                  ? (d) {
                      final start = _dragStart;
                      if (start == null) return;

                      final dy = d.localPosition.dy - start.dy;
                      final deltaNorm = (-dy) * widget.sensitivity;

                      final newNorm =
                          (_norm(_startValue) + deltaNorm).clamp(0.0, 1.0);
                      final newValue = _denorm(newNorm);
                      widget.onChanged(newValue);
                    }
                  : null,
              onPanEnd: widget.enabled
                  ? (_) => _endInteraction(fireChangeEnd: true)
                  : null,
              onPanCancel: widget.enabled
                  ? () => _endInteraction(fireChangeEnd: true)
                  : null,
              child: knobPaint,
            ),
          ),
          const SizedBox(height: 6),
          if (widget.label != null)
            Text(
              widget.label!,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                height: 1.0,
              ),
            ),
          if (widget.showValueText)
            Text(
              _format(_clamped),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          if (widget.modTag != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: widget.onTapModTag,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.modTag!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({
    required this.t,
    required this.enabled,
    required this.accent,
  });

  final double t; // 0..1
  final bool enabled;
  final Color accent;

  static const double _startAngle = math.pi * 0.75; // 135°
  static const double _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (math.min(size.width, size.height) / 2) - 2;

    final bodyPaint = Paint()
      ..color = const Color(0xFF20202A)
      ..style = PaintingStyle.fill;

    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(c, r, bodyPaint);
    canvas.drawCircle(c, r, rimPaint);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;

    final rect = Rect.fromCircle(center: c, radius: r - 6);
    canvas.drawArc(rect, _startAngle, _sweep, false, trackPaint);

    final valuePaint = Paint()
      ..color = enabled
          ? accent.withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;

    canvas.drawArc(rect, _startAngle, _sweep * t, false, valuePaint);

    final ang = _startAngle + (_sweep * t);
    final p1 = c + Offset(math.cos(ang), math.sin(ang)) * (r - 10);
    final p2 = c + Offset(math.cos(ang), math.sin(ang)) * (r - 18);

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.92 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    canvas.drawLine(p2, p1, tickPaint);

    final dotPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(c, 4.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.enabled != enabled ||
        oldDelegate.accent != accent;
  }
}
