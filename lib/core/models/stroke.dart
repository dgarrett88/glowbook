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
  final int color; // ARGB
  final double size;
  final double glow;
  final int seed;
  final List<PointSample> points;
  /// Optional identifier used by the renderer for mirrored strokes
  final String? symmetryId;

  const Stroke({
    required this.id,
    required this.brushId,
    required this.color,
    required this.size,
    required this.glow,
    required this.seed,
    required this.points,
    this.symmetryId,
  });

  Stroke copyWith({
    String? id,
    String? brushId,
    int? color,
    double? size,
    double? glow,
    int? seed,
    List<PointSample>? points,
    String? symmetryId,
  }) {
    return Stroke(
      id: id ?? this.id,
      brushId: brushId ?? this.brushId,
      color: color ?? this.color,
      size: size ?? this.size,
      glow: glow ?? this.glow,
      seed: seed ?? this.seed,
      points: points ?? this.points,
      symmetryId: symmetryId ?? this.symmetryId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'brushId': brushId,
        'color': color,
        'size': size,
        'glow': glow,
        'seed': seed,
        'points': points.map((p) => p.toJson()).toList(),
        'symmetryId': symmetryId,
      };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] as String,
      brushId: json['brushId'] as String,
      color: json['color'] as int,
      size: (json['size'] as num).toDouble(),
      glow: (json['glow'] as num).toDouble(),
      seed: json['seed'] as int,
      points: (json['points'] as List)
          .map((e) => PointSample.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      symmetryId: json['symmetryId'] as String?,
    );
  }
}
