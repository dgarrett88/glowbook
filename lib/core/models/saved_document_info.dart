/// Lightweight metadata for listing saved drawings.
class SavedDocumentInfo {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;

  const SavedDocumentInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  SavedDocumentInfo copyWith({
    String? id,
    String? name,
    int? createdAt,
    int? updatedAt,
  }) {
    return SavedDocumentInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory SavedDocumentInfo.fromJson(Map<String, dynamic> json) {
    return SavedDocumentInfo(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}
