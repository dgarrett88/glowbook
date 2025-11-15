class SavedDocumentInfo {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;

  /// Optional: number of strokes in this document.
  /// Older saved files may not have this field; in that case we treat it as 0.
  final int strokeCount;

  const SavedDocumentInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.strokeCount = 0,
  });

  SavedDocumentInfo copyWith({
    String? id,
    String? name,
    int? createdAt,
    int? updatedAt,
    int? strokeCount,
  }) {
    return SavedDocumentInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      strokeCount: strokeCount ?? this.strokeCount,
    );
  }

  factory SavedDocumentInfo.fromJson(Map<String, dynamic> json) {
    return SavedDocumentInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      strokeCount: (json['strokeCount'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'strokeCount': strokeCount,
    };
  }
}
