// lib/features/canvas/render/renderer.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:characters/characters.dart';

import '../../../core/models/canvas_layer.dart';
import '../../../core/models/canvas_text_object.dart';
import '../../../core/models/stroke.dart';
import '../state/canvas_controller.dart';
import '../state/glow_blend.dart' as gb;
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
    required double Function() previewScaleFn,
    required Size Function() previewFullSizeFn,
    required int Function() backgroundColorFn,
    required List<CanvasTextObject> Function() textObjectsFn,

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

    // TEXT extras
    double Function(String layerId, String textObjectId)? textExtraX,
    double Function(String layerId, String textObjectId)? textExtraY,
    double Function(String layerId, String textObjectId)? textExtraScale,
    double Function(String layerId, String textObjectId)? textExtraRotationRad,
    double Function(String layerId, String textObjectId)? textFontSizeEffective,
    double Function(String layerId, String textObjectId)? textOpacityEffective,
    double Function(String layerId, String textObjectId)? textGlowRadiusEffective,
    double Function(String layerId, String textObjectId)? textGlowOpacityEffective,
    double Function(String layerId, String textObjectId)? textGlowBrightnessEffective,
    double Function(String layerId, String textObjectId)? textEdgeGlowWidthEffective,
    double Function(String layerId, String textObjectId)? textEdgeGlowStrengthEffective,

    required String? Function() selectedStrokeIdFn,
    required String? Function() selectedTextObjectIdFn,
  })  : _layerTransformFn = layerTransformFn,
        _textObjectsFn = textObjectsFn,
        _previewScaleFn = previewScaleFn,
        _previewFullSizeFn = previewFullSizeFn,
        _backgroundColorFn = backgroundColorFn,
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
        _textExtraX = textExtraX,
        _textExtraY = textExtraY,
        _textExtraScale = textExtraScale,
        _textExtraRotationRad = textExtraRotationRad,
        _textFontSizeEffective = textFontSizeEffective,
        _textOpacityEffective = textOpacityEffective,
        _textGlowRadiusEffective = textGlowRadiusEffective,
        _textGlowOpacityEffective = textGlowOpacityEffective,
        _textGlowBrightnessEffective = textGlowBrightnessEffective,
        _textEdgeGlowWidthEffective = textEdgeGlowWidthEffective,
        _textEdgeGlowStrengthEffective = textEdgeGlowStrengthEffective,
        _selectedStrokeIdFn = selectedStrokeIdFn,
        _selectedTextObjectIdFn = selectedTextObjectIdFn,
        super(repaint: repaint);

  final Listenable repaint;
  final SymmetryMode Function() symmetryFn;

  // ---------------------------------------------------------------------------
  // PREVIEW SCALE CALLBACKS
  // ---------------------------------------------------------------------------

  /// The live preview CustomPaint may be physically smaller than the full canvas.
  /// Renderer still works in full logical/world coordinates and scales down inside paint.
  final double Function() _previewScaleFn;
  final Size Function() _previewFullSizeFn;

  /// Renderer-owned opaque background.
  ///
  /// This is important for non-additive blend modes like multiply/screen/overlay,
  /// because strokes must blend against real background pixels inside the same
  /// painted scene, not against a transparent CustomPaint surface.
  final int Function() _backgroundColorFn;

  /// Live text object list supplied by CanvasController.
  /// Keeping this as a callback means text updates do not need to rebuild the
  /// whole stroke render cache.
  final List<CanvasTextObject> Function() _textObjectsFn;

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

  /// Returns extra scale delta for a layer as:
  /// finalScale - baseScale
  /// Effective scale = baseScale + extraScale
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

  /// Text extras/effective visual values.
  final double Function(String layerId, String textObjectId)? _textExtraX;
  final double Function(String layerId, String textObjectId)? _textExtraY;
  final double Function(String layerId, String textObjectId)? _textExtraScale;
  final double Function(String layerId, String textObjectId)? _textExtraRotationRad;
  final double Function(String layerId, String textObjectId)? _textFontSizeEffective;
  final double Function(String layerId, String textObjectId)? _textOpacityEffective;
  final double Function(String layerId, String textObjectId)? _textGlowRadiusEffective;
  final double Function(String layerId, String textObjectId)? _textGlowOpacityEffective;
  final double Function(String layerId, String textObjectId)? _textGlowBrightnessEffective;
  final double Function(String layerId, String textObjectId)? _textEdgeGlowWidthEffective;
  final double Function(String layerId, String textObjectId)? _textEdgeGlowStrengthEffective;

  /// Returns currently selected stroke id (or null).
  final String? Function() _selectedStrokeIdFn;

  /// Returns currently selected text object id (or null).
  final String? Function() _selectedTextObjectIdFn;

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
  final Set<String> _visibleLayerIds = <String>{};

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
    _visibleLayerIds.clear();

    // dispose old baked
    for (final p in _bakedByStrokeId.values) {
      p.dispose();
    }
    _bakedByStrokeId.clear();

    // rebuild entries in correct z order
    for (final layer in layers) {
      if (!layer.visible) continue;
      _visibleLayerIds.add(layer.id);

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

  bool _layerHasLiveExtrasNow(String layerId) {
    final extraRot = _layerExtraRotationRadians(layerId);
    final extraX = _layerExtraX?.call(layerId) ?? 0.0;
    final extraY = _layerExtraY?.call(layerId) ?? 0.0;
    final extraScale = _layerExtraScale?.call(layerId) ?? 0.0;
    final extraOpacity = _layerExtraOpacity?.call(layerId) ?? 0.0;

    return extraRot.abs() > 0.000001 ||
        extraX.abs() > 0.000001 ||
        extraY.abs() > 0.000001 ||
        extraScale.abs() > 0.000001 ||
        extraOpacity.abs() > 0.000001;
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

    // extraScale now means: finalScale - base.scale
    final effScale = (base.scale + extraScale).clamp(0.1, 5.0).toDouble();
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

    final out = <PointSample>[];
    for (final p in sLocal.points) {
      final w = _forward(Offset(p.x, p.y), t, pivotLocal);
      out.add(PointSample(w.dx, w.dy, p.t));
    }

    return sLocal.copyWith(
      points: out,
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
    final baseLayerOpacity =
        _layerTransformFn(layerId).opacity.clamp(0.0, 1.0).toDouble();
    final extraLayerOpacity = _layerExtraOpacity?.call(layerId) ?? 0.0;
    final layerOpacityMul =
        (baseLayerOpacity + extraLayerOpacity).clamp(0.0, 1.0).toDouble();

    final coreOpacityBase = _strokeExtraCoreOpacity != null
        ? _strokeExtraCoreOpacity!(layerId, strokeId)
        : outStroke.coreOpacity;

    final glowRadius = _strokeExtraGlowRadius != null
        ? _strokeExtraGlowRadius!(layerId, strokeId)
        : outStroke.glowRadius;

    final glowOpacityBase = _strokeExtraGlowOpacity != null
        ? _strokeExtraGlowOpacity!(layerId, strokeId)
        : outStroke.glowOpacity;

    final glowBrightness = _strokeExtraGlowBrightness != null
        ? _strokeExtraGlowBrightness!(layerId, strokeId)
        : outStroke.glowBrightness;

    final coreOpacity = (coreOpacityBase * layerOpacityMul).clamp(0.0, 1.0);
    final glowOpacity = (glowOpacityBase * layerOpacityMul).clamp(0.0, 1.0);

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



  // ---------------------------------------------------------------------------
  // TEXT RENDERING (V1)
  // ---------------------------------------------------------------------------

  Color _withCombinedOpacity(int argb, double opacity) {
    final base = Color(argb);
    final a = (base.alpha * opacity.clamp(0.0, 1.0)).round().clamp(0, 255);
    return base.withAlpha(a);
  }

  Offset _textPointToWorld(Offset local, LayerTransform t, Offset pivotLocal) {
    return _forward(local, t, pivotLocal);
  }

  void _drawTextObject(Canvas canvas, CanvasTextObject obj) {
    if (obj.text.trim().isEmpty) return;
    if (!_visibleLayerIds.contains(obj.layerId)) return;

    final baseLayerTr = _layerTransformFn(obj.layerId);
    final layerTr = _effectiveLayerTransform(
      baseLayerTr,
      obj.layerId,
      freezeExtras: false,
    );

    final textExtraX = _textExtraX?.call(obj.layerId, obj.id) ?? 0.0;
    final textExtraY = _textExtraY?.call(obj.layerId, obj.id) ?? 0.0;
    final textExtraScale = _textExtraScale?.call(obj.layerId, obj.id) ?? 0.0;
    final textExtraRotation =
        _textExtraRotationRad?.call(obj.layerId, obj.id) ?? 0.0;

    final effectiveTextPosition =
        obj.position + Offset(textExtraX, textExtraY);

    final pivotLocal = layerTr.pivot ?? effectiveTextPosition;
    final worldPosition =
        _textPointToWorld(effectiveTextPosition, layerTr, pivotLocal);
    final textOpacity =
        _textOpacityEffective?.call(obj.layerId, obj.id) ?? obj.opacity;
    final effectiveOpacity =
        (textOpacity * layerTr.opacity).clamp(0.0, 1.0).toDouble();
    if (effectiveOpacity <= 0.001) return;

    final blendMode = gb.glowBlendFromKey(obj.blendModeKey).toBlendMode();
    final effectiveScale =
        ((obj.scale + textExtraScale) * layerTr.scale).clamp(0.01, 20.0).toDouble();
    final effectiveRotation = obj.rotation + textExtraRotation + layerTr.rotation;

    final effectiveGlowRadius =
        (_textGlowRadiusEffective?.call(obj.layerId, obj.id) ?? obj.glowRadius)
            .clamp(0.0, 80.0)
            .toDouble();
    final effectiveGlowOpacity =
        (_textGlowOpacityEffective?.call(obj.layerId, obj.id) ?? obj.glowOpacity)
            .clamp(0.0, 1.0)
            .toDouble();
    final effectiveGlowBrightness =
        (_textGlowBrightnessEffective?.call(obj.layerId, obj.id) ??
                obj.glowBrightness)
            .clamp(0.0, 4.0)
            .toDouble();
    final effectiveFontSize =
        (_textFontSizeEffective?.call(obj.layerId, obj.id) ?? obj.fontSize)
            .clamp(4.0, 420.0)
            .toDouble();
    final effectiveEdgeGlowWidth =
        (_textEdgeGlowWidthEffective?.call(obj.layerId, obj.id) ??
                obj.edgeGlowWidth)
            .clamp(0.0, 64.0)
            .toDouble();
    final effectiveEdgeGlowStrength =
        (_textEdgeGlowStrengthEffective?.call(obj.layerId, obj.id) ??
                obj.edgeGlowStrength)
            .clamp(0.0, 3.0)
            .toDouble();

    canvas.save();
    canvas.translate(worldPosition.dx, worldPosition.dy);
    canvas.rotate(effectiveRotation);
    canvas.scale(effectiveScale, effectiveScale);

    final baseStyle = TextStyle(
      fontFamily: obj.fontFamily,
      fontSize: effectiveFontSize,
      height: obj.lineHeight,
      letterSpacing: obj.letterSpacing,
    );

    TextPainter makePainter(String text, Paint paint) {
      return TextPainter(
        text: TextSpan(
          style: baseStyle.copyWith(foreground: paint),
          text: text,
        ),
        textAlign: obj.textAlign,
        textDirection: TextDirection.ltr,
      )..layout();
    }

    TextPainter layoutPainterForBounds() {
      return TextPainter(
        text: TextSpan(
          style: baseStyle.copyWith(
            color: _withCombinedOpacity(obj.fillColor, effectiveOpacity),
          ),
          text: obj.text,
        ),
        textAlign: obj.textAlign,
        textDirection: TextDirection.ltr,
      )..layout();
    }

    void paintWhole(Paint paint) {
      final tp = makePainter(obj.text, paint);
      final offset = Offset(-tp.width / 2.0, -tp.height / 2.0);
      tp.paint(canvas, offset);
    }

    bool hasLetterOverrides = false;
    for (final o in obj.letterOverrides) {
      if (!o.isDefault && o.index >= 0 && o.index < obj.text.length) {
        hasLetterOverrides = true;
        break;
      }
    }

    final shouldPaintByLetter =
        obj.modDistribution == CanvasTextModDistribution.perCharacter ||
            hasLetterOverrides;

    void paintLetters(Paint paint, {bool glowPass = false}) {
      final letters = obj.text.characters.toList();
      if (letters.isEmpty) return;

      final painters = <TextPainter>[];
      double totalW = 0.0;
      double maxH = 0.0;
      for (final ch in letters) {
        final tp = makePainter(ch, paint);
        painters.add(tp);
        totalW += tp.width;
        if (tp.height > maxH) maxH = tp.height;
      }

      double x = -totalW / 2.0;
      for (int i = 0; i < painters.length; i++) {
        final tp = painters[i];
        final override = obj.letterOverrideAt(i);
        final letterOpacity =
            (override.opacity.clamp(0.0, 1.0) as double).toDouble();
        final glowBoost = glowPass
            ? (override.glowBoost.clamp(0.0, 4.0) as double).toDouble()
            : 1.0;
        final paintOpacityMul =
            (letterOpacity * glowBoost).clamp(0.0, 1.0).toDouble();
        if (paintOpacityMul <= 0.001) {
          x += tp.width;
          continue;
        }

        Paint letterPaint = paint;
        if (paint.color.opacity < 0.999 || paintOpacityMul < 0.999) {
          letterPaint = Paint()
            ..color = paint.color.withValues(
              alpha: (paint.color.opacity * paintOpacityMul).clamp(0.0, 1.0),
            )
            ..style = paint.style
            ..strokeWidth = paint.strokeWidth
            ..blendMode = paint.blendMode
            ..maskFilter = paint.maskFilter;
        }

        final center = Offset(x + tp.width / 2.0, 0.0);
        canvas.save();
        canvas.translate(
          center.dx + override.offsetX,
          center.dy + override.offsetY,
        );
        canvas.rotate(override.rotation);
        canvas.scale(override.scale.clamp(0.05, 8.0).toDouble());
        final letterPainter = makePainter(letters[i], letterPaint);
        letterPainter.paint(canvas, Offset(-letterPainter.width / 2.0, -maxH / 2.0));
        canvas.restore();

        x += tp.width;
      }
    }

    void paintText(Paint paint, {bool glowPass = false}) {
      if (shouldPaintByLetter) {
        paintLetters(paint, glowPass: glowPass);
      } else {
        paintWhole(paint);
      }
    }

    if (obj.glowEnabled &&
        effectiveGlowRadius > 0.0 &&
        effectiveGlowOpacity > 0.0) {
      final glow01 = (effectiveGlowRadius / 80.0).clamp(0.0, 1.0).toDouble();
      final fontGlowSize = math.max(effectiveFontSize * 0.12, 4.0);
      final intensity = gb.GlowBlendState.I.intensity.clamp(0.0, 1.0);
      final baseAlpha =
          (effectiveOpacity * effectiveGlowOpacity * intensity).clamp(0.0, 1.0);
      final bright = effectiveGlowBrightness;

      final radiusFactor = math.pow(glow01, 0.75).toDouble();
      final brightFactor = math.pow(glow01, 0.55).toDouble();

      final outerSigma = fontGlowSize * (1.0 + 9.0 * radiusFactor);
      final midSigma = fontGlowSize * (0.45 + 4.5 * radiusFactor);
      final tightSigma = fontGlowSize * (0.18 + 1.6 * radiusFactor);

      final outerAlpha = (baseAlpha * (0.34 + 0.46 * brightFactor) * bright)
          .clamp(0.0, 1.0);
      final midAlpha = (baseAlpha * (0.48 + 0.52 * brightFactor) * bright)
          .clamp(0.0, 1.0);
      final tightAlpha = (baseAlpha * (0.55 + 0.45 * brightFactor) * bright)
          .clamp(0.0, 1.0);

      paintText(Paint()
        ..color = _withCombinedOpacity(obj.glowColor, outerAlpha)
        ..blendMode = blendMode
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerSigma));

      paintText(Paint()
        ..color = _withCombinedOpacity(obj.glowColor, midAlpha)
        ..blendMode = blendMode
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, midSigma));

      paintText(Paint()
        ..color = _withCombinedOpacity(obj.glowColor, tightAlpha)
        ..blendMode = blendMode
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, tightSigma));
    }

    if (obj.edgeGlowEnabled &&
        effectiveEdgeGlowWidth > 0.0 &&
        effectiveEdgeGlowStrength > 0.0) {
      final intensity = gb.GlowBlendState.I.intensity.clamp(0.0, 1.0);
      final edgeAlpha =
          (effectiveOpacity * effectiveEdgeGlowStrength * intensity).clamp(0.0, 1.0);
      final edgeWidth = effectiveEdgeGlowWidth.clamp(0.2, 64.0).toDouble();

      paintText(Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth * 2.0
        ..color = _withCombinedOpacity(obj.glowColor, edgeAlpha * 0.8)
        ..blendMode = blendMode
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, edgeWidth * 3.0));

      paintText(Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth
        ..color = _withCombinedOpacity(obj.glowColor, edgeAlpha)
        ..blendMode = blendMode
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, edgeWidth * 0.75));
    }

    if (obj.fillEnabled) {
      paintText(Paint()
        ..color = _withCombinedOpacity(obj.fillColor, effectiveOpacity)
        ..blendMode = blendMode);
    }

    if (obj.outlineEnabled &&
        obj.outlineWidth > 0.0 &&
        obj.outlineOpacity > 0.0) {
      paintText(Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = obj.outlineWidth
        ..color = _withCombinedOpacity(
          obj.outlineColor,
          (effectiveOpacity * obj.outlineOpacity).clamp(0.0, 1.0),
        )
        ..blendMode = blendMode);
    }

    if (_selectedTextObjectIdFn() == obj.id) {
      final tp = layoutPainterForBounds();
      final rect = Rect.fromLTWH(
        -tp.width / 2.0 - 8.0,
        -tp.height / 2.0 - 8.0,
        tp.width + 16.0,
        tp.height + 16.0,
      );
      final selectionPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / effectiveScale.clamp(0.25, 8.0)
        ..color = const Color(0xFF00FFFF);
      canvas.drawRect(rect, selectionPaint);
    }

    canvas.restore();
  }

  void _drawTextObjects(Canvas canvas) {
    final objects = _textObjectsFn();
    if (objects.isEmpty) return;

    for (final obj in objects) {
      _drawTextObject(canvas, obj);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final previewScale = _previewScaleFn().clamp(0.10, 1.0).toDouble();
    final fullSize = _previewFullSizeFn();

    final sceneSize =
        (fullSize.width > 0 && fullSize.height > 0) ? fullSize : size;

    _lastSize = sceneSize;

    canvas.save();

    if ((previewScale - 1.0).abs() > 0.0001) {
      canvas.scale(previewScale, previewScale);
    }

    _paintScene(canvas, sceneSize);

    canvas.restore();
  }

  void _paintScene(Canvas canvas, Size size) {
    // Paint the actual canvas background inside the same scene as the strokes.
    // This makes blend modes behave the same at every preview resolution.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(_backgroundColorFn()),
    );

    final selectedId = _selectedStrokeIdFn();

    // Draw committed strokes
    for (final e in _entries) {
      if (!e.strokeLocal.visible) continue;

      final isSelected = (selectedId != null && e.strokeLocal.id == selectedId);

      // Keep layer extras active even when selected.
      // Only freeze stroke-level extras if needed.
      final freezeStrokeExtras = isSelected;

      // If stroke-extras enabled, never use baked pictures.
      // Also skip baked pictures whenever this layer currently has live extras
      // (rotation / x / y / scale / opacity), otherwise animation gets frozen.
      if (!_strokeExtrasEnabled) {
        final baked = _bakedByStrokeId[e.strokeLocal.id];
        final hasLiveLayerExtras = _layerHasLiveExtrasNow(e.layerId);

        if (!isSelected && !hasLiveLayerExtras && baked != null) {
          canvas.drawPicture(baked);
          continue;
        }
      }

      final baseTr = _layerTransformFn(e.layerId);

      final world = _strokeToWorldWithLayerExtras(
        e.strokeLocal,
        baseTr,
        e.layerId,
        freezeExtras: false,
      );

      final finalStroke = _applyStrokeExtrasWorld(
        world,
        e.layerId,
        e.strokeLocal.id,
        freezeExtras: freezeStrokeExtras,
      );

      _drawByBrush(canvas, finalStroke, size, _modeForStroke(finalStroke));
    }

    // Draw active in-progress stroke.
    // Important: do not return from here. Text objects are drawn after strokes,
    // so an early return makes text disappear while the user is drawing.
    final active = _activeEntry;
    if (active != null && active.strokeLocal.visible) {
      final bool activeIsWorld = active.layerId == '__WORLD__';

      // ✅ If controller is feeding WORLD points, draw as-is (no transforms/extras).
      if (activeIsWorld) {
        _drawByBrush(
          canvas,
          active.strokeLocal,
          size,
          _modeForStroke(active.strokeLocal),
        );
      } else {
        // Normal: layer-local -> world with extras
        final selectedId2 = _selectedStrokeIdFn();
        final isSelected =
            (selectedId2 != null && active.strokeLocal.id == selectedId2);
        final freezeStrokeExtras = isSelected;

        final baseTr = _layerTransformFn(active.layerId);

        final world = _strokeToWorldWithLayerExtras(
          active.strokeLocal,
          baseTr,
          active.layerId,
          freezeExtras: false,
        );

        final finalStroke = _applyStrokeExtrasWorld(
          world,
          active.layerId,
          active.strokeLocal.id,
          freezeExtras: freezeStrokeExtras,
        );

        _drawByBrush(canvas, finalStroke, size, _modeForStroke(finalStroke));
      }
    }

    // V1 text objects draw above strokes for now. Later we can interleave with
    // strokes by layer/object order once text editing is complete.
    _drawTextObjects(canvas);
  }

  /// Export path: paint the scene at full logical size with no live preview scaling.
  /// The caller is responsible for scaling the canvas to the desired output pixels.
  void paintForExport(Canvas canvas, Size size) {
    _lastSize = size;
    _paintScene(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
