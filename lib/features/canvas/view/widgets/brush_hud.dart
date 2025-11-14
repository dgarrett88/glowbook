
import 'dart:async';
import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';
import '../../../../core/models/brush.dart';
import 'color_wheel_dialog.dart';

/// BrushHUD quickfix:
/// - Restores brush chips
/// - Live-updating sliders for size & glow (AnimatedBuilder on controller)
/// - Restores 8 editable color swatches (long-press opens color wheel)
class BrushHUD extends StatelessWidget {
  final CanvasController controller;
  const BrushHUD({super.key, required this.controller});

  int _columnsFor(int slots, double width){
    if (slots <= 8) return 4;     // 2 rows of 4
    if (slots <= 24) return 6;    // mid tier
    return 8;                     // dense for 32
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final slots = controller.paletteSlots.clamp(1, controller.palette.length);
        final media = MediaQuery.of(context);
        final maxHeight = media.size.height * 0.85;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + media.viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: const [
                      Icon(Icons.brush),
                      SizedBox(width: 8),
                      Text('Brush', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Brush choices (chips)
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('Liquid Neon', Brush.liquidNeon.id),
                      _chip('Soft Glow',   Brush.softGlow.id),
                      _chip('Glow Only',  Brush.glowOnly.id),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Size
                  const Text('Size'),
                  Slider(
                    value: controller.brushSize,
                    min: 1,
                    max: 40,
                    onChanged: controller.setBrushSize,
                  ),
                  const SizedBox(height: 12),
                  // Glow
                  const Text('Glow'),
                  Slider(
                    value: controller.brushGlow,
                    min: 0.0,
                    max: 3.0,
                    onChanged: (v) {
                      controller.brushGlow = v;
                      controller.notifyListeners();
                    },
                  ),
                  const SizedBox(height: 12),
                  // Colors
                  const Text('Colors (hold to edit)'),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (ctx, constraints){
                      final cols = _columnsFor(slots, constraints.maxWidth);
                      final itemSize = (constraints.maxWidth - (8.0 * (cols - 1))) / cols;
                      return GridView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: slots,
                        itemBuilder: (ctx, i){
                          final argb = controller.palette[i];
                          final selected = controller.color == argb;
                          return _SwatchTile(
                            size: itemSize,
                            argb: argb,
                            selected: selected,
                            onTapSelect: () => controller.setColor(argb),
                            onPickCommit: (c){
                              controller.updatePalette(i, c.toARGB32());
                              controller.setColor(c.toARGB32());
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: ()=> Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _chip(String label, String id){
    return Builder(
      builder: (context) {
        final hud = context.findAncestorWidgetOfExactType<BrushHUD>()!;
        final selected = hud.controller.brushId == id;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_){ hud.controller.setBrush(id); },
        );
      }
    );
  }
}

class _SwatchTile extends StatefulWidget {
  const _SwatchTile({
    required this.size,
    required this.argb,
    required this.selected,
    required this.onTapSelect,
    required this.onPickCommit,
  });

  final double size;
  final int argb;
  final bool selected;
  final VoidCallback onTapSelect;
  final ValueChanged<Color> onPickCommit;

  @override
  State<_SwatchTile> createState() => _SwatchTileState();
}

class _SwatchTileState extends State<_SwatchTile> with SingleTickerProviderStateMixin {
  static const Duration _holdDuration = Duration(milliseconds: 300);
  late final AnimationController _ring = AnimationController(vsync: this, duration: _holdDuration);

  Timer? _holdTimer;
  bool _pressing = false;
  bool _armed = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  void _startHold() {
    _cancelHold();
    setState(()=> _pressing = true);
    _ring.forward(from: 0);
    _holdTimer = Timer(_holdDuration, () async {
      if (!mounted) return;
      if (_pressing) {
        _armed = true;
        final picked = await showDialog<Color>(
          context: context,
          builder: (_) => ColorWheelDialog(initial: Color(widget.argb)),
        );
        if (!mounted) return;
        if (picked != null) {
          widget.onPickCommit(picked);
        }
        _cancelHold();
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted) setState(()=> _pressing = false);
    _ring.stop();
    _armed = false;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.selected ? Colors.white : Colors.white24;
    final spinnerSize = widget.size * 0.36;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startHold(),
      onTapUp: (_) {
        final openedDialog = _armed;
        _cancelHold();
        if (!openedDialog) {
          widget.onTapSelect();
        }
      },
      onTapCancel: _cancelHold,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: widget.size, height: widget.size,
            decoration: BoxDecoration(
              color: Color(widget.argb),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: widget.selected ? 2 : 1),
              boxShadow: widget.selected ? [const BoxShadow(color: Colors.black54, blurRadius: 6)] : null,
            ),
          ),
          IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              opacity: _pressing ? 1 : 0,
              duration: const Duration(milliseconds: 80),
              child: SizedBox(
                width: spinnerSize, height: spinnerSize,
                child: AnimatedBuilder(
                  animation: _ring,
                  builder: (context, _) {
                    return CircularProgressIndicator(
                      value: _ring.value,
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      backgroundColor: Colors.white24,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
