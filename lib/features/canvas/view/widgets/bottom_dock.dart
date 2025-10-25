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
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
          border: const Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.brush),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                min: 1,
                max: 60,
                value: controller.brushSize,
                onChanged: controller.setBrushSize,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => controller.pickColor(context),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(controller.color),
                  shape: BoxShape.circle,
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
