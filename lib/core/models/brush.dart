class Brush {
  final String id;
  final String name;
  const Brush(this.id, this.name);

  static const liquidNeon = Brush('liquid_neon', 'Liquid Neon');
  static const softGlow = Brush('soft_glow', 'Soft Glow');
  static const glowOnly = Brush('glow_only', 'Glow Only');

  static const List<Brush> all = <Brush>[
    liquidNeon,
    softGlow,
    glowOnly,
  ];

  static Brush fromId(String id) {
    return all.firstWhere(
      (b) => b.id == id,
      orElse: () => softGlow,
    );
  }
}
