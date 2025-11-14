import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import '../../../core/models/stroke.dart';
import '../state/canvas_controller.dart';
import 'brushes/liquid_neon.dart';
import 'brushes/soft_glow.dart';
import 'brushes/glow_only.dart';

class Renderer extends CustomPainter {
  Renderer(this.repaint, this.symmetryFn): super(repaint: repaint);
  final Listenable repaint;
  final SymmetryMode Function() symmetryFn;

  final List<ui.Picture> _baked = <ui.Picture>[];
  final LiquidNeonBrush _neon = LiquidNeonBrush();
  final SoftGlowBrush _soft = SoftGlowBrush();
  final GlowOnlyBrush _glowOnly = GlowOnlyBrush();
  Stroke? _active;
  Size? _lastSize;

  SymmetryMode _modeForStroke(Stroke s){
    final id = s.symmetryId;
    if (id == null) return symmetryFn();
    switch(id){
      case 'mirrorV': return SymmetryMode.mirrorV;
      case 'mirrorH': return SymmetryMode.mirrorH;
      case 'quad': return SymmetryMode.quad;
      case 'off':
      default: return SymmetryMode.off;
    }
  }

  void beginStroke(Stroke s){ _active = s; }
  void updateStroke(Stroke s){ _active = s; }
  void commitStroke(Stroke s){
    final sz = _lastSize ?? const Size(0,0);
    final rec = ui.PictureRecorder();
    final can = Canvas(rec);
    _drawByBrush(can, s, sz, _modeForStroke(s));
    _baked.add(rec.endRecording());
    _active = null;
  }

  void rebuildFrom(List<Stroke> strokes){
    for (final p in _baked) { p.dispose(); }
    _baked.clear();
    final sz = _lastSize ?? const Size(0,0);
    for (final s in strokes){
      final rec = ui.PictureRecorder();
      final can = Canvas(rec);
      _drawByBrush(can, s, sz, _modeForStroke(s));
      _baked.add(rec.endRecording());
    }
  }

  void _drawByBrush(Canvas canvas, Stroke s, Size sz, SymmetryMode mode){
    switch (s.brushId) {
      case 'glow_only':
        _glowOnly.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'soft_glow':
        _soft.drawFullWithSymmetry(canvas, s, sz, mode);
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
    for (final pic in _baked) {
      canvas.drawPicture(pic);
    }
    final s = _active;
    if (s != null) {
      _drawByBrush(canvas, s, size, _modeForStroke(s));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
