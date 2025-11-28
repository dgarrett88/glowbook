import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';
import '../../state/glow_blend.dart' as gb;

import 'brush_hud.dart';
import 'color_wheel_dialog.dart';
import 'dice_dots_icon.dart';

class BottomDock extends StatelessWidget {
  final CanvasController controller;
  const BottomDock({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.35),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 30,
                spreadRadius: 10,
                color: Colors.black26,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _DockButton(
                icon: Icons.brush,
                label: 'Brush',
                onTap: () => showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (ctx) {
                    final screenH = MediaQuery.of(ctx).size.height;
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: screenH * 0.85,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: BrushHUD(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _DockButton(
                customIcon: _symIcon(controller.symmetry),
                label: 'Sym',
                onTap: _cycleSymmetry,
                onLongPress: () => _openSymmetryMenu(context),
              ),
              _DockButton(
                customIcon: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color(controller.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                label: 'Color',
                onTap: () async {
                  final picked = await showDialog<Color?>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) =>
                        ColorWheelDialog(initial: Color(controller.color)),
                  );
                  if (picked != null) controller.setColor(picked.value);
                },
              ),
              _DockButton(
                icon: Icons.auto_awesome,
                label: 'Blend',
                onTap: () => _openBlendSheet(context),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleSymmetry() {
    switch (controller.symmetry) {
      case SymmetryMode.off:
        controller.setSymmetry(SymmetryMode.mirrorV);
        break;
      case SymmetryMode.mirrorV:
        controller.setSymmetry(SymmetryMode.mirrorH);
        break;
      case SymmetryMode.mirrorH:
        controller.setSymmetry(SymmetryMode.quad);
        break;
      case SymmetryMode.quad:
        controller.setSymmetry(SymmetryMode.off);
        break;
    }
  }

  static Widget _symIcon(SymmetryMode m) {
    switch (m) {
      case SymmetryMode.off:
        return const Icon(Icons.blur_circular);
      case SymmetryMode.mirrorV:
        return const DiceDotsIcon(pattern: DiceDotsPattern.twoH);
      case SymmetryMode.mirrorH:
        return const DiceDotsIcon(pattern: DiceDotsPattern.twoV);
      case SymmetryMode.quad:
        return const DiceDotsIcon(pattern: DiceDotsPattern.four);
    }
  }

  Future<void> _openSymmetryMenu(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              runSpacing: 12,
              children: [
                _SymRow('Off', const Icon(Icons.blur_circular),
                    () => controller.setSymmetry(SymmetryMode.off)),
                // NOTE: labels swapped per your request
                _SymRow(
                    'Horizontal',
                    const DiceDotsIcon(pattern: DiceDotsPattern.twoH),
                    () => controller.setSymmetry(SymmetryMode.mirrorV)),
                _SymRow(
                    'Vertical',
                    const DiceDotsIcon(pattern: DiceDotsPattern.twoV),
                    () => controller.setSymmetry(SymmetryMode.mirrorH)),
                _SymRow(
                    'Quad',
                    const DiceDotsIcon(pattern: DiceDotsPattern.four),
                    () => controller.setSymmetry(SymmetryMode.quad)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openBlendSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final screenH = MediaQuery.of(ctx).size.height;
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: screenH * 0.45,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AnimatedBuilder(
                  animation: gb.GlowBlendState.I,
                  builder: (context, _) {
                    final state = gb.GlowBlendState.I;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Blend modes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final mode in gb.GlowBlend.values)
                              ChoiceChip(
                                label: Text(mode.label),
                                selected: state.mode == mode,
                                onSelected: (_) {
                                  gb.GlowBlendState.I.setMode(mode);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Intensity: ${(state.intensity * 100).round()}%',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Slider(
                          value: state.intensity,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            gb.GlowBlendState.I.setIntensity(v);
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SymRow extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const _SymRow(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: icon,
      title: Text(label),
      onTap: () {
        onTap();
        Navigator.of(context).pop();
      },
      iconColor: cs.primary,
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DockButton({
    Key? key,
    this.icon,
    this.customIcon,
    required this.label,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ic = customIcon ??
        Icon(
          icon,
          size: 22,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // 👈 make whole padded area tappable
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ic,
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
