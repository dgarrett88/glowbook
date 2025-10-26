class PointSample {
  final double x;
  final double y;
  final int t; // ms since stroke start
  const PointSample(this.x, this.y, this.t);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 't': t};
  factory PointSample.fromJson(Map<String, dynamic> j) =>
      PointSample((j['x'] as num).toDouble(), (j['y'] as num).toDouble(), j['t'] as int);
}

class Stroke {
  final String id;
  final String brushId;
  final int color;    // ARGB
  final double size;
  final double glow;
  final int seed;
  final List<PointSample> points;
  final String? symmetryId; // 'off','mirrorV','mirrorH','quad'

  Stroke({
    required this.id,
    required this.brushId,
    required this.color,
    required this.size,
    required this.glow,
    required this.seed,
    required this.points,
    this.symmetryId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'brushId': brushId,
        'color': color,
        'size': size,
        'glow': glow,
        'seed': seed,
        'points': points.map((e) => e.toJson()).toList(),
        'symmetryId': symmetryId,
      };

  factory Stroke.fromJson(Map<String, dynamic> j) => Stroke(
        id: j['id'] as String,
        brushId: j['brushId'] as String,
        color: j['color'] as int,
        size: (j['size'] as num).toDouble(),
        glow: (j['glow'] as num).toDouble(),
        seed: j['seed'] as int,
        points: (j['points'] as List).map((e) => PointSample.fromJson(e as Map<String, dynamic>)).toList(),
        symmetryId: j['symmetryId'] as String?,
      );
}
