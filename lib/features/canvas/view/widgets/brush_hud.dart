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
  // Local multi-glow state (UI only, maps down into single brushGlow)
  bool _linkGlowSettings = true;
  double _glowRadius = 0.7;
  double _glowOpacity = 1.0;
  double _glowBrightness = 0.7;
  bool _initialised = false;

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

  void _syncFromController(CanvasController controller) {
    if (_initialised) return;
    _initialised = true;

    final g = controller.brushGlow.clamp(0.0, 1.0);
    _glowRadius = g;
    _glowBrightness = g;
    _glowOpacity = 1.0;
    _linkGlowSettings = true;
  }

  double _computeEffectiveGlow() {
    final r = _glowRadius.clamp(0.0, 1.0);
    final b = _glowBrightness.clamp(0.0, 1.0);
    final o = _glowOpacity.clamp(0.0, 1.0);
    return ((r + b) * 0.5) * o;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvasControllerProvider);
    final ctrl = ref.read(canvasControllerProvider);

    _syncFromController(controller);

    // UI glow values
    final glowUi = (controller.brushGlow * 100.0).clamp(0.0, 100.0);
    final glowRadiusUi = (_glowRadius * 100.0).clamp(0.0, 100.0);
    final glowOpacityUi = (_glowOpacity * 100.0).clamp(0.0, 100.0);
    final glowBrightnessUi = (_glowBrightness * 100.0).clamp(0.0, 100.0);

    final screenH = MediaQuery.of(context).size.height;

    return SizedBox(
        height: screenH * 0.85, // << 85% height
        child: Container(
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

                const SizedBox(height: 8),

                // ---------------------------
                // Glow controls
                // ---------------------------
                Row(
                  children: [
                    const Text(
                      'Link glow settings',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _linkGlowSettings,
                      onChanged: (v) {
                        setState(() {
                          _linkGlowSettings = v;
                          if (v) {
                            final g = controller.brushGlow.clamp(0.0, 1.0);
                            _glowRadius = g;
                            _glowBrightness = g;
                            _glowOpacity = 1.0;
                          }
                        });
                        final eff = _linkGlowSettings
                            ? _glowRadius
                            : _computeEffectiveGlow();
                        ctrl.setBrushGlow(eff);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                if (_linkGlowSettings) ...[
                  // Unified glow slider (behaves like your old "Glow size" slider)
                  Row(
                    children: [
                      const Text(
                        'Glow',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: glowUi,
                          min: 0.0,
                          max: 100.0,
                          onChanged: (v) {
                            final nv = (v / 100.0).clamp(0.0, 1.0);
                            setState(() {
                              _glowRadius = nv;
                              _glowBrightness = nv;
                              _glowOpacity = 1.0;
                            });
                            ctrl.setBrushGlow(nv);
                          },
                        ),
                      ),
                      Text(
                        glowUi.toStringAsFixed(0),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ] else ...[
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
                            setState(() {
                              _glowRadius = (v / 100.0).clamp(0.0, 1.0);
                            });
                            ctrl.setBrushGlow(_computeEffectiveGlow());
                          },
                        ),
                      ),
                      Text(
                        glowRadiusUi.toStringAsFixed(0),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
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
                            setState(() {
                              _glowOpacity = (v / 100.0).clamp(0.0, 1.0);
                            });
                            ctrl.setBrushGlow(_computeEffectiveGlow());
                          },
                        ),
                      ),
                      Text(
                        glowOpacityUi.toStringAsFixed(0),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
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
                            setState(() {
                              _glowBrightness = (v / 100.0).clamp(0.0, 1.0);
                            });
                            ctrl.setBrushGlow(_computeEffectiveGlow());
                          },
                        ),
                      ),
                      Text(
                        glowBrightnessUi.toStringAsFixed(0),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // ---------------------------
                // Palette / Colors
                // ---------------------------
                _PaletteRow(controller: controller, ctrl: ctrl),
              ],
            ),
          ),
        ));
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
