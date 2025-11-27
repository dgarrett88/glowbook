import 'dart:math' as math;
import 'package:flutter/material.dart';

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
      child: CustomPaint(
        painter: _BrushPreviewPainter(controller),
      ),
    );
  }
}

class _BrushPreviewPainter extends CustomPainter {
  final CanvasController controller;

  final LiquidNeonBrush _neon = LiquidNeonBrush();
  final SoftGlowBrush _soft = SoftGlowBrush();
  final GlowOnlyBrush _glowOnly = GlowOnlyBrush();
  final HyperNeonBrush _hyper = HyperNeonBrush();
  final EdgeGlowBrush _edge = EdgeGlowBrush();
  final GhostTrailBrush _ghost = GhostTrailBrush();
  final InnerGlowBrush _inner = InnerGlowBrush();

  _BrushPreviewPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = const Color(0xFF050506);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Subtle border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(12),
      ),
      borderPaint,
    );

    final width = size.width;
    final height = size.height;
    final midY = height * 0.5;

    // Build a single stroke from left to right with a gentle wave.
    const sampleCount = 32;
    final points = <PointSample>[];

    final xStart = width * 0.08;
    final xEnd = width * 0.92;
    final amp = height * 0.18;

    for (int i = 0; i < sampleCount; i++) {
      final t = i / (sampleCount - 1);
      final x = xStart + (xEnd - xStart) * t;
      final wave = math.sin(t * math.pi * 2.0);
      final y = midY + wave * amp;
      points.add(PointSample(x, y, (t * 300).round()));
    }

    final stroke = Stroke(
      id: 'preview_stroke',
      brushId: controller.brushId,
      color: controller.color,
      size: controller.brushSize,
      glow: controller.brushGlow,
      glowRadius: controller.glowRadius,
      glowOpacity: controller.glowOpacity,
      glowBrightness: controller.glowBrightness,
      coreOpacity: controller.coreOpacity, // 🔥 wired into preview
      glowRadiusScalesWithSize: controller.glowRadiusScalesWithSize,
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
