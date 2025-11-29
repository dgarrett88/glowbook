import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/canvas_controller.dart';
import '../../../../core/models/brush.dart';
import 'color_wheel_dialog.dart';
import 'brush_preview.dart';

// Global neon colours so they're available everywhere in this file.
const _neonCyan = Color(0xFF00F5FF);
const _neonPink = Color(0xFFFF4DFF);

class BrushHUD extends ConsumerStatefulWidget {
  const BrushHUD({super.key});

  @override
  ConsumerState<BrushHUD> createState() => _BrushHUDState();
}

class _BrushHUDState extends ConsumerState<BrushHUD> {
  bool _brushExpanded = true;
  bool _glowExpanded = true;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvasControllerProvider);
    final ctrl = ref.read(canvasControllerProvider);

    // Glow values from controller
    final effectiveGlow = controller.brushGlow.clamp(0.0, 1.0);
    final glowRadius = controller.glowRadius.clamp(0.0, 1.0);
    final glowOpacity = controller.glowOpacity.clamp(0.0, 1.0);
    final glowBrightness = controller.glowBrightness.clamp(0.0, 1.0);

    // UI values
// - Glow (simple)  0..100
// - Radius         0..300
// - Opacity        0..100
// - Brightness     0..100  (70 = base colour)
    final glowUi = (effectiveGlow * 100.0).clamp(0.0, 100.0);
    final glowRadiusUi = (glowRadius * 300.0).clamp(0.0, 300.0);
    final glowOpacityUi = (glowOpacity * 100.0).clamp(0.0, 100.0);
    final glowBrightnessUi = (glowBrightness * 100.0).clamp(0.0, 100.0);

    // Core opacity UI (0..100)
    final coreUi =
        (controller.coreOpacity.clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);

    // Brush size UI (direct, 1..600)
    final sizeUi = controller.brushSize.clamp(1.0, 600.0);

    final bool advancedGlow = controller.advancedGlowEnabled;

    // These are the "Liquid Neon" defaults (could be per-brush).
    const double defaultCoreOpacity = 0.86;
    const double defaultGlow = 0.3;

// Advanced glow defaults:
// Radius: 15 (on 0–300 UI scale)  -> 15 / 300 = 0.05
// Brightness: 50 (on 0–100 UI scale) -> 0.5
    const double defaultRadius = 15.0 / 300.0;
    const double defaultBrightness = 50.0 / 100.0;

    const double defaultOpacity = 1.0;

    bool approxEquals(double a, double b) => (a - b).abs() < 0.001;

    // Check if we're at defaults in both simple and advanced dimensions.
    final bool coreAtDefault =
        approxEquals(controller.coreOpacity, defaultCoreOpacity);

    final bool simpleGlowAtDefault =
        approxEquals(controller.brushGlow, defaultGlow);

    final bool advancedGlowAtDefault =
        approxEquals(controller.glowRadius, defaultRadius) &&
            approxEquals(controller.glowBrightness, defaultBrightness) &&
            approxEquals(controller.glowOpacity, defaultOpacity);

    // Reset button appears if:
    // - Advanced OFF: any of (core, simple glow) differ from defaults
    // - Advanced ON : any of (core, radius, brightness, opacity) differ
    final bool showResetButton = advancedGlow
        ? !(coreAtDefault && advancedGlowAtDefault)
        : !(coreAtDefault && simpleGlowAtDefault);

    // Neon / glassy styling
    final sectionBg = Colors.white.withValues(alpha: 0.10); // brighter than HUD
    final sectionBorderColor = _neonCyan.withValues(alpha: 0.35);
    final sectionShadowColor = _neonPink.withValues(alpha: 0.18);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===========================
            // ALWAYS-VISIBLE BRUSH PREVIEW
            // ===========================
            SizedBox(
              height: 160,
              width: double.infinity,
              child: BrushPreview(controller: controller),
            ),

            const SizedBox(height: 12),

            // ===========================
            // BRUSH SECTION (GLASSY FRAME)
            // ===========================
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: sectionBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sectionBorderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: sectionShadowColor,
                    blurRadius: 16,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  // Header – slightly darker glass strip
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            _brushExpanded = !_brushExpanded;
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Brush',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _brushExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (_brushExpanded) ...[
                    const SizedBox(height: 8),

                    // Brush selector row
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
                                  alpha: isSelected ? 0.20 : 0.06,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isSelected
                                      ? _neonCyan.withValues(alpha: 0.8)
                                      : Colors.white24,
                                  width: isSelected ? 1.2 : 1.0,
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

                    const SizedBox(height: 10),

                    // Size | Opacity numeric row
                    Row(
                      children: [
                        // Size
                        Expanded(
                          child: NumberDragField(
                            value: sizeUi,
                            min: 1,
                            max: 600,
                            decimals: 1,
                            suffix: null,
                            dragSensitivity: 1.0, // units per pixel
                            onChanged: (ui) {
                              ctrl.setBrushSize(ui.clamp(1.0, 600.0));
                            },
                          ),
                        ),

                        // Divider
                        Container(
                          width: 1,
                          height: 32,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: Colors.white.withValues(alpha: 0.14),
                        ),

                        // Core opacity
                        Expanded(
                          child: NumberDragField(
                            value: coreUi,
                            min: 0,
                            max: 100,
                            decimals: 1,
                            suffix: null,
                            dragSensitivity: 0.4,
                            onChanged: (ui) {
                              final nv = (ui / 100.0).clamp(0.0, 1.0);
                              ctrl.setCoreOpacity(nv);
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Labels row: Size   Opacity
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'size',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'opacity',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Gap so HUD bg shows between sections
            const SizedBox(height: 10),

            // ===========================
            // GLOW SECTION (GLASSY FRAME)
            // ===========================
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: sectionBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sectionBorderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: sectionShadowColor,
                    blurRadius: 16,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  // Header
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            _glowExpanded = !_glowExpanded;
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Glow',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _glowExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (_glowExpanded) ...[
                    const SizedBox(height: 8),

                    // Simple unified Glow slider
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

                    // Advanced glow toggle row + Reset button
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

                    // Advanced controls – compact 3-column layout
                    if (advancedGlow) ...[
                      const SizedBox(height: 6),

                      // Values row:  Radius | Opacity | Brightness
                      Row(
                        children: [
                          // Radius (0..300)
                          Expanded(
                            child: NumberDragField(
                              value: glowRadiusUi,
                              min: 0,
                              max: 300,
                              decimals: 1,
                              suffix: null,
                              dragSensitivity: 0.4,
                              onChanged: (ui) {
                                final nv = (ui / 300.0).clamp(0.0, 1.0);
                                ctrl.setGlowRadius(nv);
                              },
                            ),
                          ),

                          // Divider
                          Container(
                            width: 1,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: Colors.white.withValues(alpha: 0.14),
                          ),

                          // Opacity (0..100)
                          Expanded(
                            child: NumberDragField(
                              value: glowOpacityUi,
                              min: 0,
                              max: 100,
                              decimals: 1,
                              suffix: null,
                              dragSensitivity: 0.4,
                              onChanged: (ui) {
                                final nv = (ui / 100.0).clamp(0.0, 1.0);
                                ctrl.setGlowOpacity(nv);
                              },
                            ),
                          ),

                          // Divider
                          Container(
                            width: 1,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: Colors.white.withValues(alpha: 0.14),
                          ),

                          // Brightness (0..100)
                          Expanded(
                            child: NumberDragField(
                              value: glowBrightnessUi,
                              min: 0,
                              max: 100,
                              decimals: 1,
                              suffix: null,
                              dragSensitivity: 0.4,
                              onChanged: (ui) {
                                // Map 0..100 UI -> 0..1 stored
                                final nv = (ui / 100.0).clamp(0.0, 1.0);
                                ctrl.setGlowBrightness(nv);
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Labels row: radius   opacity   brightness
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'radius',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'opacity',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'brightness',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Radius scaling toggle
                      Row(
                        children: [
                          const Text(
                            'Scale with size',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: controller.glowRadiusScalesWithSize,
                            onChanged: (value) {
                              ctrl.setGlowRadiusScalesWithSize(value);
                            },
                            activeThumbColor: Colors.white,
                            activeTrackColor: Colors.white24,
                            inactiveThumbColor: Colors.white54,
                            inactiveTrackColor: Colors.white10,
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ---------------------------
            // Palette / Colors
            // ---------------------------
            _PaletteRow(controller: controller, ctrl: ctrl),
          ],
        ),
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
                        color: isSelected ? _neonCyan : Colors.black54,
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

/// Numeric field that you can tap to edit or drag up/down to change.
/// Used for fine-tuning values like size, opacity, radius, brightness.
class NumberDragField extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int decimals;
  final double dragSensitivity; // base units per pixel of vertical drag
  final String? suffix;
  final ValueChanged<double> onChanged;

  const NumberDragField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.dragSensitivity,
    required this.onChanged,
    this.suffix,
  });

  @override
  State<NumberDragField> createState() => _NumberDragFieldState();
}

class _NumberDragFieldState extends State<NumberDragField> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(widget.min, widget.max);
  }

  @override
  void didUpdateWidget(covariant NumberDragField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local value in sync when external value changes (e.g. reset button)
    if (widget.value != oldWidget.value) {
      _value = widget.value.clamp(widget.min, widget.max);
    }
  }

  Future<void> _editManually() async {
    final controller = TextEditingController(
      text: _value.toStringAsFixed(widget.decimals),
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set value'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: widget.suffix,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                final parsed = double.tryParse(text);
                Navigator.of(context).pop(parsed);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final clamped = result.clamp(widget.min, widget.max);
      setState(() {
        _value = clamped;
      });
      widget.onChanged(clamped);
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;
    if (dy == 0) return;

    final absDy = dy.abs();

    // Heuristic: tiny movements = fine control,
    // medium = normal, big = coarse jumps.
    double scale;
    if (absDy < 1.0) {
      scale = 0.25; // super fine micro moves
    } else if (absDy < 4.0) {
      scale = 0.8; // fine-ish
    } else if (absDy < 10.0) {
      scale = 1.5; // normal-ish
    } else {
      scale = 2.5; // you’re swiping hard, move faster
    }

    final delta = -dy * widget.dragSensitivity * scale;
    if (delta == 0) return;

    final next = (_value + delta).clamp(widget.min, widget.max);
    if (next != _value) {
      setState(() {
        _value = next;
      });
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text =
        _value.toStringAsFixed(widget.decimals) + (widget.suffix ?? '');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editManually,
      onVerticalDragUpdate: _handleVerticalDragUpdate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
