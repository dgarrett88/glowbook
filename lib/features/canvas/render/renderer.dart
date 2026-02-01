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

/// Render entry = a stroke plus the layer it belongs to.
/// Stroke points are stored in "layer-local" space (for committed strokes).
class _RenderEntry {
  final Stroke strokeLocal;
  final String layerId;

  _RenderEntry({
    required this.strokeLocal,
    required this.layerId,
  });
}

class Renderer extends CustomPainter {
  Renderer(
    this.repaint,
    this.symmetryFn, {
    // ✅ NEW: get latest layer transform live (prevents stale pivot/rotation bugs)
    required LayerTransform Function(String layerId) layerTransformFn,

    // LAYER extras
    required double Function(String layerId) layerExtraRotationRadians,
    double Function(String layerId)? layerExtraX,
    double Function(String layerId)? layerExtraY,
    double Function(String layerId)? layerExtraScale,
    double Function(String layerId)? layerExtraOpacity,

    // STROKE extras
    double Function(String layerId, String strokeId)? strokeExtraX,
    double Function(String layerId, String strokeId)? strokeExtraY,
    double Function(String layerId, String strokeId)? strokeExtraRotationRad,
    double Function(String layerId, String strokeId)? strokeExtraSize,
    double Function(String layerId, String strokeId)? strokeExtraCoreOpacity,
    double Function(String layerId, String strokeId)? strokeExtraGlowRadius,
    double Function(String layerId, String strokeId)? strokeExtraGlowOpacity,
    double Function(String layerId, String strokeId)? strokeExtraGlowBrightness,
    required String? Function() selectedStrokeIdFn,
  })  : _layerTransformFn = layerTransformFn,
        _layerExtraRotationRadians = layerExtraRotationRadians,
        _layerExtraX = layerExtraX,
        _layerExtraY = layerExtraY,
        _layerExtraScale = layerExtraScale,
        _layerExtraOpacity = layerExtraOpacity,
        _strokeExtraX = strokeExtraX,
        _strokeExtraY = strokeExtraY,
        _strokeExtraRotationRad = strokeExtraRotationRad,
        _strokeExtraSize = strokeExtraSize,
        _strokeExtraCoreOpacity = strokeExtraCoreOpacity,
        _strokeExtraGlowRadius = strokeExtraGlowRadius,
        _strokeExtraGlowOpacity = strokeExtraGlowOpacity,
        _strokeExtraGlowBrightness = strokeExtraGlowBrightness,
        _selectedStrokeIdFn = selectedStrokeIdFn,
        super(repaint: repaint);

  final Listenable repaint;
  final SymmetryMode Function() symmetryFn;

  // ---------------------------------------------------------------------------
  // CALLBACKS (from controller)
  // ---------------------------------------------------------------------------

  /// ✅ Get latest layer transform by id (so pivot updates take effect immediately)
  final LayerTransform Function(String layerId) _layerTransformFn;

  /// Returns the current extra rotation (radians) for a layer due to animation.
  final double Function(String layerId) _layerExtraRotationRadians;

  /// Returns extra translation in world pixels for a layer due to animation.
  final double Function(String layerId)? _layerExtraX;
  final double Function(String layerId)? _layerExtraY;

  /// Returns extra scale delta for a layer (interpreted as multiplier delta).
  /// Effective scale = baseScale * (1 + extraScale)
  final double Function(String layerId)? _layerExtraScale;

  /// Returns extra opacity delta for a layer (additive).
  /// Effective opacity = clamp(baseOpacity + extraOpacity, 0..1)
  final double Function(String layerId)? _layerExtraOpacity;

  /// Stroke extras (all additive, except rotation already radians)
  final double Function(String layerId, String strokeId)? _strokeExtraX;
  final double Function(String layerId, String strokeId)? _strokeExtraY;
  final double Function(String layerId, String strokeId)?
      _strokeExtraRotationRad;

  final double Function(String layerId, String strokeId)? _strokeExtraSize;
  final double Function(String layerId, String strokeId)?
      _strokeExtraCoreOpacity;
  final double Function(String layerId, String strokeId)?
      _strokeExtraGlowRadius;
  final double Function(String layerId, String strokeId)?
      _strokeExtraGlowOpacity;
  final double Function(String layerId, String strokeId)?
      _strokeExtraGlowBrightness;

  /// Returns currently selected stroke id (or null).
  final String? Function() _selectedStrokeIdFn;

  bool get _strokeExtrasEnabled =>
      _strokeExtraX != null ||
      _strokeExtraY != null ||
      _strokeExtraRotationRad != null ||
      _strokeExtraSize != null ||
      _strokeExtraCoreOpacity != null ||
      _strokeExtraGlowRadius != null ||
      _strokeExtraGlowOpacity != null ||
      _strokeExtraGlowBrightness != null;

  // ---------------------------------------------------------------------------

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

  _RenderEntry? _activeEntry; // current drawing context (layer + stroke)
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

  /// Call when a stroke begins.
  /// - For normal drawing: strokeLocal points are layer-local, layerId = actual layer id.
  /// - For "draw in world then bake on lift": strokeLocal points are WORLD, layerId='__WORLD__'
  void beginStroke(Stroke strokeLocal, String layerId, LayerTransform layerTr) {
    // layerTr is intentionally ignored: we always pull latest transform by id.
    _activeEntry = _RenderEntry(strokeLocal: strokeLocal, layerId: layerId);
  }

  void updateStroke(Stroke strokeLocal) {
    if (_activeEntry == null) return;
    _activeEntry = _RenderEntry(
      strokeLocal: strokeLocal,
      layerId: _activeEntry!.layerId,
    );
  }

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

    // rebuild entries in correct z order
    for (final layer in layers) {
      if (!layer.visible) continue;

      for (final group in layer.groups) {
        for (final s in group.strokes) {
          if (!s.visible) continue;
          _entries.add(_RenderEntry(strokeLocal: s, layerId: layer.id));
        }
      }
    }

    // While stroke-extras are enabled, do NOT bake anything.
    if (_strokeExtrasEnabled) return;

    final selectedId = _selectedStrokeIdFn();
    final sz = _lastSize ?? const Size(0, 0);

    for (final e in _entries) {
      final sid = e.strokeLocal.id;

      final extraRot = _layerExtraRotationRadians(e.layerId);
      final extraX = _layerExtraX?.call(e.layerId) ?? 0.0;
      final extraY = _layerExtraY?.call(e.layerId) ?? 0.0;
      final extraScale = _layerExtraScale?.call(e.layerId) ?? 0.0;
      final extraOpacity = _layerExtraOpacity?.call(e.layerId) ?? 0.0;

      final isLayerAnimated = extraRot.abs() > 0.000001 ||
          extraX.abs() > 0.000001 ||
          extraY.abs() > 0.000001 ||
          extraScale.abs() > 0.000001 ||
          extraOpacity.abs() > 0.000001;

      if (isLayerAnimated) continue;
      if (selectedId != null && sid == selectedId) continue;

      final rec = ui.PictureRecorder();
      final can = Canvas(rec);

      final baseTr = _layerTransformFn(e.layerId);

      final world = _strokeToWorldWithLayerExtras(
        e.strokeLocal,
        baseTr,
        e.layerId,
        freezeExtras: false,
      );

      _drawByBrush(can, world, sz, _modeForStroke(world));
      _bakedByStrokeId[sid] = rec.endRecording();
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

  Offset _strokeBoundsCenterLocal(Stroke sLocal) {
    double? minX, maxX, minY, maxY;
    for (final pt in sLocal.points) {
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
    return Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
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

  LayerTransform _effectiveLayerTransform(
    LayerTransform base,
    String layerId, {
    required bool freezeExtras,
  }) {
    if (freezeExtras) return base;

    final dx = _layerExtraX?.call(layerId) ?? 0.0;
    final dy = _layerExtraY?.call(layerId) ?? 0.0;
    final extraRot = _layerExtraRotationRadians(layerId);
    final extraScale = _layerExtraScale?.call(layerId) ?? 0.0;
    final extraOpacity = _layerExtraOpacity?.call(layerId) ?? 0.0;

    final scaleMul = (1.0 + extraScale).clamp(0.01, 100.0).toDouble();
    final effScale = (base.scale * scaleMul).clamp(0.01, 100.0).toDouble();
    final effOpacity = (base.opacity + extraOpacity).clamp(0.0, 1.0).toDouble();

    return base.copyWith(
      position: base.position + Offset(dx, dy),
      rotation: base.rotation + extraRot,
      scale: effScale,
      opacity: effOpacity,
      pivot: base.pivot, // keep pivot stable
    );
  }

  Stroke _strokeToWorldWithLayerExtras(
    Stroke sLocal,
    LayerTransform baseLayerTr,
    String layerId, {
    required bool freezeExtras,
  }) {
    final t = _effectiveLayerTransform(
      baseLayerTr,
      layerId,
      freezeExtras: freezeExtras,
    );

    if (_isIdentity(t)) return sLocal;

    // ✅ Never rotate around (0,0) when pivot is missing.
    // Prefer layer pivot; fallback to stroke bounds center (local).
    final pivotLocal = t.pivot ?? _strokeBoundsCenterLocal(sLocal);

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

  Offset _strokeWorldCentroid(Stroke sWorld) {
    final pts = sWorld.points;
    if (pts.isEmpty) return Offset.zero;
    double sx = 0.0, sy = 0.0;
    for (final p in pts) {
      sx += p.x;
      sy += p.y;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  // ---------------------------------------------------------------------------
  // ✅ NEW HELPERS: smoother 0..1 modulation without clamp "dead zones"
  // ---------------------------------------------------------------------------

  /// Applies a 0..1 "extra" smoothly as modulation based on knob base value.
  ///
  /// - If extra >= 0: treat as "depth up" (base -> base+extra).
  /// - If extra < 0: treat as "depth down" (base -> base+extra).
  ///
  /// The key is that `u` should be UNIPOLAR [0..1] (sine mapped etc),
  /// so the result never spends half the cycle stuck at 0 due to clamping.
  double _applyUnitMod(double base, double extra, {required double u}) {
    final b = base.clamp(0.0, 1.0).toDouble();
    final uu = u.clamp(0.0, 1.0).toDouble();
    final e = extra;

    // base + (depth * u)
    final v = (b + e * uu).clamp(0.0, 1.0).toDouble();
    return v;
  }

  Stroke _applyStrokeExtrasWorld(
    Stroke sWorld,
    String layerId,
    String strokeId, {
    required bool freezeExtras,
  }) {
    if (freezeExtras) return sWorld;

    final dx = _strokeExtraX?.call(layerId, strokeId) ?? 0.0;
    final dy = _strokeExtraY?.call(layerId, strokeId) ?? 0.0;
    final rot = _strokeExtraRotationRad?.call(layerId, strokeId) ?? 0.0;

    final dSize = _strokeExtraSize?.call(layerId, strokeId) ?? 0.0;

    // These extras should be produced by controller as UNIPOLAR-shaped deltas
    // for smooth modulation (ex: u = (raw+1)/2).
    final dCoreOp = _strokeExtraCoreOpacity?.call(layerId, strokeId) ?? 0.0;
    final dGlowRadius = _strokeExtraGlowRadius?.call(layerId, strokeId) ?? 0.0;
    final dGlowOp = _strokeExtraGlowOpacity?.call(layerId, strokeId) ?? 0.0;
    final dGlowBright =
        _strokeExtraGlowBrightness?.call(layerId, strokeId) ?? 0.0;

    final hasGeo =
        dx.abs() > 0.000001 || dy.abs() > 0.000001 || rot.abs() > 0.000001;

    Stroke outStroke = sWorld;

    // Geometry (translate + rotate around centroid in WORLD)
    if (hasGeo) {
      final pivot = _strokeWorldCentroid(outStroke);
      final cosA = math.cos(rot);
      final sinA = math.sin(rot);
      final outPts = <PointSample>[];

      for (final p in outStroke.points) {
        final base = Offset(p.x + dx, p.y + dy);
        final v = base - pivot;
        final r = Offset(
          v.dx * cosA - v.dy * sinA,
          v.dx * sinA + v.dy * cosA,
        );
        final w = pivot + r;
        outPts.add(PointSample(w.dx, w.dy, p.t));
      }
      outStroke = outStroke.copyWith(points: outPts);
    }

    // Visual params
    // Size stays additive (unbounded)
    final newSize = (outStroke.size + dSize).clamp(0.5, 500.0).toDouble();

    // ✅ VISUAL PARAMS: controller now returns FINAL values (Vital-style)
    final coreOpacity = _strokeExtraCoreOpacity != null
        ? _strokeExtraCoreOpacity!(layerId, strokeId)
        : outStroke.coreOpacity;

    final glowRadius = _strokeExtraGlowRadius != null
        ? _strokeExtraGlowRadius!(layerId, strokeId)
        : outStroke.glowRadius;

    final glowOpacity = _strokeExtraGlowOpacity != null
        ? _strokeExtraGlowOpacity!(layerId, strokeId)
        : outStroke.glowOpacity;

    final glowBrightness = _strokeExtraGlowBrightness != null
        ? _strokeExtraGlowBrightness!(layerId, strokeId)
        : outStroke.glowBrightness;

    return outStroke.copyWith(
      size: newSize,
      coreOpacity: coreOpacity.clamp(0.0, 1.0),
      glowRadius: glowRadius.clamp(0.0, 1.0),
      glowOpacity: glowOpacity.clamp(0.0, 1.0),
      glowBrightness: glowBrightness.clamp(0.0, 1.0),
    );
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

    // Draw committed strokes
    for (final e in _entries) {
      if (!e.strokeLocal.visible) continue;

      final isSelected = (selectedId != null && e.strokeLocal.id == selectedId);
      final freezeExtras = isSelected;

      // If stroke-extras enabled, never use baked pictures.
      if (!_strokeExtrasEnabled) {
        final baked = _bakedByStrokeId[e.strokeLocal.id];
        if (!freezeExtras && baked != null) {
          canvas.drawPicture(baked);
          continue;
        }
      }

      final baseTr = _layerTransformFn(e.layerId);

      final world = _strokeToWorldWithLayerExtras(
        e.strokeLocal,
        baseTr,
        e.layerId,
        freezeExtras: freezeExtras,
      );

      final finalStroke = _applyStrokeExtrasWorld(
        world,
        e.layerId,
        e.strokeLocal.id,
        freezeExtras: freezeExtras,
      );

      _drawByBrush(canvas, finalStroke, size, _modeForStroke(finalStroke));
    }

    // Draw active in-progress stroke
    final active = _activeEntry;
    if (active != null) {
      if (!active.strokeLocal.visible) return;

      final bool activeIsWorld = active.layerId == '__WORLD__';

      // ✅ If controller is feeding WORLD points, draw as-is (no transforms/extras).
      if (activeIsWorld) {
        _drawByBrush(
          canvas,
          active.strokeLocal,
          size,
          _modeForStroke(active.strokeLocal),
        );
        return;
      }

      // Normal: layer-local -> world with extras
      final selectedId2 = _selectedStrokeIdFn();
      final isSelected =
          (selectedId2 != null && active.strokeLocal.id == selectedId2);
      final freezeExtras = isSelected;

      final baseTr = _layerTransformFn(active.layerId);

      final world = _strokeToWorldWithLayerExtras(
        active.strokeLocal,
        baseTr,
        active.layerId,
        freezeExtras: freezeExtras,
      );

      final finalStroke = _applyStrokeExtrasWorld(
        world,
        active.layerId,
        active.strokeLocal.id,
        freezeExtras: freezeExtras,
      );

      _drawByBrush(canvas, finalStroke, size, _modeForStroke(finalStroke));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
