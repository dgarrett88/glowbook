// lib/features/canvas/render/renderer.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';

import '../../../core/models/canvas_layer.dart';
import '../../../core/models/stroke.dart';
import '../state/canvas_controller.dart';
import 'brushes/edge_glow.dart';
import 'brushes/ghost_trail.dart';
import 'brushes/glow_only.dart';
import 'brushes/hyper_neon.dart';
import 'brushes/inner_glow.dart';
import 'brushes/liquid_neon.dart';
import 'brushes/soft_glow.dart';

/// Render entry = a stroke plus the layer context it belongs to.
/// Stroke points are stored in "layer-local" space.
class _RenderEntry {
  final Stroke strokeLocal;
  final String layerId;
  final LayerTransform layerTransform;

  _RenderEntry({
    required this.strokeLocal,
    required this.layerId,
    required this.layerTransform,
  });
}

class Renderer extends CustomPainter {
  Renderer(
    this.repaint,
    this.symmetryFn, {
    required double Function(String layerId) layerExtraRotationRadians,
    required String? Function() selectedStrokeIdFn,
  })  : _layerExtraRotationRadians = layerExtraRotationRadians,
        _selectedStrokeIdFn = selectedStrokeIdFn,
        super(repaint: repaint);

  final Listenable repaint;
  final SymmetryMode Function() symmetryFn;

  /// Returns the current extra rotation (radians) for a layer due to animation.
  final double Function(String layerId) _layerExtraRotationRadians;

  /// Returns currently selected stroke id (or null).
  final String? Function() _selectedStrokeIdFn;

  final LiquidNeonBrush _neon = LiquidNeonBrush();
  final SoftGlowBrush _soft = SoftGlowBrush();
  final GlowOnlyBrush _glowOnly = GlowOnlyBrush();
  final HyperNeonBrush _hyper = const HyperNeonBrush();
  final EdgeGlowBrush _edge = const EdgeGlowBrush();
  final GhostTrailBrush _ghost = const GhostTrailBrush();
  final InnerGlowBrush _inner = const InnerGlowBrush();

  final List<_RenderEntry> _entries = <_RenderEntry>[];

  /// Cache baked pictures ONLY for strokes that are not animated and not selected.
  /// Key = stroke id.
  final Map<String, ui.Picture> _bakedByStrokeId = <String, ui.Picture>{};

  _RenderEntry? _activeEntry; // current drawing context (layer + transform)
  Size? _lastSize;

  SymmetryMode _modeForStroke(Stroke s) {
    final id = s.symmetryId;
    if (id == null) return symmetryFn();
    switch (id) {
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

  // ---------------------------------------------------------------------------
  // PUBLIC API USED BY CONTROLLER
  // ---------------------------------------------------------------------------

  /// Call when a stroke begins (we receive the stroke in layer-local space),
  /// plus the layer transform it belongs to.
  void beginStroke(Stroke strokeLocal, String layerId, LayerTransform layerTr) {
    _activeEntry = _RenderEntry(
      strokeLocal: strokeLocal,
      layerId: layerId,
      layerTransform: layerTr,
    );
  }

  void updateStroke(Stroke strokeLocal) {
    if (_activeEntry == null) return;
    _activeEntry = _RenderEntry(
      strokeLocal: strokeLocal,
      layerId: _activeEntry!.layerId,
      layerTransform: _activeEntry!.layerTransform,
    );
  }

  /// Commit doesn't bake to pictures (animation exists). Controller will call
  /// rebuildFromLayers after commit anyway.
  void commitStroke() {
    _activeEntry = null;
  }

  /// Rebuild the render list from authoritative layer state (layer-local points).
  void rebuildFromLayers(List<CanvasLayer> layers) {
    _entries.clear();

    // dispose old baked
    for (final p in _bakedByStrokeId.values) {
      p.dispose();
    }
    _bakedByStrokeId.clear();

    // rebuild entries in correct z order: layers list order then stroke order inside groups
    for (final layer in layers) {
      if (!layer.visible) continue;

      for (final group in layer.groups) {
        for (final s in group.strokes) {
          if (!s.visible) continue; // ✅ skip hidden strokes
          _entries.add(_RenderEntry(
            strokeLocal: s,
            layerId: layer.id,
            layerTransform: layer.transform,
          ));
        }
      }
    }

    // pre-bake only strokes on layers that currently have 0 extra rotation
    // (static), AND not selected.
    final selectedId = _selectedStrokeIdFn();
    final sz = _lastSize ?? const Size(0, 0);

    for (final e in _entries) {
      final extra = _layerExtraRotationRadians(e.layerId);
      if (extra.abs() > 0.000001) continue; // animated layer: no bake
      if (selectedId != null && e.strokeLocal.id == selectedId) continue;

      final rec = ui.PictureRecorder();
      final can = Canvas(rec);

      final baseWorld = _strokeToWorld(e.strokeLocal, e.layerTransform);
      _drawByBrush(can, baseWorld, sz, _modeForStroke(baseWorld));

      _bakedByStrokeId[e.strokeLocal.id] = rec.endRecording();
    }
  }

  // ---------------------------------------------------------------------------
  // TRANSFORM HELPERS
  // ---------------------------------------------------------------------------

  bool _isIdentity(LayerTransform t) {
    return t.position == Offset.zero &&
        t.scale == 1.0 &&
        t.rotation == 0.0 &&
        t.opacity == 1.0;
  }

  Offset _computeBoundsPivotForEntry(_RenderEntry e) {
    // If pivot is set, it is already in canvas coords.
    final p = e.layerTransform.pivot;
    if (p != null) return p;

    // Fallback: bounds center of stroke points (layer-local)
    double? minX, maxX, minY, maxY;
    for (final pt in e.strokeLocal.points) {
      final x = pt.x;
      final y = pt.y;
      minX = (minX == null) ? x : math.min(minX, x);
      maxX = (maxX == null) ? x : math.max(maxX, x);
      minY = (minY == null) ? y : math.min(minY, y);
      maxY = (maxY == null) ? y : math.max(maxY, y);
    }
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return Offset.zero;
    }

    final localCenter = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);

    // Base transform about localCenter (good-enough fallback)
    return _forward(localCenter, e.layerTransform, localCenter);
  }

  Offset _forward(Offset p, LayerTransform t, Offset pivotLocal) {
    final angle = t.rotation;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final local = p - pivotLocal;

    final rotated = Offset(
      local.dx * cosA - local.dy * sinA,
      local.dx * sinA + local.dy * cosA,
    );

    final scaled = rotated * t.scale;

    return scaled + pivotLocal + t.position;
  }

  Stroke _strokeToWorld(Stroke sLocal, LayerTransform t) {
    if (_isIdentity(t)) return sLocal;

    final pivotLocal = t.pivot ?? Offset.zero;

    final opacityMul = t.opacity.clamp(0.0, 1.0);

    final out = <PointSample>[];
    for (final p in sLocal.points) {
      final w = _forward(Offset(p.x, p.y), t, pivotLocal);
      out.add(PointSample(w.dx, w.dy, p.t));
    }

    return sLocal.copyWith(
      points: out,
      coreOpacity: (sLocal.coreOpacity * opacityMul).clamp(0.0, 1.0),
      glowOpacity: (sLocal.glowOpacity * opacityMul).clamp(0.0, 1.0),
    );
  }

  Stroke _applyExtraRotationWorld(
      Stroke sWorld, double extraRad, Offset pivotWorld) {
    if (extraRad.abs() < 0.000001) return sWorld;

    final cosA = math.cos(extraRad);
    final sinA = math.sin(extraRad);

    final out = <PointSample>[];
    for (final p in sWorld.points) {
      final v = Offset(p.x, p.y) - pivotWorld;
      final r = Offset(
        v.dx * cosA - v.dy * sinA,
        v.dx * sinA + v.dy * cosA,
      );
      final w = pivotWorld + r;
      out.add(PointSample(w.dx, w.dy, p.t));
    }
    return sWorld.copyWith(points: out);
  }

  void _drawByBrush(Canvas canvas, Stroke s, Size sz, SymmetryMode mode) {
    switch (s.brushId) {
      case 'glow_only':
        _glowOnly.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'soft_glow':
        _soft.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'hyper_neon':
        _hyper.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'edge_glow':
        _edge.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'ghost_trail':
        _ghost.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'inner_glow':
        _inner.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
      case 'liquid_neon':
      default:
        _neon.drawFullWithSymmetry(canvas, s, sz, mode);
        break;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _lastSize = size;

    final selectedId = _selectedStrokeIdFn();

    // Draw all committed strokes
    for (final e in _entries) {
      if (!e.strokeLocal.visible) continue; // ✅ safety

      final baseWorld = _strokeToWorld(e.strokeLocal, e.layerTransform);

      // ✅ if selected, it "stops animating" so extra = 0
      final extra = (selectedId != null && e.strokeLocal.id == selectedId)
          ? 0.0
          : _layerExtraRotationRadians(e.layerId);

      // If we have a baked picture and this stroke is static, draw it
      final baked = _bakedByStrokeId[e.strokeLocal.id];
      if (baked != null && extra.abs() < 0.000001) {
        canvas.drawPicture(baked);
        continue;
      }

      // Otherwise draw live (needed for animation and selection edits)
      final pivotWorld =
          e.layerTransform.pivot ?? _computeBoundsPivotForEntry(e);
      final animatedWorld =
          _applyExtraRotationWorld(baseWorld, extra, pivotWorld);

      _drawByBrush(canvas, animatedWorld, size, _modeForStroke(animatedWorld));
    }

    // Draw active in-progress stroke (live)
    final active = _activeEntry;
    if (active != null) {
      if (!active.strokeLocal.visible) return;

      final baseWorld =
          _strokeToWorld(active.strokeLocal, active.layerTransform);

      final extra = (selectedId != null && active.strokeLocal.id == selectedId)
          ? 0.0
          : _layerExtraRotationRadians(active.layerId);

      final pivotWorld =
          active.layerTransform.pivot ?? _computeBoundsPivotForEntry(active);
      final animatedWorld =
          _applyExtraRotationWorld(baseWorld, extra, pivotWorld);

      _drawByBrush(canvas, animatedWorld, size, _modeForStroke(animatedWorld));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
