import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/canvas_controller.dart';
import '../../../../core/models/brush.dart';
import 'color_wheel_dialog.dart';
import 'brush_preview.dart';

class BrushHUD extends ConsumerStatefulWidget {
  const BrushHUD({super.key});

  @override
  ConsumerState<BrushHUD> createState() => _BrushHUDState();
}

class _BrushHUDState extends ConsumerState<BrushHUD> {
  // Map actual brush size (1-600) -> slider value (0.0-1.0)
  double _sizeToSliderValue(double size) {
    const min1 = 1.0;
    const max1 = 100.0;
    const min2 = 100.0;
    const max2 = 600.0;

    if (size <= min2) {
      final v = ((size - min1) / (max1 - min1)).clamp(0.0, 1.0);
      return 0.5 * v;
    } else {
      final v = ((size - min2) / (max2 - min2)).clamp(0.0, 1.0);
      return 0.5 + 0.5 * v;
    }
  }

  // Map slider value (0.0-1.0) back to actual brush size (1-600)
  double _sliderValueToSize(double v) {
    const min1 = 1.0;
    const max1 = 100.0;
    const min2 = 100.0;
    const max2 = 600.0;

    if (v <= 0.5) {
      final local = v / 0.5; // 0..1
      return min1 + local * (max1 - min1); // 1..100
    } else {
      final local = (v - 0.5) / 0.5; // 0..1
      return min2 + local * (max2 - min2); // 100..600
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvasControllerProvider);
    final ctrl = ref.read(canvasControllerProvider);

    final cs = Theme.of(context).colorScheme;

    // Glow values from controller (0..1)
    final effectiveGlow = controller.brushGlow.clamp(0.0, 1.0);
    final glowRadius = controller.glowRadius.clamp(0.0, 1.0);
    final glowOpacity = controller.glowOpacity.clamp(0.0, 1.0);
    final glowBrightness = controller.glowBrightness.clamp(0.0, 1.0);

    // UI (0..100) versions for sliders
    final glowUi = (effectiveGlow * 100.0).clamp(0.0, 100.0);
    final glowRadiusUi = (glowRadius * 100.0).clamp(0.0, 100.0);
    final glowOpacityUi = (glowOpacity * 100.0).clamp(0.0, 100.0);
    final glowBrightnessUi = (glowBrightness * 100.0).clamp(0.0, 100.0);

    // Core opacity UI (0..100)
    final coreUi =
        (controller.coreOpacity.clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);

    final bool advancedGlow = controller.advancedGlowEnabled;

    // Liquid Neon defaults (for now; later can be per-brush).
    const double defaultCoreOpacity = 0.86;
    const double defaultGlow = 0.7;
    const double defaultRadius = 0.7;
    const double defaultBrightness = 0.7;
    const double defaultOpacity = 1.0;

    bool _approxEquals(double a, double b) => (a - b).abs() < 0.001;

    // Check if we're at defaults in both simple and advanced dimensions.
    final bool coreAtDefault =
        _approxEquals(controller.coreOpacity, defaultCoreOpacity);

    final bool simpleGlowAtDefault =
        _approxEquals(controller.brushGlow, defaultGlow);

    final bool advancedGlowAtDefault =
        _approxEquals(controller.glowRadius, defaultRadius) &&
            _approxEquals(controller.glowBrightness, defaultBrightness) &&
            _approxEquals(controller.glowOpacity, defaultOpacity);

    // Reset button appears if:
    // - Advanced OFF: any of (core, simple glow) differ from defaults
    // - Advanced ON : any of (core, radius, brightness, opacity) differ
    final bool showResetButton = advancedGlow
        ? !(coreAtDefault && advancedGlowAtDefault)
        : !(coreAtDefault && simpleGlowAtDefault);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
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

            // ---------------------------
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

            const SizedBox(height: 6),

            // ---------------------------
            // Core strength slider
            // ---------------------------
            Row(
              children: [
                const Text(
                  'Core strength',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: coreUi,
                    min: 0.0,
                    max: 100.0,
                    onChanged: (v) {
                      final nv = (v / 100.0).clamp(0.0, 1.0);
                      ctrl.setCoreOpacity(nv);
                    },
                  ),
                ),
                Text(
                  coreUi.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ---------------------------
            // Glow controls
            // ---------------------------

            // 1) Single combined Glow slider (always shown).
            Row(
              children: [
                Text(
                  'Glow',
                  style: TextStyle(
                    color: advancedGlow ? Colors.white54 : Colors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: glowUi,
                    min: 0.0,
                    max: 100.0,
                    onChanged: advancedGlow
                        ? null // disabled when advanced glow is ON
                        : (v) {
                            final nv = (v / 100.0).clamp(0.0, 1.0);
                            ctrl.setBrushGlow(nv);
                          },
                  ),
                ),
                Text(
                  glowUi.toStringAsFixed(0),
                  style: TextStyle(
                    color: advancedGlow ? Colors.white54 : Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // 2) Advanced glow toggle row + Reset button (right aligned)
            Row(
              children: [
                Switch(
                  value: advancedGlow,
                  onChanged: (v) {
                    ctrl.setAdvancedGlowEnabled(v);
                  },
                ),
                const SizedBox(width: 8),
                const Text(
                  'Advanced glow',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                if (showResetButton)
                  TextButton(
                    onPressed: () {
                      // Reset to default "Liquid Neon" profile.
                      ctrl.setCoreOpacity(defaultCoreOpacity);

                      if (advancedGlow) {
                        // Advanced mode: reset per-channel glow.
                        ctrl.setGlowRadius(defaultRadius);
                        ctrl.setGlowBrightness(defaultBrightness);
                        ctrl.setGlowOpacity(defaultOpacity);
                      } else {
                        // Simple mode: reset unified glow slider.
                        ctrl.setBrushGlow(defaultGlow);
                      }
                    },
                    child: const Text('Reset'),
                  ),
              ],
            ),

            // 3) Advanced sliders (shown only when advanced glow is ON)
            if (advancedGlow) ...[
              const SizedBox(height: 4),

              // Radius slider
              Row(
                children: [
                  const Text(
                    'Radius',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: glowRadiusUi,
                      min: 0.0,
                      max: 100.0,
                      onChanged: (v) {
                        final nv = (v / 100.0).clamp(0.0, 1.0);
                        ctrl.setGlowRadius(nv);
                      },
                    ),
                  ),
                  Text(
                    glowRadiusUi.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 2),

              // Opacity slider
              Row(
                children: [
                  const Text(
                    'Opacity',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: glowOpacityUi,
                      min: 0.0,
                      max: 100.0,
                      onChanged: (v) {
                        final nv = (v / 100.0).clamp(0.0, 1.0);
                        ctrl.setGlowOpacity(nv);
                      },
                    ),
                  ),
                  Text(
                    glowOpacityUi.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 2),

              // Brightness slider
              Row(
                children: [
                  const Text(
                    'Brightness',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: glowBrightnessUi,
                      min: 0.0,
                      max: 100.0,
                      onChanged: (v) {
                        final nv = (v / 100.0).clamp(0.0, 1.0);
                        ctrl.setGlowBrightness(nv);
                      },
                    ),
                  ),
                  Text(
                    glowBrightnessUi.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // ---------------------------
            // Palette / Colors
            // ---------------------------
            _PaletteRow(controller: controller, ctrl: ctrl, cs: cs),
          ],
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final CanvasController controller;
  final CanvasController ctrl;
  final ColorScheme cs;

  const _PaletteRow({
    required this.controller,
    required this.ctrl,
    required this.cs,
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
                      ctrl.updatePalette(index, picked.value);
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
