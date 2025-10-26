class PointSample {
  final double x;
  final double y;
  final int t; // ms since stroke start
  const PointSample(this.x, this.y, this.t);
}

class Stroke {
  final String id;
  final int color;     // ARGB
  final double size;   // logical px
  final double glow;   // 0..1
  final String brushId;
  final int seed;      // optional deterministic seed for brush effects
  final List<PointSample> points;

  Stroke({
    required this.id,
    required this.color,
    required this.size,
    required this.glow,
    required this.brushId,
    this.seed = 0,
    required this.points,
  });

  Stroke copyWith({List<PointSample>? points}) => Stroke(
    id: id,
    color: color,
    size: size,
    glow: glow,
    brushId: brushId,
    seed: seed,
    points: points ?? this.points,
  );
}
