class Brush {
  final String id;
  final double baseSize;
  final double glow; // 0..1
  const Brush({required this.id, required this.baseSize, required this.glow});

  static const liquidNeon = Brush(id: 'liquid_neon', baseSize: 8.0, glow: 0.8);
}
