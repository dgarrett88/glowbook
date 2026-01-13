// lib/core/models/lfo.dart
import 'dart:math' as math;

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

/// One LFO generator (global, routed to one or more targets).
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

  /// Evaluate normalized waveform output roughly in [-1..1], with optional offset.
  double eval(double tSec) {
    final ph = (phase % 1.0 + 1.0) % 1.0;
    final x = (tSec * rateHz + ph) % 1.0; // 0..1
    double y;

    switch (wave) {
      case LfoWave.sine:
        y = math.sin(x * math.pi * 2.0);
        break;
      case LfoWave.triangle:
        // triangle in [-1..1]
        // 0..1 -> 0..1..0 then map to [-1..1]
        final tri01 = x < 0.5 ? (x * 2.0) : (2.0 - x * 2.0);
        y = tri01 * 2.0 - 1.0;
        break;
      case LfoWave.saw:
        // saw in [-1..1]
        y = x * 2.0 - 1.0;
        break;
      case LfoWave.square:
        y = x < 0.5 ? 1.0 : -1.0;
        break;
    }

    y += offset;
    // keep sane
    return y.clamp(-2.0, 2.0).toDouble();
  }
}

/// For v1 we only route to *layer extra rotation*.
/// Amount is in degrees (nice for UI), converted to radians in controller.
class LfoRoute {
  final String id;
  final String lfoId;
  final String layerId;
  final bool enabled;

  /// Peak amount in degrees applied to the LFO output.
  final double amountDeg;

  const LfoRoute({
    required this.id,
    required this.lfoId,
    required this.layerId,
    this.enabled = true,
    this.amountDeg = 25.0,
  });

  LfoRoute copyWith({
    String? id,
    String? lfoId,
    String? layerId,
    bool? enabled,
    double? amountDeg,
  }) {
    return LfoRoute(
      id: id ?? this.id,
      lfoId: lfoId ?? this.lfoId,
      layerId: layerId ?? this.layerId,
      enabled: enabled ?? this.enabled,
      amountDeg: amountDeg ?? this.amountDeg,
    );
  }
}
