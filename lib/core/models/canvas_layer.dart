// lib/core/models/canvas_layer.dart
import 'dart:ui' show Offset;

import 'stroke.dart';

/// Logical layer in the document.
class CanvasLayer {
  final String id; // e.g. 'layer-main' or uuid
  final String name; // e.g. 'Layer 1'
  final bool visible; // can hide/show layer
  final bool locked; // cannot edit when locked

  /// Transform applied to the whole layer.
  final LayerTransform transform;

  /// Groups of strokes inside this layer.
  final List<StrokeGroup> groups;

  const CanvasLayer({
    required this.id,
    required this.name,
    required this.visible,
    required this.locked,
    required this.transform,
    required this.groups,
  });

  CanvasLayer copyWith({
    String? id,
    String? name,
    bool? visible,
    bool? locked,
    LayerTransform? transform,
    List<StrokeGroup>? groups,
  }) {
    return CanvasLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      transform: transform ?? this.transform,
      groups: groups ?? this.groups,
    );
  }

  /// Convenience: flatten strokes for renderer if needed.
  List<Stroke> get allStrokes {
    return [
      for (final g in groups) ...g.strokes,
    ];
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'visible': visible,
        'locked': locked,
        'transform': transform.toJson(),
        'groups': groups.map((g) => g.toJson()).toList(),
      };

  factory CanvasLayer.fromJson(Map<String, dynamic> json) {
    return CanvasLayer(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Layer',
      visible: (json['visible'] as bool?) ?? true,
      locked: (json['locked'] as bool?) ?? false,
      transform: LayerTransform.fromJson(
        (json['transform'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      groups: (json['groups'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => StrokeGroup.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Group of strokes inside a layer.
class StrokeGroup {
  final String id; // e.g. 'group-main' or uuid
  final String name; // e.g. 'Group 1'
  final GroupTransform transform;
  final List<Stroke> strokes;

  const StrokeGroup({
    required this.id,
    required this.name,
    required this.transform,
    required this.strokes,
  });

  StrokeGroup copyWith({
    String? id,
    String? name,
    GroupTransform? transform,
    List<Stroke>? strokes,
  }) {
    return StrokeGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      transform: transform ?? this.transform,
      strokes: strokes ?? this.strokes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'transform': transform.toJson(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory StrokeGroup.fromJson(Map<String, dynamic> json) {
    return StrokeGroup(
      id: json['id'] as String? ?? 'group-main',
      name: json['name'] as String? ?? 'Group',
      transform: GroupTransform.fromJson(
        (json['transform'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      strokes: (json['strokes'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Stroke.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Transform applied to an entire layer.
class LayerTransform {
  final Offset position; // layer offset
  final double scale; // uniform scale
  final double rotation; // radians
  final double opacity; // 0–1

  const LayerTransform({
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  LayerTransform copyWith({
    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,
  }) {
    return LayerTransform(
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': position.dx,
        'y': position.dy,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
      };

  factory LayerTransform.fromJson(Map<String, dynamic> json) {
    return LayerTransform(
      position: Offset(
        (json['x'] as num?)?.toDouble() ?? 0.0,
        (json['y'] as num?)?.toDouble() ?? 0.0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Transform applied to a group of strokes within a layer.
class GroupTransform {
  final Offset position;
  final double scale;
  final double rotation;
  final double opacity;

  const GroupTransform({
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  GroupTransform copyWith({
    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,
  }) {
    return GroupTransform(
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': position.dx,
        'y': position.dy,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
      };

  factory GroupTransform.fromJson(Map<String, dynamic> json) {
    return GroupTransform(
      position: Offset(
        (json['x'] as num?)?.toDouble() ?? 0.0,
        (json['y'] as num?)?.toDouble() ?? 0.0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
