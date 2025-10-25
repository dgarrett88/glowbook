import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/models/stroke.dart';
import 'brushes/liquid_neon.dart';

class Renderer extends CustomPainter {
  Renderer(this.repaint) : super(repaint: repaint);
  final Listenable repaint;

  final List<ui.Picture> _baked = [];
  final LiquidNeonBrush _neon = LiquidNeonBrush();

  Stroke? _activeStroke;

  void beginStroke(Stroke stroke) => _activeStroke = stroke;
  void updateStroke(Stroke stroke) => _activeStroke = stroke;

  void commitStroke(Stroke stroke) {
    final rec = ui.PictureRecorder();
    final can = Canvas(rec);
    _neon.drawFull(can, stroke);
    _baked.add(rec.endRecording());
    _activeStroke = null;
  }

  void rebuildFrom(List<Stroke> strokes) {
    for (final p in _baked) { p.dispose(); }
    _baked.clear();
    for (final s in strokes) {
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
    final s = _activeStroke;
    if (s != null) _neon.drawPartial(canvas, s);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
