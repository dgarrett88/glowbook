import 'dart:ui' show BlendMode, Color, lerpDouble;
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
  chromaticMix,
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
      case GlowBlend.chromaticMix:
        // Experimental "colour melt" mode – use normal compositing so
        // strokes and halos tint each other without huge brightness jumps.
        return BlendMode.srcOver;
    }
  }

  /// Human-friendly label for menus.
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
      case GlowBlend.chromaticMix:
        return 'Chromatic Mix';
    }
  }

  /// Adjust the stroke colour based on the global blend mode and intensity.
  ///
  /// Right now we only refine Additive so it:
  /// - has more headroom (doesn't hit white instantly)
  /// - actually responds nicely to the intensity slider.
  Color adjustColorForMode(Color base, double intensity) {
    switch (this) {
      case GlowBlend.additive:
        final t = intensity.clamp(0.0, 1.0);

        // Give ourselves headroom so additive doesn’t instantly blow out:
        // At low intensity we darken the colour a bit and reduce alpha.
        // At high intensity it’s closer to the original.
        final headroomScale = lerpDouble(0.7, 1.0, t)!; // 0.7 → 1.0
        final alphaScale = lerpDouble(0.3, 1.0, t)!; // 0.3 → 1.0

        int scaleChannel(int c) => (c * headroomScale).clamp(0, 255).round();

        final r = scaleChannel(base.red);
        final g = scaleChannel(base.green);
        final b = scaleChannel(base.blue);
        final a = (base.alpha * alphaScale).clamp(0, 255).round();

        return Color.fromARGB(a, r, g, b);

      // Other modes can get their own refinement later.
      default:
        return base;
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

/// Map a GlowBlend to a stable string key for storage with documents.
String glowBlendToKey(GlowBlend mode) {
  switch (mode) {
    case GlowBlend.additive:
      return 'additive';
    case GlowBlend.screen:
      return 'screen';
    case GlowBlend.multiply:
      return 'multiply';
    case GlowBlend.overlay:
      return 'overlay';
    case GlowBlend.lighten:
      return 'lighten';
    case GlowBlend.darken:
      return 'darken';
    case GlowBlend.chromaticMix:
      return 'chromaticMix';
  }
}

/// Convert a stored string key back into a GlowBlend.
/// Unknown/null keys fall back to additive.
GlowBlend glowBlendFromKey(String? key) {
  switch (key) {
    case 'screen':
      return GlowBlend.screen;
    case 'multiply':
      return GlowBlend.multiply;
    case 'overlay':
      return GlowBlend.overlay;
    case 'lighten':
      return GlowBlend.lighten;
    case 'darken':
      return GlowBlend.darken;
    case 'chromaticMix':
      return GlowBlend.chromaticMix;
    case 'additive':
    default:
      return GlowBlend.additive;
  }
}
