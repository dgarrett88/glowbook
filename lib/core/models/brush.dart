class Brush {
  final String id;
  final String name;
  const Brush(this.id, this.name);

  static const liquidNeon = Brush('liquid_neon', 'Liquid Neon');
  static const softGlow = Brush('soft_glow', 'Soft Glow');
  static const glowOnly = Brush('glow_only', 'Glow Only');

  static const hyperNeon = Brush('hyper_neon', 'Hyper Neon');
  static const edgeGlow = Brush('edge_glow', 'Edge Glow');
  static const ghostTrail = Brush('ghost_trail', 'Ghost Trail');
  static const innerGlow = Brush('inner_glow', 'Inner Glow');

  static const List<Brush> all = <Brush>[
    liquidNeon,
    softGlow,
    glowOnly,
    hyperNeon,
    edgeGlow,
    ghostTrail,
    innerGlow,
  ];

  static Brush fromId(String id) {
    return all.firstWhere(
      (b) => b.id == id,
      orElse: () => softGlow,
    );
  }
}
