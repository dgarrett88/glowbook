enum BackgroundType { solid, gradient, texture }

class Background {
  final BackgroundType type;
  final Map<String, dynamic> params;
  const Background({required this.type, this.params = const {}});

  static Background solid(int argb) =>
      Background(type: BackgroundType.solid, params: {'color': argb});
}

enum SymmetryMode { off, mirrorV, mirrorH, quad }

class CanvasDoc {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int width;
  final int height;
  final Background background;
  final SymmetryMode symmetry;

  const CanvasDoc({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.background,
    required this.symmetry,
  });
}
