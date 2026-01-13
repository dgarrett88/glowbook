import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../state/canvas_controller.dart';
import '../../state/glow_blend.dart' as gb;

import '../layer_panel.dart'; // widgets -> view
import '../lfo_panel.dart'; // ✅ ADD: your LFO panel (adjust path/name if different)

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

class _BottomDockState extends State<BottomDock>
    with SingleTickerProviderStateMixin {
  final PageController _page = PageController();
  int _pageIndex = 0;

  // ✅ lets us resize programmatically from the handle/header drag
  final DraggableScrollableController _layersSheetCtrl =
      DraggableScrollableController();

  // ✅ inertial/snap animation for the sheet size
  late final AnimationController _sheetAnim;

  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();

    // Drive the sheet size directly from this controller's value.
    _sheetAnim = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (!_layersSheetCtrl.isAttached) return;
        _layersSheetCtrl.jumpTo(_sheetAnim.value);
      });
  }

  @override
  void dispose() {
    _page.dispose();
    _layersSheetCtrl.dispose();
    _sheetAnim.dispose();
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

                        // Page 2: layers + lfo + select
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
                              onTap: () => _openLayersSheet(context),
                            ),

                            // ✅ NEW: LFO button
                            _DockButton(
                              customIcon: const Icon(Icons.waves,
                                  size: 22, color: Colors.white),
                              label: 'LFO',
                              onTap: () => _openLfoSheet(context),
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

  // --- snap + motion helpers -------------------------------------------------
  // NOTE: We are intentionally NOT using these for handle/header anymore.
  // Handle/header now live inside the same scrollable as the list, so they
  // inherit the exact same "smooth glide" feel as the layers area.

  void _stopSheetMotion() {
    if (_sheetAnim.isAnimating) _sheetAnim.stop();
  }

  double _pickSnapTarget({
    required double current,
    required double v, // fraction/sec (positive = grow, negative = shrink)
    required List<double> snaps,
    required double minSize,
  }) {
    final s = snaps.toList()..sort();

    // Find nearest snap index
    int nearestIndex = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < s.length; i++) {
      final d = (current - s[i]).abs();
      if (d < bestDist) {
        bestDist = d;
        nearestIndex = i;
      }
    }

    const double closeThreshold = 0.15; // ✅ only close near bottom
    const double flickThreshold = 0.22;
    const double dragBias = 0.04; // how far user must drag past snap

    double prevSnap() => s[(nearestIndex - 1).clamp(0, s.length - 1)];
    double nextSnap() => s[(nearestIndex + 1).clamp(0, s.length - 1)];

    // ---- Flick behaviour ----
    if (v.abs() >= flickThreshold) {
      if (v > 0) {
        return nextSnap();
      } else {
        if (current <= closeThreshold) return minSize;

        final p = prevSnap();
        if (p <= minSize + 1e-6) {
          return s.length > 1 ? s[1] : minSize;
        }
        return p;
      }
    }

    // ---- Gentle drag behaviour ----
    if (v < 0 && current < s[nearestIndex] - dragBias) {
      final p = prevSnap();
      if (p <= minSize + 1e-6 && current > closeThreshold) {
        return s.length > 1 ? s[1] : minSize;
      }
      return p;
    }

    if (v > 0 && current > s[nearestIndex] + dragBias) {
      return nextSnap();
    }

    final nearest = s[nearestIndex];
    if (nearest <= minSize + 1e-6 && current > closeThreshold) {
      return s.length > 1 ? s[1] : minSize;
    }

    return nearest;
  }

  void _springTo({
    required double from,
    required double to,
    required double velocity, // fraction/sec
    required double minSize,
    required double maxSize,
  }) {
    final clampedTo = to.clamp(minSize, maxSize);

    const spring = SpringDescription(
      mass: 1.0,
      stiffness: 720.0,
      damping: 62.0,
    );

    _sheetAnim
      ..stop()
      ..value = from;

    _sheetAnim.animateWith(
      _ClampedSpringSimulation(
        SpringSimulation(spring, from, clampedTo, velocity),
        minSize,
        maxSize,
      ),
    );
  }

  void _startReleaseMotion({
    required double screenH,
    required double minSize,
    required double maxSize,
    required double velocityPixelsPerSecondDy,
    required List<double> snapPoints,
  }) {
    if (!_layersSheetCtrl.isAttached) return;

    final current = _layersSheetCtrl.size;
    final vRaw = (-velocityPixelsPerSecondDy) / screenH;

    const double vCap = 2.0;
    const double vScale = 1.35;
    final v = vCap * _tanh(vRaw / vScale);

    const double glideDrag = 1.65;

    final projected = _projectFrictionEnd(
      x0: current,
      v0: v,
      drag: glideDrag,
      minSize: minSize,
      maxSize: maxSize,
    );

    final target = _pickSnapTarget(
      current: current,
      v: v,
      snaps: snapPoints,
      minSize: minSize,
    );

    final better = _nearestSnap(projected, snapPoints);

    final chosen = ((projected - better).abs() <= (projected - target).abs())
        ? better
        : target;

    _springTo(
      from: current,
      to: chosen,
      velocity: v,
      minSize: minSize,
      maxSize: maxSize,
    );
  }

  // --- helpers ---------------------------------------------------------------

  void _openBrushSheet(BuildContext context, ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
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

  double _projectFrictionEnd({
    required double x0,
    required double v0,
    required double drag,
    required double minSize,
    required double maxSize,
  }) {
    final sim = FrictionSimulation(drag, x0, v0);

    double t = 0.0;
    for (int i = 0; i < 120; i++) {
      t += 1 / 60;
      if (sim.isDone(t)) break;
    }

    return sim.x(t).clamp(minSize, maxSize);
  }

  double _nearestSnap(double x, List<double> snaps) {
    final s = snaps.toList()..sort();
    double best = s.first;
    double bestDist = (x - best).abs();
    for (final p in s) {
      final d = (x - p).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    return best;
  }

  void _openLayersSheet(BuildContext context) {
    // ✅ SHEET BEHAVIOUR
    const double kInitial = 0.42;
    const double kMin = 0.15;
    const double kMax = 0.90;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, // ✅ remove dark overlay
      isScrollControlled: true,
      builder: (ctx) {
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
                // ✅ IMPORTANT: don't paint a background here,
                // LayerPanel already draws its own blurred container.
                color: Colors.transparent,
                child: LayerPanel(
                  scrollController: scrollController,
                  showHeader: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ✅ NEW: LFO sheet (matches layers sheet style)
  void _openLfoSheet(BuildContext context) {
    const double kInitial = 0.42;
    const double kMin = 0.15;
    const double kMax = 0.90;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: kInitial,
          minChildSize: kMin,
          maxChildSize: kMax,
          expand: false,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(
                color: Colors.transparent,
                child: LfoPanel(
                  scrollController: scrollController,
                  showHeader: true,
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

// --- Small widgets -----------------------------------------------------------

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

/// Clamp spring motion so it never exceeds sheet bounds.
class _ClampedSpringSimulation extends Simulation {
  final SpringSimulation _inner;
  final double minX;
  final double maxX;

  _ClampedSpringSimulation(this._inner, this.minX, this.maxX);

  @override
  double x(double time) => _inner.x(time).clamp(minX, maxX);

  @override
  double dx(double time) {
    final raw = _inner.x(time);
    if (raw < minX || raw > maxX) return 0.0;
    return _inner.dx(time);
  }

  @override
  bool isDone(double time) {
    final raw = _inner.x(time);
    if (raw < minX || raw > maxX) return true;
    return _inner.isDone(time);
  }
}

/// Hyperbolic tangent for older SDKs without math.tanh.
double _tanh(double x) {
  if (x > 10) return 1.0;
  if (x < -10) return -1.0;

  final ex = math.exp(x);
  final emx = 1.0 / ex;
  return (ex - emx) / (ex + emx);
}
