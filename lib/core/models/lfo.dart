// lib/core/models/lfo.dart
import 'dart:math' as math;

/// Supported LFO waveforms.
enum LfoWave { sine, triangle, saw, square }

extension LfoWaveX on LfoWave {
  String get label {
    switch (this) {
      case LfoWave.sine:
        return 'Sine';
      case LfoWave.triangle:
        return 'Tri';
      case LfoWave.saw:
        return 'Saw';
      case LfoWave.square:
        return 'Square';
    }
  }
}

/// What a route is allowed to modulate.
/// Expanded to cover layer + stroke params.
enum LfoParam {
  // -----------------------
  // Layer params
  // -----------------------
  layerRotationDeg,
  layerX,
  layerY,
  layerScale,
  layerOpacity,

  // -----------------------
  // Stroke params
  // -----------------------
  strokeSize,
  strokeX,
  strokeY,
  strokeRotationDeg,
  strokeCoreOpacity,
  strokeGlowRadius,
  strokeGlowOpacity,
  strokeGlowBrightness,
}

/// One global LFO generator.
/// LFOs do not know targets — routes do.
class Lfo {
  final String id;
  final String name;
  final bool enabled;

  final LfoWave wave;

  /// cycles per second
  final double rateHz;

  /// phase offset in [0..1)
  final double phase;

  /// output offset in [-1..1] (added after waveform)
  final double offset;

  const Lfo({
    required this.id,
    required this.name,
    this.enabled = true,
    this.wave = LfoWave.sine,
    this.rateHz = 0.25,
    this.phase = 0.0,
    this.offset = 0.0,
  });

  Lfo copyWith({
    String? id,
    String? name,
    bool? enabled,
    LfoWave? wave,
    double? rateHz,
    double? phase,
    double? offset,
  }) {
    return Lfo(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      wave: wave ?? this.wave,
      rateHz: rateHz ?? this.rateHz,
      phase: phase ?? this.phase,
      offset: offset ?? this.offset,
    );
  }

  /// Evaluate normalized waveform output in [-1..1], with optional offset.
  /// Routing (amount/param) is applied elsewhere.
  double eval(double tSec) {
    final ph = (phase % 1.0 + 1.0) % 1.0;
    final x = (tSec * rateHz + ph) % 1.0; // 0..1
    double y;

    switch (wave) {
      case LfoWave.sine:
        y = math.sin(x * math.pi * 2.0);
        break;

      case LfoWave.triangle:
        final tri01 = x < 0.5 ? (x * 2.0) : (2.0 - x * 2.0);
        y = tri01 * 2.0 - 1.0;
        break;

      case LfoWave.saw:
        y = x * 2.0 - 1.0;
        break;

      case LfoWave.square:
        y = x < 0.5 ? 1.0 : -1.0;
        break;
    }

    y += offset;

    return y.clamp(-1.0, 1.0).toDouble();
  }
}

/// A route connects one LFO to ONE parameter on ONE target.
///
/// v1: target was a layer only.
/// v2: target can be a layer OR a specific stroke ref.
class LfoRoute {
  final String id;
  final String lfoId;

  /// Layer target (always present)
  final String layerId;

  /// Stroke target (optional) — when set, this route targets a stroke
  /// within `layerId` at `groupIndex`.
  final int? groupIndex;
  final String? strokeId;

  /// What parameter this route modulates.
  final LfoParam param;

  final bool enabled;

  /// If true: route output is bipolar (-1..+1).
  /// If false: route output becomes unipolar (0..1).
  final bool bipolar;

  /// Peak amount (stored in amountDeg for backward compatibility).
  /// Interpretation depends on param.
  final double amountDeg;

  const LfoRoute({
    required this.id,
    required this.lfoId,
    required this.layerId,
    this.groupIndex,
    this.strokeId,
    this.param = LfoParam.layerRotationDeg,
    this.enabled = true,
    this.bipolar = true,
    this.amountDeg = 25.0,
  });

  bool get isStrokeTarget => strokeId != null && groupIndex != null;

  /// Future-proof generic access (optional helper).
  double get amount => amountDeg;

  LfoRoute copyWith({
    String? id,
    String? lfoId,
    String? layerId,
    int? groupIndex,
    String? strokeId,
    LfoParam? param,
    bool? enabled,
    bool? bipolar,
    double? amountDeg,
  }) {
    return LfoRoute(
      id: id ?? this.id,
      lfoId: lfoId ?? this.lfoId,
      layerId: layerId ?? this.layerId,
      groupIndex: groupIndex ?? this.groupIndex,
      strokeId: strokeId ?? this.strokeId,
      param: param ?? this.param,
      enabled: enabled ?? this.enabled,
      bipolar: bipolar ?? this.bipolar,
      amountDeg: amountDeg ?? this.amountDeg,
    );
  }
}
