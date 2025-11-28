import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import '../../../core/models/stroke.dart';
import '../state/canvas_controller.dart';
import 'brushes/liquid_neon.dart';
import 'brushes/soft_glow.dart';
import 'brushes/glow_only.dart';
import 'brushes/hyper_neon.dart';
import 'brushes/edge_glow.dart';
import 'brushes/ghost_trail.dart';
import 'brushes/inner_glow.dart';
import '../state/glow_blend.dart' as gb;

class Renderer extends CustomPainter {
  Renderer(this.repaint, this.symmetryFn) : super(repaint: repaint);

  final Listenable repaint;
  final SymmetryMode Function() symmetryFn;

  final List<ui.Picture> _baked = <ui.Picture>[];
  final LiquidNeonBrush _neon = LiquidNeonBrush();
  final SoftGlowBrush _soft = SoftGlowBrush();
  final GlowOnlyBrush _glowOnly = GlowOnlyBrush();
  final HyperNeonBrush _hyper = const HyperNeonBrush();
  final EdgeGlowBrush _edge = const EdgeGlowBrush();
  final GhostTrailBrush _ghost = const GhostTrailBrush();
  final InnerGlowBrush _inner = const InnerGlowBrush();

  Stroke? _active;
  Size? _lastSize;

  SymmetryMode _modeForStroke(Stroke s) {
    final id = s.symmetryId;
    if (id == null) return symmetryFn();
    switch (id) {
      case 'mirrorV':
        return SymmetryMode.mirrorV;
      case 'mirrorH':
        return SymmetryMode.mirrorH;
      case 'quad':
        return SymmetryMode.quad;
      case 'off':
      default:
        return SymmetryMode.off;
    }
  }

  void beginStroke(Stroke s) {
    _active = s;
  }

  void updateStroke(Stroke s) {
    _active = s;
  }

  void commitStroke(Stroke s) {
    final sz = _lastSize ?? const Size(0, 0);
    final rec = ui.PictureRecorder();
    final can = Canvas(rec);
    _drawByBrush(can, s, sz, _modeForStroke(s));
    _baked.add(rec.endRecording());
    _active = null;
  }

  void rebuildFrom(List<Stroke> strokes) {
    for (final p in _baked) {
      p.dispose();
    }
    _baked.clear();
    final sz = _lastSize ?? const Size(0, 0);
    for (final s in strokes) {
      final rec = ui.PictureRecorder();
      final can = Canvas(rec);
      _drawByBrush(can, s, sz, _modeForStroke(s));
      _baked.add(rec.endRecording());
    }
  }

  void _drawByBrush(Canvas canvas, Stroke s, Size sz, SymmetryMode mode) {
    switch (s.brushId) {
      case 'glow_only':
        _glowOnly.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'soft_glow':
        _soft.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'hyper_neon':
        _hyper.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'edge_glow':
        _edge.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'ghost_trail':
        _ghost.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'inner_glow':
        _inner.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'liquid_neon':
      default:
        _neon.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _lastSize = size;

    // Clear the background based on global blend mode.
    final mode = gb.GlowBlendState.I.mode;
    final bool isMultiply = mode == gb.GlowBlend.multiply;

    // White for Multiply (Venn-style mixing), black for neon modes.
    final ui.Color bgColor =
        isMultiply ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFF000000);

    final Paint bgPaint = Paint()..color = bgColor;
    canvas.drawRect(ui.Offset.zero & size, bgPaint);

    // Draw baked strokes.
    for (final pic in _baked) {
      canvas.drawPicture(pic);
    }

    // Draw active stroke on top.
    final s = _active;
    if (s != null) {
      _drawByBrush(canvas, s, size, _modeForStroke(s));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
