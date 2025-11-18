import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/canvas_controller.dart';
import '../../../../core/models/brush.dart';
import 'color_wheel_dialog.dart';
import 'brush_preview.dart';

class BrushHUD extends ConsumerWidget {
  const BrushHUD({super.key});

  // Map actual brush size (1-600) -> slider value (0.0-1.0)
  double _sizeToSliderValue(double size) {
    const min1 = 1.0;
    const max1 = 100.0;
    const min2 = 100.0;
    const max2 = 600.0;

    final s = size.clamp(min1, max2);

    if (s <= max1) {
      // Range 1-100 collapsed into 0.0-0.5
      final local = (s - min1) / (max1 - min1); // 0..1
      return local * 0.5; // 0..0.5
    } else {
      // Range 100-600 collapsed into 0.5-1.0
      final local = (s - min2) / (max2 - min2); // 0..1
      return 0.5 + local * 0.5; // 0.5..1.0
    }
  }

  // Map slider value (0.0-1.0) -> actual brush size (1-600)
  double _sliderValueToSize(double t) {
    const min1 = 1.0;
    const max1 = 100.0;
    const min2 = 100.0;
    const max2 = 600.0;

    final v = t.clamp(0.0, 1.0);

    if (v <= 0.5) {
      final local = v / 0.5; // 0..1
      return min1 + local * (max1 - min1); // 1..100
    } else {
      final local = (v - 0.5) / 0.5; // 0..1
      return min2 + local * (max2 - min2); // 100..600
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvasControllerProvider);
    final ctrl = ref.read(canvasControllerProvider);

    // UI glow value: 0-100 mapped from internal 0-1
    final glowUi = (controller.brushGlow * 100.0).clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------------------------
          // Brush selector row
          // ---------------------------
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: Brush.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final brush = Brush.all[index];
                final isSelected = controller.brushId == brush.id;
                return GestureDetector(
                  onTap: () => ctrl.setBrush(brush.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: isSelected ? 0.15 : 0.05,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.white24,
                      ),
                    ),
                    child: Text(
                      brush.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Brush Preview
          // ---------------------------
          SizedBox(
            height: 160,
            width: double.infinity,
            child: BrushPreview(controller: controller),
          ),

          const SizedBox(height: 16),

          // ---------------------------
          // Size slider (non-linear)
          // ---------------------------
          Row(
            children: [
              const Text(
                'Size',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  // Slider range is 0..1, mapped to 1..600
                  value: _sizeToSliderValue(controller.brushSize),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (t) {
                    final newSize = _sliderValueToSize(t);
                    ctrl.setBrushSize(newSize);
                  },
                ),
              ),
              Text(
                controller.brushSize.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),

          // ---------------------------
          // Glow size slider (0-100 UI -> 0-1 internal)
          // ---------------------------
          Row(
            children: [
              const Text(
                'Glow size',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: glowUi,
                  min: 0.0,
                  max: 100.0,
                  onChanged: (v) {
                    ctrl.setBrushGlow(v / 100.0);
                  },
                ),
              ),
              Text(
                glowUi.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ---------------------------
          // Palette / Colors
          // ---------------------------
          _PaletteRow(controller: controller, ctrl: ctrl),
        ],
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final CanvasController controller;
  final CanvasController ctrl;

  const _PaletteRow({
    required this.controller,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = controller.palette;
    final slots = controller.paletteSlots;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const Text(
            'Colors',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: slots,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final argb = colors[index];
                final isSelected = controller.color == argb;

                return GestureDetector(
                  onTap: () => ctrl.setColor(argb),
                  onLongPress: () async {
                    final picked = await showDialog<Color?>(
                      context: context,
                      barrierDismissible: true,
                      builder: (_) => ColorWheelDialog(initial: Color(argb)),
                    );
                    if (picked != null) {
                      ctrl.updatePalette(index, picked.toARGB32());
                    }
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(argb),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.black54,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
