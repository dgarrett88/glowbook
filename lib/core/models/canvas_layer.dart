// lib/core/models/canvas_layer.dart
import 'dart:ui';

import 'stroke.dart';

/// Logical layer in the document.
/// Initially this is just a wrapper around one default group,
/// but it gives us a solid place to hang transforms + LFOs later.
class CanvasLayer {
  final String id; // e.g. 'layer-main' or uuid
  final String name; // e.g. 'Layer 1'
  final bool visible; // can hide/show layer
  final bool locked; // cannot edit when locked

  /// Transform applied to the whole layer.
  /// LFOs will eventually modulate this.
  final LayerTransform transform;

  /// Groups of strokes inside this layer.
  /// For now we just use one default group, but this supports more.
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
}

/// Group of strokes inside a layer.
/// This is our hook for selection, grab/move, and per-group LFOs.
class StrokeGroup {
  final String id; // e.g. 'group-main' or uuid
  final String name; // e.g. 'Group 1'

  /// Transform for this group relative to its layer.
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
}
