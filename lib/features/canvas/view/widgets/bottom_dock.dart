import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';
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
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: const [
            BoxShadow(
                blurRadius: 12, offset: Offset(0, -2), color: Colors.black26)
          ],
        ),
        child: Row(
          children: [
            _DockButton(
              icon: Icons.brush,
              label: 'Brush',
              onTap: () => showModalBottomSheet(
                context: context,
                useSafeArea: true,
                backgroundColor: cs.surface,
                builder: (_) => BrushHUD(),
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
          ],
        ),
      ),
    );
  }

  void _cycleSymmetry() {
    // Cycle order: Off -> Vertical -> Horizontal -> Quad -> Off
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

  Widget _symIcon(SymmetryMode m) {
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
}

class _SymRow extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const _SymRow(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon,
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _DockButton(
      {super.key,
      this.icon,
      this.customIcon,
      required this.label,
      required this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ic = customIcon ?? Icon(icon, size: 22, color: cs.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
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
