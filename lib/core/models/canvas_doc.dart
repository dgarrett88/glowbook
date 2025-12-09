enum BackgroundType { solid, gradient, texture }

class Background {
  final BackgroundType type;
  final Map<String, dynamic> params;
  const Background({required this.type, this.params = const {}});

  static Background solid(int argb) =>
      Background(type: BackgroundType.solid, params: {'color': argb});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _backgroundTypeToString(type),
        'params': params,
      };

  factory Background.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final params = (json['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return Background(
      type: _backgroundTypeFromString(typeStr),
      params: params,
    );
  }

  static BackgroundType _backgroundTypeFromString(String? value) {
    switch (value) {
      case 'solid':
        return BackgroundType.solid;
      case 'gradient':
        return BackgroundType.gradient;
      case 'texture':
        return BackgroundType.texture;
      default:
        return BackgroundType.solid;
    }
  }

  static String _backgroundTypeToString(BackgroundType type) {
    switch (type) {
      case BackgroundType.solid:
        return 'solid';
      case BackgroundType.gradient:
        return 'gradient';
      case BackgroundType.texture:
        return 'texture';
    }
  }
}

enum SymmetryMode { off, mirrorV, mirrorH, quad }

class CanvasDoc {
  final String id;
  final String name;
  final int createdAt; // msSinceEpoch
  final int updatedAt; // msSinceEpoch
  final int width;
  final int height;
  final Background background;
  final SymmetryMode symmetry;

  /// NEW: per-document blend mode key.
  ///
  /// Examples:
  ///  - 'additive'
  ///  - 'screen'
  ///  - 'overlay'
  ///  - 'chromaticMix'
  ///
  /// Older JSON files won’t have this field, so we default to 'additive'.
  final String blendModeKey;

  const CanvasDoc({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.background,
    required this.symmetry,
    this.blendModeKey = 'additive',
  });

  CanvasDoc copyWith({
    String? id,
    String? name,
    int? createdAt,
    int? updatedAt,
    int? width,
    int? height,
    Background? background,
    SymmetryMode? symmetry,
    String? blendModeKey,
  }) {
    return CanvasDoc(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      background: background ?? this.background,
      symmetry: symmetry ?? this.symmetry,
      blendModeKey: blendModeKey ?? this.blendModeKey,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'width': width,
        'height': height,
        'background': background.toJson(),
        'symmetry': _symmetryToString(symmetry),

        // NEW: save blend mode key
        'blendMode': blendModeKey,
      };

  factory CanvasDoc.fromJson(Map<String, dynamic> json) {
    return CanvasDoc(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      background: Background.fromJson(
        (json['background'] as Map).cast<String, dynamic>(),
      ),
      symmetry: _symmetryFromString(json['symmetry'] as String?),

      // NEW: default to additive if missing
      blendModeKey: (json['blendMode'] as String?) ?? 'additive',
    );
  }

  static String _symmetryToString(SymmetryMode mode) {
    switch (mode) {
      case SymmetryMode.off:
        return 'off';
      case SymmetryMode.mirrorV:
        return 'mirrorV';
      case SymmetryMode.mirrorH:
        return 'mirrorH';
      case SymmetryMode.quad:
        return 'quad';
    }
  }

  static SymmetryMode _symmetryFromString(String? value) {
    switch (value) {
      case 'mirrorV':
        return SymmetryMode.mirrorV;
      case 'mirrorH':
        return SymmetryMode.mirrorH;
      case 'quad':
        return SymmetryMode.quad;
      case 'off':
      default:
        return SymmetryMode.off;
    }
  }
}
