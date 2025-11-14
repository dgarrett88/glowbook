import 'canvas_doc.dart';
import 'stroke.dart';

/// A full editable drawing document: metadata + all strokes.
class CanvasDocumentBundle {
  final CanvasDoc doc;
  final List<Stroke> strokes;

  const CanvasDocumentBundle({
    required this.doc,
    required this.strokes,
  });

  CanvasDocumentBundle copyWith({
    CanvasDoc? doc,
    List<Stroke>? strokes,
  }) {
    return CanvasDocumentBundle(
      doc: doc ?? this.doc,
      strokes: strokes ?? this.strokes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'doc': doc.toJson(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory CanvasDocumentBundle.fromJson(Map<String, dynamic> json) {
    return CanvasDocumentBundle(
      doc: CanvasDoc.fromJson((json['doc'] as Map).cast<String, dynamic>()),
      strokes: (json['strokes'] as List)
          .map((e) => Stroke.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
