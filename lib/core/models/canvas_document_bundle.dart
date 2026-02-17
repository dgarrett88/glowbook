import 'canvas_doc.dart';
import 'stroke.dart';
import 'canvas_layer.dart';
import 'lfo.dart'; // ✅ add
import 'package:glowbook/core/models/lfo_route.dart';

class CanvasDocumentBundle {
  final CanvasDoc doc;
  final List<CanvasLayer>? layers;
  final String? activeLayerId;
  final List<Stroke> strokes;

  // ✅ NEW: per-document LFO state
  final List<Lfo>? lfos;
  final List<LfoRoute>? lfoRoutes;

  const CanvasDocumentBundle({
    required this.doc,
    required this.strokes,
    this.layers,
    this.activeLayerId,
    this.lfos,
    this.lfoRoutes,
  });

  CanvasDocumentBundle copyWith({
    CanvasDoc? doc,
    List<Stroke>? strokes,
    List<CanvasLayer>? layers,
    String? activeLayerId,
    List<Lfo>? lfos,
    List<LfoRoute>? lfoRoutes,
  }) {
    return CanvasDocumentBundle(
      doc: doc ?? this.doc,
      strokes: strokes ?? this.strokes,
      layers: layers ?? this.layers,
      activeLayerId: activeLayerId ?? this.activeLayerId,
      lfos: lfos ?? this.lfos,
      lfoRoutes: lfoRoutes ?? this.lfoRoutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'doc': doc.toJson(),

        if (layers != null) 'layers': layers!.map((l) => l.toJson()).toList(),
        if (activeLayerId != null) 'activeLayerId': activeLayerId,

        // ✅ NEW
        if (lfos != null) 'lfos': lfos!.map((l) => l.toJson()).toList(),
        if (lfoRoutes != null)
          'lfoRoutes': lfoRoutes!.map((r) => r.toJson()).toList(),

        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory CanvasDocumentBundle.fromJson(Map<String, dynamic> json) {
    final doc =
        CanvasDoc.fromJson((json['doc'] as Map).cast<String, dynamic>());

    final List<CanvasLayer>? layers = (json['layers'] is List)
        ? (json['layers'] as List)
            .whereType<Map>()
            .map((e) => CanvasLayer.fromJson(e.cast<String, dynamic>()))
            .toList()
        : null;

    final String? activeLayerId = json['activeLayerId'] as String?;

    final strokes = (json['strokes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Stroke.fromJson(e.cast<String, dynamic>()))
        .toList();

    // ✅ NEW
    final List<Lfo>? lfos = (json['lfos'] is List)
        ? (json['lfos'] as List)
            .whereType<Map>()
            .map((e) => Lfo.fromJson(e.cast<String, dynamic>()))
            .toList()
        : null;

    final List<LfoRoute>? lfoRoutes = (json['lfoRoutes'] is List)
        ? (json['lfoRoutes'] as List)
            .whereType<Map>()
            .map((e) => LfoRoute.fromJson(e.cast<String, dynamic>()))
            .toList()
        : null;

    return CanvasDocumentBundle(
      doc: doc,
      strokes: strokes,
      layers: layers,
      activeLayerId: activeLayerId,
      lfos: lfos,
      lfoRoutes: lfoRoutes,
    );
  }
}
