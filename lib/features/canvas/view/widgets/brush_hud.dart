import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/canvas_controller.dart';
import '../../../../core/models/brush.dart';
import 'color_wheel_dialog.dart';
import 'brush_preview.dart';
import 'synth_knob.dart';

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

  final ValueNotifier<bool> _knobIsActive = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _knobIsActive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvasControllerProvider);
    final ctrl = ref.read(canvasControllerProvider);

    final effectiveGlow = controller.brushGlow.clamp(0.0, 1.0);
    final glowRadius = controller.glowRadius.clamp(0.0, 1.0);
    final glowOpacity = controller.glowOpacity.clamp(0.0, 1.0);
    final glowBrightness = controller.glowBrightness.clamp(0.0, 1.0);

    final glowUi = (effectiveGlow * 100.0).clamp(0.0, 100.0);
    final glowRadiusUi = (glowRadius * 300.0).clamp(0.0, 300.0);
    final glowOpacityUi = (glowOpacity * 100.0).clamp(0.0, 100.0);
    final glowBrightnessUi = (glowBrightness * 100.0).clamp(0.0, 100.0);

    final coreUi =
        (controller.coreOpacity.clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);

    final sizeUi = controller.brushSize.clamp(1.0, 600.0);

    final bool advancedGlow = controller.advancedGlowEnabled;

    const double defaultCoreOpacity = 0.86;
    const double defaultGlow = 0.3;

    const double defaultRadius = 15.0 / 300.0;
    const double defaultBrightness = 50.0 / 100.0;
    const double defaultOpacity = 1.0;

    bool approxEquals(double a, double b) => (a - b).abs() < 0.001;

    final bool coreAtDefault =
        approxEquals(controller.coreOpacity, defaultCoreOpacity);

    final bool simpleGlowAtDefault =
        approxEquals(controller.brushGlow, defaultGlow);

    final bool advancedGlowAtDefault =
        approxEquals(controller.glowRadius, defaultRadius) &&
            approxEquals(controller.glowBrightness, defaultBrightness) &&
            approxEquals(controller.glowOpacity, defaultOpacity);

    final bool showResetButton = advancedGlow
        ? !(coreAtDefault && advancedGlowAtDefault)
        : !(coreAtDefault && simpleGlowAtDefault);

    final sectionBg = Colors.white.withValues(alpha: 0.10);
    final sectionBorderColor = _neonCyan.withValues(alpha: 0.35);
    final sectionShadowColor = _neonPink.withValues(alpha: 0.18);

    void onKnobInteraction(bool active) => _knobIsActive.value = active;

    Widget headerTile({
      required String title,
      required bool expanded,
      required VoidCallback onTap,
    }) {
      return Container(
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
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
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
      );
    }

    Widget sectionFrame({required Widget child}) {
      return Container(
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
        child: child,
      );
    }

    // ✅ FULL SCREEN HUD
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            children: [
              // ✅ PREVIEW ALWAYS PINNED TOP
              SizedBox(
                height: 210,
                width: double.infinity,
                child: BrushPreview(controller: controller),
              ),

              // ✅ everything below scrolls
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _knobIsActive,
                    builder: (context, active, _) {
                      return SingleChildScrollView(
                        physics: active
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ===========================
                            // BRUSH SECTION
                            // ===========================
                            sectionFrame(
                              child: Column(
                                children: [
                                  headerTile(
                                    title: 'Brush',
                                    expanded: _brushExpanded,
                                    onTap: () => setState(
                                        () => _brushExpanded = !_brushExpanded),
                                  ),
                                  if (_brushExpanded) ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 36,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: Brush.all.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 8),
                                        itemBuilder: (context, index) {
                                          final brush = Brush.all[index];
                                          final isSelected =
                                              controller.brushId == brush.id;
                                          return GestureDetector(
                                            onTap: () =>
                                                ctrl.setBrush(brush.id),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha:
                                                      isSelected ? 0.20 : 0.06,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? _neonCyan.withValues(
                                                          alpha: 0.8)
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
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        SynthKnob(
                                          label: 'Size',
                                          value: sizeUi,
                                          min: 1.0,
                                          max: 600.0,
                                          defaultValue: 10.0,
                                          valueFormatter: (v) =>
                                              v.toStringAsFixed(0),
                                          onInteractionChanged:
                                              onKnobInteraction,
                                          onChanged: (v) => ctrl.setBrushSize(
                                              v.clamp(1.0, 600.0)),
                                        ),
                                        SynthKnob(
                                          label: 'Opacity',
                                          value: coreUi,
                                          min: 0.0,
                                          max: 100.0,
                                          defaultValue:
                                              defaultCoreOpacity * 100.0,
                                          valueFormatter: (v) =>
                                              '${v.toStringAsFixed(0)}%',
                                          onInteractionChanged:
                                              onKnobInteraction,
                                          onChanged: (ui) {
                                            final nv =
                                                (ui / 100.0).clamp(0.0, 1.0);
                                            ctrl.setCoreOpacity(nv);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ===========================
                            // GLOW SECTION
                            // ===========================
                            sectionFrame(
                              child: Column(
                                children: [
                                  headerTile(
                                    title: 'Glow',
                                    expanded: _glowExpanded,
                                    onTap: () => setState(
                                        () => _glowExpanded = !_glowExpanded),
                                  ),
                                  if (_glowExpanded) ...[
                                    const SizedBox(height: 10),
                                    Opacity(
                                      opacity: advancedGlow ? 0.45 : 1.0,
                                      child: IgnorePointer(
                                        ignoring: advancedGlow,
                                        child: Center(
                                          child: SynthKnob(
                                            label: 'Glow',
                                            value: glowUi,
                                            min: 0.0,
                                            max: 100.0,
                                            defaultValue: defaultGlow * 100.0,
                                            valueFormatter: (v) =>
                                                v.toStringAsFixed(0),
                                            onInteractionChanged:
                                                onKnobInteraction,
                                            onChanged: (v) {
                                              final nv =
                                                  (v / 100.0).clamp(0.0, 1.0);
                                              ctrl.setBrushGlow(nv);
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Switch(
                                          value: advancedGlow,
                                          onChanged:
                                              ctrl.setAdvancedGlowEnabled,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Advanced glow',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        ),
                                        const Spacer(),
                                        if (showResetButton)
                                          TextButton(
                                            onPressed: () {
                                              ctrl.setCoreOpacity(
                                                  defaultCoreOpacity);
                                              if (advancedGlow) {
                                                ctrl.setGlowRadius(
                                                    defaultRadius);
                                                ctrl.setGlowBrightness(
                                                    defaultBrightness);
                                                ctrl.setGlowOpacity(
                                                    defaultOpacity);
                                              } else {
                                                ctrl.setBrushGlow(defaultGlow);
                                              }
                                            },
                                            child: const Text('Reset'),
                                          ),
                                      ],
                                    ),
                                    if (advancedGlow) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        alignment: WrapAlignment.center,
                                        children: [
                                          SynthKnob(
                                            label: 'Radius',
                                            value: glowRadiusUi,
                                            min: 0.0,
                                            max: 300.0,
                                            defaultValue: defaultRadius * 300.0,
                                            valueFormatter: (v) =>
                                                v.toStringAsFixed(0),
                                            onInteractionChanged:
                                                onKnobInteraction,
                                            onChanged: (ui) =>
                                                ctrl.setGlowRadius((ui / 300.0)
                                                    .clamp(0.0, 1.0)),
                                          ),
                                          SynthKnob(
                                            label: 'Opacity',
                                            value: glowOpacityUi,
                                            min: 0.0,
                                            max: 100.0,
                                            defaultValue:
                                                defaultOpacity * 100.0,
                                            valueFormatter: (v) =>
                                                '${v.toStringAsFixed(0)}%',
                                            onInteractionChanged:
                                                onKnobInteraction,
                                            onChanged: (ui) =>
                                                ctrl.setGlowOpacity((ui / 100.0)
                                                    .clamp(0.0, 1.0)),
                                          ),
                                          SynthKnob(
                                            label: 'Bright',
                                            value: glowBrightnessUi,
                                            min: 0.0,
                                            max: 100.0,
                                            defaultValue:
                                                defaultBrightness * 100.0,
                                            valueFormatter: (v) =>
                                                v.toStringAsFixed(0),
                                            onInteractionChanged:
                                                onKnobInteraction,
                                            onChanged: (ui) => ctrl
                                                .setGlowBrightness((ui / 100.0)
                                                    .clamp(0.0, 1.0)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Text(
                                            'Scale with size',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                          ),
                                          const SizedBox(width: 8),
                                          Switch(
                                            value: controller
                                                .glowRadiusScalesWithSize,
                                            onChanged: ctrl
                                                .setGlowRadiusScalesWithSize,
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Tip: drag to turn • long-press for exact value • double-tap to reset',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 10),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            _PaletteRow(controller: controller, ctrl: ctrl),
                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
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
