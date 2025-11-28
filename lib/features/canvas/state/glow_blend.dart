import 'dart:ui' show BlendMode;
import 'package:flutter/foundation.dart';

/// Global blend modes for how neon strokes interact with each other.
/// These are NOT per-brush – they are a single global choice that affects
/// how strokes are composited when we (re)build the stroke pictures.
enum GlowBlend {
  additive,
  screen,
  multiply,
  overlay,
  lighten,
  darken,
}

extension GlowBlendX on GlowBlend {
  /// Map our logical blend choice to Flutter's BlendMode.
  BlendMode toBlendMode() {
    switch (this) {
      case GlowBlend.additive:
        // Classic neon stacking: colours add and can blow out to white.
        return BlendMode.plus;
      case GlowBlend.screen:
        // Lighter, photographic-style glow.
        return BlendMode.screen;
      case GlowBlend.multiply:
        // Paint-style color mixing without bright blowout.
        return BlendMode.multiply;
      case GlowBlend.overlay:
        return BlendMode.overlay;
      case GlowBlend.lighten:
        return BlendMode.lighten;
      case GlowBlend.darken:
        return BlendMode.darken;
    }
  }

  String get label {
    switch (this) {
      case GlowBlend.additive:
        return 'Additive';
      case GlowBlend.screen:
        return 'Screen';
      case GlowBlend.multiply:
        return 'Multiply';
      case GlowBlend.overlay:
        return 'Overlay';
      case GlowBlend.lighten:
        return 'Lighten';
      case GlowBlend.darken:
        return 'Darken';
    }
  }
}

/// Singleton global blend state: which mode and how strong the effect is.
///
/// This is intentionally global so that changing the blend mode or intensity
/// can re-bake all strokes and make the entire canvas react like a filter.
class GlowBlendState extends ChangeNotifier {
  GlowBlendState._();
  static final GlowBlendState I = GlowBlendState._();

  GlowBlend _mode = GlowBlend.additive;
  double _intensity = 1.0; // 0 = no glow contribution, 1 = full strength.

  GlowBlend get mode => _mode;
  double get intensity => _intensity;

  void setMode(GlowBlend m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  void setIntensity(double v) {
    final clamped = v.clamp(0.0, 1.0);
    if (clamped == _intensity) return;
    _intensity = clamped;
    notifyListeners();
  }
}
