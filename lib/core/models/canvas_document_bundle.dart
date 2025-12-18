import 'canvas_doc.dart';
import 'stroke.dart';
import 'canvas_layer.dart';

/// A full editable drawing document: metadata + layers (preferred) + strokes (legacy).
class CanvasDocumentBundle {
  final CanvasDoc doc;

  /// Preferred: full layer tree (layers -> groups -> strokes).
  /// New saves will include this.
  final List<CanvasLayer>? layers;

  /// Which layer was active when saved (optional; defaults on load).
  final String? activeLayerId;

  /// Legacy flattened strokes list. Kept for backwards compatibility + fast export.
  final List<Stroke> strokes;

  const CanvasDocumentBundle({
    required this.doc,
    required this.strokes,
    this.layers,
    this.activeLayerId,
  });

  CanvasDocumentBundle copyWith({
    CanvasDoc? doc,
    List<Stroke>? strokes,
    List<CanvasLayer>? layers,
    String? activeLayerId,
  }) {
    return CanvasDocumentBundle(
      doc: doc ?? this.doc,
      strokes: strokes ?? this.strokes,
      layers: layers ?? this.layers,
      activeLayerId: activeLayerId ?? this.activeLayerId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'doc': doc.toJson(),

        // New format:
        if (layers != null) 'layers': layers!.map((l) => l.toJson()).toList(),
        if (activeLayerId != null) 'activeLayerId': activeLayerId,

        // Legacy:
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory CanvasDocumentBundle.fromJson(Map<String, dynamic> json) {
    final doc =
        CanvasDoc.fromJson((json['doc'] as Map).cast<String, dynamic>());

    // New:
    final List<CanvasLayer>? layers = (json['layers'] is List)
        ? (json['layers'] as List)
            .whereType<Map>()
            .map((e) => CanvasLayer.fromJson(e.cast<String, dynamic>()))
            .toList()
        : null;

    final String? activeLayerId = json['activeLayerId'] as String?;

    // Legacy:
    final strokes = (json['strokes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Stroke.fromJson(e.cast<String, dynamic>()))
        .toList();

    return CanvasDocumentBundle(
      doc: doc,
      strokes: strokes,
      layers: layers,
      activeLayerId: activeLayerId,
    );
  }
}
