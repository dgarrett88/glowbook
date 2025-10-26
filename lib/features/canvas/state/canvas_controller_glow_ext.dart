import 'canvas_controller.dart';

extension GlowControl on CanvasController {
  void setBrushGlow(double v) {
    if (v.isNaN) v = 0.5;
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    brushGlow = v;
    notifyListeners();
  }
}
