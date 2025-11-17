import 'canvas_controller.dart';

/// Legacy glow control extension.
///
/// Glow is now controlled directly by `CanvasController.setBrushGlow`.
/// This extension is kept only for backward compatibility and no longer
/// touches `brushGlow` or `notifyListeners` directly.
extension GlowControl on CanvasController {
  @Deprecated('Use CanvasController.setBrushGlow instead')
  void setBrushGlowLegacy(double v) {
    setBrushGlow(v);
  }
}
