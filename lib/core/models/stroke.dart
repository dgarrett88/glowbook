// lib/core/models/stroke.dart
class PointSample {
  final double x;
  final double y;
  final int t; // ms since stroke start
  const PointSample(this.x, this.y, this.t);

  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y, 't': t};

  factory PointSample.fromJson(Map<String, dynamic> json) {
    return PointSample(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
      json['t'] as int,
    );
  }
}

class Stroke {
  final String id;
  final String brushId;

  /// User-facing label for this stroke (shown in Layer panel).
  final String name;

  /// If false, the stroke is hidden (not rendered).
  final bool visible;

  final int color; // ARGB
  final double size;

  /// Legacy single glow factor (0..1). Kept for backwards compatibility.
  /// New code should prefer [glowRadius], [glowOpacity], [glowBrightness].
  final double glow;

  /// Radius/intensity factor for halo size (0..1).
  final double glowRadius;

  /// Opacity factor for the glow stroke (0..1).
  final double glowOpacity;

  /// Brightness factor that feeds into glow alpha (0..1).
  final double glowBrightness;

  /// How solid the inner stroke core is (0..1).
  final double coreOpacity;

  /// If true, glow radius scales with brush size when rendered.
  final bool glowRadiusScalesWithSize;

  final int seed;
  final List<PointSample> points;

  /// Optional identifier used by the renderer for mirrored strokes.
  final String? symmetryId;

  const Stroke({
    required this.id,
    required this.brushId,
    this.name = 'Stroke',
    this.visible = true,
    required this.color,
    required this.size,
    required this.glow,
    this.glowRadius = 0.7,
    this.glowOpacity = 1.0,
    this.glowBrightness = 0.7,
    this.coreOpacity = 0.86,
    this.glowRadiusScalesWithSize = false,
    required this.seed,
    required this.points,
    this.symmetryId,
  });

  Stroke copyWith({
    String? id,
    String? brushId,
    String? name,
    bool? visible,
    int? color,
    double? size,
    double? glow,
    double? glowRadius,
    double? glowOpacity,
    double? glowBrightness,
    double? coreOpacity,
    bool? glowRadiusScalesWithSize,
    int? seed,
    List<PointSample>? points,
    String? symmetryId,
  }) {
    return Stroke(
      id: id ?? this.id,
      brushId: brushId ?? this.brushId,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      color: color ?? this.color,
      size: size ?? this.size,
      glow: glow ?? this.glow,
      glowRadius: glowRadius ?? this.glowRadius,
      glowOpacity: glowOpacity ?? this.glowOpacity,
      glowBrightness: glowBrightness ?? this.glowBrightness,
      coreOpacity: coreOpacity ?? this.coreOpacity,
      glowRadiusScalesWithSize:
          glowRadiusScalesWithSize ?? this.glowRadiusScalesWithSize,
      seed: seed ?? this.seed,
      points: points ?? this.points,
      symmetryId: symmetryId ?? this.symmetryId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'brushId': brushId,
        'name': name,
        'visible': visible,
        'color': color,
        'size': size,
        'glow': glow,
        'glowRadius': glowRadius,
        'glowOpacity': glowOpacity,
        'glowBrightness': glowBrightness,
        'coreOpacity': coreOpacity,
        'glowRadiusScalesWithSize': glowRadiusScalesWithSize,
        'seed': seed,
        'points': points.map((p) => p.toJson()).toList(),
        'symmetryId': symmetryId,
      };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final double legacyGlow = (json['glow'] as num).toDouble();
    return Stroke(
      id: json['id'] as String,
      brushId: json['brushId'] as String,
      name: (json['name'] as String?) ?? 'Stroke',
      visible: (json['visible'] as bool?) ?? true,
      color: json['color'] as int,
      size: (json['size'] as num).toDouble(),
      glow: legacyGlow,
      glowRadius: (json['glowRadius'] as num?)?.toDouble() ?? legacyGlow,
      glowOpacity: (json['glowOpacity'] as num?)?.toDouble() ?? 1.0,
      glowBrightness:
          (json['glowBrightness'] as num?)?.toDouble() ?? legacyGlow,
      coreOpacity: (json['coreOpacity'] as num?)?.toDouble() ?? 0.86,
      glowRadiusScalesWithSize:
          (json['glowRadiusScalesWithSize'] as bool?) ?? false,
      seed: json['seed'] as int,
      points: (json['points'] as List)
          .map(
            (e) => PointSample.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      symmetryId: json['symmetryId'] as String?,
    );
  }
}
