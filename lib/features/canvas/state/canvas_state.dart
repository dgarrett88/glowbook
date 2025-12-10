// lib/features/canvas/state/canvas_state.dart
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../core/models/stroke.dart';
import '../../../core/models/canvas_layer.dart';

class CanvasState {
  /// Logical layers in the document.
  /// Render order = list order (0 = bottom, last = top).
  final List<CanvasLayer> layers;

  /// ID of the currently active layer for drawing.
  final String activeLayerId;

  /// Redo stack is kept stroke-based for now.
  final List<Stroke> redoStack;

  const CanvasState({
    required this.layers,
    required this.activeLayerId,
    this.redoStack = const [],
  });

  /// Convenience factory: empty document with a single default layer/group.
  factory CanvasState.initial() {
    return const CanvasState(
      layers: [
        CanvasLayer(
          id: 'layer-main',
          name: 'Layer 1',
          visible: true,
          locked: false,
          transform: LayerTransform(),
          groups: [
            StrokeGroup(
              id: 'group-main',
              name: 'Group 1',
              transform: GroupTransform(),
              strokes: [],
            ),
          ],
        ),
      ],
      activeLayerId: 'layer-main',
      redoStack: [],
    );
  }

  /// Wrap an old flat stroke list into a single layer + group.
  factory CanvasState.fromStrokes(List<Stroke> strokes) {
    return CanvasState(
      layers: [
        CanvasLayer(
          id: 'layer-main',
          name: 'Layer 1',
          visible: true,
          locked: false,
          transform: const LayerTransform(),
          groups: [
            StrokeGroup(
              id: 'group-main',
              name: 'Group 1',
              transform: const GroupTransform(),
              strokes: List<Stroke>.from(strokes),
            ),
          ],
        ),
      ],
      activeLayerId: 'layer-main',
      redoStack: const [],
    );
  }

  CanvasState copyWith({
    List<CanvasLayer>? layers,
    String? activeLayerId,
    List<Stroke>? redoStack,
  }) {
    return CanvasState(
      layers: layers ?? this.layers,
      activeLayerId: activeLayerId ?? this.activeLayerId,
      redoStack: redoStack ?? this.redoStack,
    );
  }

  /// Helper: get the active layer (fallback to first if missing).
  CanvasLayer get activeLayer {
    final found = layers.where((l) => l.id == activeLayerId);
    if (found.isNotEmpty) return found.first;
    return layers.isNotEmpty
        ? layers.first
        : const CanvasLayer(
            id: 'layer-main',
            name: 'Layer 1',
            visible: true,
            locked: false,
            transform: LayerTransform(),
            groups: [
              StrokeGroup(
                id: 'group-main',
                name: 'Group 1',
                transform: GroupTransform(),
                strokes: [],
              ),
            ],
          );
  }

  /// Flatten all visible strokes in layer order,
  /// applying layer transforms around the layer's own bounds centre
  /// AND per-layer opacity.
  List<Stroke> get allStrokes {
    final result = <Stroke>[];

    for (final layer in layers) {
      if (!layer.visible) continue;

      final t = layer.transform;

      // Layer opacity 0..1
      final double layerOpacity = t.opacity.clamp(0.0, 1.0);
      if (layerOpacity <= 0.001) {
        // Effectively invisible → skip whole layer.
        continue;
      }

      // Fast path: identity geometry → just apply opacity to strokes.
      final bool isIdentityGeometry =
          t.position == Offset.zero && t.scale == 1.0 && t.rotation == 0.0;

      if (isIdentityGeometry) {
        for (final group in layer.groups) {
          for (final stroke in group.strokes) {
            if (layerOpacity >= 0.999) {
              // Fully opaque → original stroke.
              result.add(stroke);
            } else {
              final int c = stroke.color;
              final int a = (c >> 24) & 0xFF;
              final int rgb = c & 0x00FFFFFF;
              final int newA = (a * layerOpacity).round().clamp(0, 255);
              final int newColor = (newA << 24) | rgb;

              result.add(
                stroke.copyWith(color: newColor),
              );
            }
          }
        }
        continue;
      }

      // -------------------------------------------------------------------
      // Non-identity geometry → we need pivot, rotation, scale, translation.
      // -------------------------------------------------------------------

      // Collect all points in this layer to compute a tight bounding box.
      double? minX, maxX, minY, maxY;
      for (final group in layer.groups) {
        for (final stroke in group.strokes) {
          for (final p in stroke.points) {
            final x = p.x;
            final y = p.y;
            if (minX == null || x < minX) minX = x;
            if (maxX == null || x > maxX) maxX = x;
            if (minY == null || y < minY) minY = y;
            if (maxY == null || y > maxY) maxY = y;
          }
        }
      }

      // If the layer has no strokes, skip it.
      if (minX == null || minY == null || maxX == null || maxY == null) {
        continue;
      }

      // Pivot at the centre of the layer's bounds.
      final pivot = Offset(
        (minX + maxX) / 2.0,
        (minY + maxY) / 2.0,
      );

      final double angle = t.rotation; // radians
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      final double scale = t.scale;
      final Offset offset = t.position;

      // Apply transform to every point in this layer.
      for (final group in layer.groups) {
        for (final stroke in group.strokes) {
          final transformedPoints = <PointSample>[];

          for (final p in stroke.points) {
            final original = Offset(p.x, p.y);

            // Make coordinates relative to pivot
            final local = original - pivot;

            // Rotate
            final rotated = Offset(
              local.dx * cosA - local.dy * sinA,
              local.dx * sinA + local.dy * cosA,
            );

            // Scale
            final scaled = rotated * scale;

            // Move back from pivot and then apply layer position offset
            final finalPos = scaled + pivot + offset;

            transformedPoints.add(
              PointSample(finalPos.dx, finalPos.dy, p.t),
            );
          }

          if (layerOpacity >= 0.999) {
            // Only geometry change
            result.add(
              stroke.copyWith(points: transformedPoints),
            );
          } else {
            // Geometry + opacity change
            final int c = stroke.color;
            final int a = (c >> 24) & 0xFF;
            final int rgb = c & 0x00FFFFFF;
            final int newA = (a * layerOpacity).round().clamp(0, 255);
            final int newColor = (newA << 24) | rgb;

            result.add(
              stroke.copyWith(
                points: transformedPoints,
                color: newColor,
              ),
            );
          }
        }
      }
    }

    return result;
  }
}
