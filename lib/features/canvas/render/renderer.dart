import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import '../../../core/models/stroke.dart';
import 'brushes/liquid_neon.dart';

class Renderer extends CustomPainter {
  Renderer(this.repaint): super(repaint: repaint);
  final Listenable repaint;

  final List<ui.Picture> _baked = <ui.Picture>[];
  final LiquidNeonBrush _neon = LiquidNeonBrush();
  Stroke? _active;

  void beginStroke(Stroke s){ _active = s; }
  void updateStroke(Stroke s){ _active = s; }
  void commitStroke(Stroke s){
    final rec = ui.PictureRecorder();
    final can = Canvas(rec);
    _neon.drawFull(can, s);
    _baked.add(rec.endRecording());
    _active = null;
  }

  void rebuildFrom(List<Stroke> strokes){
    for (final p in _baked) { p.dispose(); }
    _baked.clear();
    for (final s in strokes){
      final rec = ui.PictureRecorder();
      final can = Canvas(rec);
      _neon.drawFull(can, s);
      _baked.add(rec.endRecording());
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final pic in _baked) {
      canvas.drawPicture(pic);
    }
    final s = _active;
    if (s != null) {
      _neon.drawFull(canvas, s);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
