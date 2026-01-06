import 'package:flutter/material.dart';

import '../../state/canvas_controller.dart';
import '../../state/glow_blend.dart' as gb;

import '../layer_panel.dart'; // widgets -> view
import 'glow_blend_dropdown.dart';

import 'brush_hud.dart';
import 'color_wheel_dialog.dart';
import 'dice_dots_icon.dart';

class BottomDock extends StatefulWidget {
  final CanvasController controller;

  /// ✅ kept for backwards-compat with canvas_screen.dart
  final bool showLayers;

  /// ✅ kept for backwards-compat with canvas_screen.dart
  final VoidCallback onToggleLayers;

  const BottomDock({
    super.key,
    required this.controller,
    required this.showLayers,
    required this.onToggleLayers,
  });

  @override
  State<BottomDock> createState() => _BottomDockState();
}

class _BottomDockState extends State<BottomDock> {
  final PageController _page = PageController();
  int _pageIndex = 0;

  // ✅ lets us resize programmatically from the handle drag
  final DraggableScrollableController _layersSheetCtrl =
      DraggableScrollableController();

  CanvasController get controller => widget.controller;

  @override
  void dispose() {
    _page.dispose();
    _layersSheetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bool selectOn = controller.selectionMode;

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
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 30,
                    spreadRadius: 10,
                    color: Colors.black26,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // swipe dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Dot(active: _pageIndex == 0),
                      const SizedBox(width: 6),
                      _Dot(active: _pageIndex == 1),
                    ],
                  ),
                  const SizedBox(height: 6),

                  SizedBox(
                    height: 58,
                    child: PageView(
                      controller: _page,
                      onPageChanged: (i) => setState(() => _pageIndex = i),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Page 1: brush/draw stuff
                        _DockRow(
                          children: [
                            _DockButton(
                              icon: Icons.brush,
                              label: 'Brush',
                              onTap: () => _openBrushSheet(context, cs),
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
                                  builder: (_) => ColorWheelDialog(
                                    initial: Color(controller.color),
                                  ),
                                );
                                if (picked != null) {
                                  controller.setColor(picked.toARGB32());
                                }
                              },
                            ),
                            _DockButton(
                              customIcon: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Color(controller.backgroundColor),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                              ),
                              label: 'BG',
                              onTap: () async {
                                final picked = await showDialog<Color?>(
                                  context: context,
                                  barrierDismissible: true,
                                  builder: (_) => ColorWheelDialog(
                                    initial: Color(controller.backgroundColor),
                                  ),
                                );
                                if (picked != null) {
                                  controller
                                      .setBackgroundColor(picked.toARGB32());
                                }
                              },
                            ),
                            _DockButton(
                              icon: Icons.auto_awesome,
                              label: 'Blend',
                              onTap: () => _openBlendSheet(context),
                            ),
                          ],
                        ),

                        // Page 2: layers + select
                        _DockRow(
                          children: [
                            _DockButton(
                              customIcon: Icon(
                                Icons.layers,
                                size: 22,
                                color: widget.showLayers
                                    ? Colors.cyanAccent
                                    : Colors.white,
                              ),
                              label: 'Layers',
                              // ✅ OPTION A: open resizable sheet
                              onTap: () => _openLayersSheet(context),
                              // long-press keeps your old toggle behaviour
                              onLongPress: widget.onToggleLayers,
                            ),
                            _DockButton(
                              customIcon: Icon(
                                Icons.select_all,
                                size: 22,
                                color:
                                    selectOn ? Colors.cyanAccent : Colors.white,
                              ),
                              label: selectOn ? 'Select ON' : 'Select',
                              onTap: () => controller
                                  .setSelectionMode(!controller.selectionMode),
                              onLongPress: () {
                                if (controller.selectionMode) {
                                  controller.clearSelection();
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- helpers ---------------------------------------------------------------

  void _openBrushSheet(BuildContext context, ColorScheme cs) {
    showModalBottomSheet(
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: BrushHUD(),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openLayersSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ EDIT THESE:
    const double kInitial = 0.42; // default height
    const double kMin = 0.22; // smallest
    const double kMax = 0.85; // biggest

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final screenH = MediaQuery.of(ctx).size.height;

        return DraggableScrollableSheet(
          controller: _layersSheetCtrl,
          initialChildSize: kInitial,
          minChildSize: kMin,
          maxChildSize: kMax,
          expand: false,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    // ✅ drag handle that ALWAYS resizes the sheet (not the list)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) {
                        // drag up => bigger
                        final delta = -d.delta.dy / screenH;
                        final next =
                            (_layersSheetCtrl.size + delta).clamp(kMin, kMax);
                        _layersSheetCtrl.jumpTo(next);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: LayerPanel(
                        scrollController: scrollController,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
      barrierColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    offset: Offset(0, -2),
                    color: Colors.black26,
                  ),
                ],
              ),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: AnimatedBuilder(
                    animation: gb.GlowBlendState.I,
                    builder: (context, _) {
                      final state = gb.GlowBlendState.I;
                      return Row(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                                minWidth: 90, maxWidth: 140),
                            child: GlowBlendDropdown(controller: controller),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Slider(
                              value: state.intensity,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (v) =>
                                  gb.GlowBlendState.I.setIntensity(v),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${(state.intensity * 100).round()}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DockRow extends StatelessWidget {
  final List<Widget> children;
  const _DockRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 0,
        children: children,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 18 : 8,
      height: 6,
      decoration: BoxDecoration(
        color: active ? Colors.white70 : Colors.white24,
        borderRadius: BorderRadius.circular(999),
      ),
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
        onTap();
        Navigator.of(context).pop();
      },
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
    super.key,
    this.icon,
    this.customIcon,
    required this.label,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final ic = customIcon ?? Icon(icon, size: 22);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
