class PointSample {
  final double x;
  final double y;
  final int t; // ms since stroke start
  const PointSample(this.x, this.y, this.t);
}

class Stroke {
  final String id;
  final String brushId;
  final int color; // ARGB
  final double size;
  final double glow; // 0..1
  final int seed;
  final List<PointSample> points;

  const Stroke({
    required this.id,
    required this.brushId,
    required this.color,
    required this.size,
    required this.glow,
    required this.seed,
    required this.points,
  });
}
