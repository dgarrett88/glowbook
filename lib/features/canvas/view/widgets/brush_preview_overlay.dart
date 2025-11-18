// import 'package:flutter/material.dart';
// import '../../state/canvas_controller.dart';

// class BrushPreviewOverlay extends CustomPainter {
//   final CanvasController controller;

//   BrushPreviewOverlay({required this.controller})
//       : super(repaint: controller.repaint);

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (!controller.showBrushPreview) return;

//     final color = Color(controller.color);
//     final brushSize = controller.brushSize;
//     final glowSize = controller.brushGlow;
//     final intensity = controller.glowIntensity;

//     // Position a bit above mid-screen, centered horizontally.
//     final center = Offset(size.width / 2, size.height * 0.35);

//     final baseRadius =
//         (brushSize / 2).clamp(1.0, size.shortestSide / 2) as double;
//     final glowRadius = baseRadius * (1.0 + glowSize * 2.0);

//     final normIntensity = intensity.clamp(0.0, 2.0);
//     final coreAlpha = (0.8 * normIntensity).clamp(0.0, 1.0);
//     final glowAlpha = (0.9 * normIntensity).clamp(0.0, 1.0);

//     final glowPaint = Paint()
//       ..color = color.withOpacity(glowAlpha)
//       ..style = PaintingStyle.fill
//       ..maskFilter =
//           MaskFilter.blur(BlurStyle.normal, glowRadius * 0.6); // soft glow

//     canvas.drawCircle(center, glowRadius, glowPaint);

//     final corePaint = Paint()
//       ..color = color.withOpacity(coreAlpha)
//       ..style = PaintingStyle.fill;

//     canvas.drawCircle(center, baseRadius, corePaint);
//   }

//   @override
//   bool shouldRepaint(covariant BrushPreviewOverlay oldDelegate) => false;
// }
