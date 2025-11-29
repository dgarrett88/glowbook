import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart'; // for type only
import '../../state/glow_blend.dart' as gb;

class GlowBlendDropdown extends StatefulWidget {
  final CanvasController controller;
  const GlowBlendDropdown({super.key, required this.controller});

  @override
  State<GlowBlendDropdown> createState() => _GlowBlendDropdownState();
}

class _GlowBlendDropdownState extends State<GlowBlendDropdown> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    gb.GlowBlendState.I.addListener(_onBlendChanged);
  }

  @override
  void dispose() {
    gb.GlowBlendState.I.removeListener(_onBlendChanged);
    _removeMenu();
    super.dispose();
  }

  void _onBlendChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _removeMenu() {
    _entry?.remove();
    _entry = null;
  }

  void _toggleMenu() {
    if (_entry != null) {
      _removeMenu();
      return;
    }

    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    if (renderBox == null || overlayBox == null) return;

    final buttonSize = renderBox.size;
    final buttonPos =
        renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    const double itemHeight = 36.0;
    final modes = gb.GlowBlend.values;
    final double menuHeight = itemHeight * modes.length;

    _entry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Stack(
          children: [
            // Tap outside to close
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeMenu,
              ),
            ),
            Positioned(
              left: buttonPos.dx,
              // Show just above the blend bar
              top: buttonPos.dy - menuHeight - 4,
              child: Material(
                color: cs.surface,
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: menuHeight,
                  width: buttonSize.width + 40,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in modes)
                        InkWell(
                          onTap: () {
                            gb.GlowBlendState.I.setMode(m);
                            _removeMenu();
                          },
                          child: Container(
                            height: itemHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              m.label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final mode = gb.GlowBlendState.I.mode;

    return InkWell(
      key: _buttonKey,
      onTap: _toggleMenu,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                mode.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
