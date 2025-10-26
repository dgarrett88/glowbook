
import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';

class BottomDock extends StatelessWidget {
  final CanvasController controller;
  const BottomDock({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Size
            const Text('Size'),
            Expanded(
              child: Slider(
                value: controller.brushSize,
                min: 1,
                max: 40,
                onChanged: controller.setBrushSize,
              ),
            ),
            // Color
            GestureDetector(
              onTap: () => controller.pickColor(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(controller.color),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
