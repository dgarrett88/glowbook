class SavedDocumentInfo {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;

  /// Optional: number of strokes in this document.
  /// Older saved files may not have this field; in that case we treat it as 0.
  final int strokeCount;

  /// Optional: canvas width in logical pixels.
  /// May be 0 for older entries.
  final int width;

  /// Optional: canvas height in logical pixels.
  /// May be 0 for older entries.
  final int height;

  const SavedDocumentInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.strokeCount = 0,
    this.width = 0,
    this.height = 0,
  });

  SavedDocumentInfo copyWith({
    String? id,
    String? name,
    int? createdAt,
    int? updatedAt,
    int? strokeCount,
    int? width,
    int? height,
  }) {
    return SavedDocumentInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      strokeCount: strokeCount ?? this.strokeCount,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  factory SavedDocumentInfo.fromJson(Map<String, dynamic> json) {
    return SavedDocumentInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      strokeCount: (json['strokeCount'] as int?) ?? 0,
      width: (json['width'] as int?) ?? 0,
      height: (json['height'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'strokeCount': strokeCount,
      'width': width,
      'height': height,
    };
  }
}
