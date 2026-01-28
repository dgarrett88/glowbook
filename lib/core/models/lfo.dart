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
enum LfoParam {
  // -------------------------
  // Layer params
  // -------------------------
  layerRotationDeg,
  layerX,
  layerY,
  layerScale,
  layerOpacity,

  // -------------------------
  // Stroke params
  // -------------------------
  strokeSize,
  strokeX,
  strokeY,
  strokeRotationDeg,
  strokeCoreOpacity,
  strokeGlowRadius,
  strokeGlowOpacity,
  strokeGlowBrightness,
}

class Lfo {
  final String id;
  final String name;

  final bool enabled;
  final LfoWave wave;

  /// Cycles per second.
  final double rateHz;

  /// 0..1
  final double phase;

  /// -1..1 (added after waveform)
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

  // Back-compat aliases some older code sometimes uses
  double get phase01 => phase;

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

  /// Evaluate waveform at timeSec.
  /// Returns [-1..1] (then offset added, still clamped).
  double eval(double timeSec) {
    final hz = rateHz <= 0 ? 0.0001 : rateHz;
    final t = (timeSec * hz) + phase;

    double v;
    switch (wave) {
      case LfoWave.sine:
        v = math.sin(t * math.pi * 2.0);
        break;

      case LfoWave.triangle:
        {
          final f = t - t.floorToDouble(); // [0..1)
          v = 1.0 - (4.0 * (f - 0.5).abs()); // [-1..1]
          break;
        }

      case LfoWave.saw:
        {
          final f = t - t.floorToDouble(); // [0..1)
          v = (f * 2.0) - 1.0; // [-1..1]
          break;
        }

      case LfoWave.square:
        {
          final f = t - t.floorToDouble();
          v = (f < 0.5) ? 1.0 : -1.0;
          break;
        }
    }

    return (v + offset).clamp(-1.0, 1.0);
  }
}

/// A single route from an LFO to a parameter.
///
/// IMPORTANT:
/// We intentionally support BOTH naming schemes:
/// - `amount` (older code)
/// - `amountDeg` (your newer UI)
class LfoRoute {
  final String id;
  final String lfoId;

  /// Target layer
  final String layerId;

  /// Target param
  final LfoParam param;

  /// Canonical amount storage.
  /// Older code often calls this `amount`.
  final double amount;

  /// If true: shaped value stays [-1..1]
  /// If false: shaped value is mapped to [0..1]
  final bool bipolar;

  final bool enabled;

  // Stroke targeting (optional)
  final int? groupIndex;
  final String? strokeId;

  const LfoRoute({
    required this.id,
    required this.lfoId,
    required this.layerId,
    required this.param,
    this.amount = 25.0,
    this.bipolar = true,
    this.enabled = true,
    this.groupIndex,
    this.strokeId,
  });

  // ✅ Newer UI alias
  double get amountDeg => amount;

  // ✅ Other “just in case” aliases (helps stop project-wide breakage)
  String? get targetStrokeId => strokeId;
  int? get targetGroupIndex => groupIndex;

  // ✅ Fix for your controller errors
  bool get isStrokeTarget => strokeId != null;
  bool get isLayerTarget => strokeId == null;

  LfoRoute copyWith({
    String? id,
    String? lfoId,
    String? layerId,
    LfoParam? param,
    double? amount,
    double? amountDeg,
    bool? bipolar,
    bool? enabled,
    int? groupIndex,
    String? strokeId,
    bool clearStrokeTarget = false,
  }) {
    final newAmount = amount ?? amountDeg ?? this.amount;

    return LfoRoute(
      id: id ?? this.id,
      lfoId: lfoId ?? this.lfoId,
      layerId: layerId ?? this.layerId,
      param: param ?? this.param,
      amount: newAmount,
      bipolar: bipolar ?? this.bipolar,
      enabled: enabled ?? this.enabled,
      groupIndex: clearStrokeTarget ? null : (groupIndex ?? this.groupIndex),
      strokeId: clearStrokeTarget ? null : (strokeId ?? this.strokeId),
    );
  }
}
