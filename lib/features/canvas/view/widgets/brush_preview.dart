import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/brush.dart';
import '../../../../core/models/stroke.dart';
import '../../state/canvas_controller.dart';
import '../../render/brushes/liquid_neon.dart';
import '../../render/brushes/soft_glow.dart';
import '../../render/brushes/glow_only.dart';
import '../../render/brushes/hyper_neon.dart';
import '../../render/brushes/edge_glow.dart';
import '../../render/brushes/ghost_trail.dart';
import '../../render/brushes/inner_glow.dart';

class BrushPreview extends StatelessWidget {
  final CanvasController controller;

  const BrushPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: CustomPaint(
          painter: _BrushPreviewPainter(controller),
        ),
      ),
    );
  }
}

class _BrushPreviewPainter extends CustomPainter {
  final CanvasController controller;

  final LiquidNeonBrush _neon = const LiquidNeonBrush();
  final SoftGlowBrush _soft = SoftGlowBrush();
  final GlowOnlyBrush _glowOnly = const GlowOnlyBrush();
  final HyperNeonBrush _hyper = const HyperNeonBrush();
  final EdgeGlowBrush _edge = const EdgeGlowBrush();
  final GhostTrailBrush _ghost = const GhostTrailBrush();
  final InnerGlowBrush _inner = const InnerGlowBrush();

  _BrushPreviewPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bg = Paint()..color = const Color(0xFF050506);
    canvas.drawRect(Offset.zero & size, bg);

    // Subtle border
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(12),
      ),
      border,
    );

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Build a clustered "dot" stroke in the center.
    final points = <PointSample>[];
    const sampleCount = 12;
    final radius =
        (controller.brushSize / 2).clamp(2.0, size.shortestSide * 0.18);

    for (int i = 0; i < sampleCount; i++) {
      final angle = (i / sampleCount) * 2 * math.pi;
      final r = radius * (0.3 + 0.7 * (i / sampleCount));
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      points.add(PointSample(x, y, i * 10));
    }

    final stroke = Stroke(
      id: 'preview_dot',
      brushId: controller.brushId,
      color: controller.color,
      size: controller.brushSize,
      glow: controller.brushGlow,
      seed: 0,
      points: points,
      symmetryId: null,
    );

    const mode = SymmetryMode.off;

    switch (stroke.brushId) {
      case 'liquid_neon':
        _neon.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      case 'soft_glow':
        _soft.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      case 'glow_only':
        _glowOnly.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      case 'hyper_neon':
        _hyper.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      case 'edge_glow':
        _edge.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      case 'ghost_trail':
        _ghost.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      case 'inner_glow':
        _inner.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
      default:
        _neon.drawFullWithSymmetry(canvas, stroke, size, mode);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BrushPreviewPainter oldDelegate) {
    return oldDelegate.controller != controller;
  }
}
