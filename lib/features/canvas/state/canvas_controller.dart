import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/models/brush.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_doc.dart' as doc_model;
import '../../../core/models/canvas_layer.dart';
import '../../../core/models/stroke.dart';
import '../../../core/models/lfo.dart'; // ✅ NEW
import '../history/history_command.dart';
import '../history/history_stack.dart';
import 'package:glowbook/core/models/lfo_route.dart';

import '../render/renderer.dart';
import 'canvas_state.dart';
import 'glow_blend.dart' as gb;

enum SymmetryMode { off, mirrorV, mirrorH, quad }

final canvasControllerProvider =
    ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

class _PendingKnobEdit {
  final String key;
  final String label;
  final String? layerId;
  final VoidCallback undo;
  VoidCallback redo;

  _PendingKnobEdit({
    required this.key,
    required this.label,
    required this.layerId,
    required this.undo,
    required this.redo,
  });
}

/// Hit test result for selection (base stroke + which symmetry variant was hit).
class _StrokeHit {
  final String strokeId;
  final String layerId;
  final int groupIndex;

  /// Mirror flags for the *variant that was hit*.
  final bool mirrorX;
  final bool mirrorY;

  /// The closest point on the hit segment in hit-variant world space.
  final Offset grabWorld;

  const _StrokeHit({
    required this.strokeId,
    required this.layerId,
    required this.groupIndex,
    required this.mirrorX,
    required this.mirrorY,
    required this.grabWorld,
  });
}

class _SymVariant {
  final List<Offset> pts;
  final bool mirrorX;
  final bool mirrorY;

  const _SymVariant(this.pts, {required this.mirrorX, required this.mirrorY});
}

// -----------------------------------------------------------------------------
// Rotation animation state (constant only for now; LFO later)
// -----------------------------------------------------------------------------

class LayerRotationAnim {
  final bool constantEnabled;
  final double constantDegPerSec;

  const LayerRotationAnim({
    this.constantEnabled = false,
    this.constantDegPerSec = 0.0,
  });

  LayerRotationAnim copyWith({
    bool? constantEnabled,
    double? constantDegPerSec,
  }) {
    return LayerRotationAnim(
      constantEnabled: constantEnabled ?? this.constantEnabled,
      constantDegPerSec: constantDegPerSec ?? this.constantDegPerSec,
    );
  }

  bool get isActive => constantEnabled && constantDegPerSec.abs() > 0.000001;
}

class CanvasController extends ChangeNotifier {
  CanvasController() {
    gb.GlowBlendState.I.addListener(_handleBlendChanged);

    _ticker = Ticker(_onTick);

    // DEV VISUAL TOGGLE
    _maybeDevEnableSpin = false;

    if (_maybeDevEnableSpin) {
      _layerRotation['layer-main'] = const LayerRotationAnim(
        constantEnabled: true,
        constantDegPerSec: 25.0,
      );

      _renderer.rebuildFromLayers(_state.layers);
      _ensureTickerState();
      _tick();
    }
  }

  final ValueNotifier<int> repaint = ValueNotifier<int>(0);

  SymmetryMode symmetry = SymmetryMode.off;

  String brushId = Brush.liquidNeon.id;

  int paletteSlots = 8;

  final List<int> palette = [
    0xFF00FFFF,
    0xFFFF00FF,
    0xFFFFFF00,
    0xFFFF6EFF,
    0xFF80FF00,
    0xFFFFA500,
    0xFF00FF9A,
    0xFF9A7BFF,
    0xFFFFFFFF,
    0xFFB0B0B0,
    0xFF00BFFF,
    0xFFFF1493,
    0xFFADFF2F,
    0xFFFFD700,
    0xFF7FFFD4,
    0xFF8A2BE2,
    0xFFFF4500,
    0xFF20B2AA,
    0xFFEE82EE,
    0xFFDC143C,
    0xFF1E90FF,
    0xFF00FA9A,
    0xFF00CED1,
    0xFFDAA520,
    0xFF9932CC,
    0xFF87CEEB,
    0xFF32CD32,
    0xFFFFA07A,
    0xFF66CDAA,
    0xFFFFE4B5,
    0xFFBA55D3,
    0xFF7FFF00,
    0xFF00FFFF,
  ];

  void updatePalette(int index, int argb) {
    if (index < 0 || index >= palette.length) return;
    palette[index] = argb;
    if (color == argb) {
      setColor(argb);
    } else {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // TIME SOURCE for animation
  // ---------------------------------------------------------------------------

  late final Ticker _ticker;
  double _timeSec = 0.0;
  bool _tickerRunning = false;

  // --- LFO editor preview keeps ticker running while panel is open ---
  bool _lfoEditorPreviewActive = false;

  void setLfoEditorPreviewActive(bool active) {
    if (_lfoEditorPreviewActive == active) return;
    _lfoEditorPreviewActive = active;
    _ensureTickerState(); // start/stop ticker based on panel visibility
    notifyListeners(); // repaint UI
  }

  // --- LFO editor preview keeps ticker running while panel is open ---

  late bool _maybeDevEnableSpin;

  final Map<String, LayerRotationAnim> _layerRotation = {};

  // ---------------------------------------------------------------------------
  // LFO STATE (v1 routes -> layer extra rotation only)
  // ---------------------------------------------------------------------------

  final List<Lfo> _lfos = <Lfo>[];
  final List<LfoRoute> _routes = <LfoRoute>[];

  List<Lfo> get lfos => List.unmodifiable(_lfos);
  List<LfoRoute> get lfoRoutes => List.unmodifiable(_routes);

  List<LfoRoute> routesForLfo(String lfoId) =>
      _routes.where((r) => r.lfoId == lfoId).toList();

  void _onTick(Duration elapsed) {
    _timeSec = elapsed.inMicroseconds / 1000000.0;

    _tick(); // your existing repaint notifier

    // If the LFO editor is open, force widget rebuilds so the playhead/curve animates
    if (_lfoEditorPreviewActive) {
      notifyListeners();
    }
  }

  void _ensureTickerState() {
    final anyConstant = _layerRotation.values.any((a) => a.isActive);

    bool anyLfoActive = false;
    if (_routes.isNotEmpty && _lfos.isNotEmpty) {
      for (final r in _routes) {
        if (!r.enabled) continue;
        final li = _lfos.indexWhere((l) => l.id == r.lfoId);
        if (li < 0) continue;
        if (!_lfos[li].enabled) continue;
        anyLfoActive = true;
        break;
      }
    }

    // ✅ keep ticker alive if panel is open
    final anyActive = anyConstant || anyLfoActive || _lfoEditorPreviewActive;

    if (anyActive && !_tickerRunning) {
      _ticker.start();
      _tickerRunning = true;
    } else if (!anyActive && _tickerRunning) {
      _ticker.stop();
      _tickerRunning = false;
      _timeSec = 0.0;
      _tick();
    }
  }

  int _lfoIndexById(String id) => _lfos.indexWhere((x) => x.id == id);

  void _replaceLfoAt(int index, Lfo next) {
    if (index < 0 || index >= _lfos.length) return;

    _lfos[index] = next;

    _ensureTickerState();
    _tick();
    notifyListeners();
  }

  String _newLfoId() => 'lfo-${DateTime.now().microsecondsSinceEpoch}';
  String _newRouteId() => 'route-${DateTime.now().microsecondsSinceEpoch}';

  double lfoPlayhead01(String lfoId) {
    final i = _lfos.indexWhere((l) => l.id == lfoId);
    if (i < 0) return 0.0;

    final lfo = _lfos[i];

    // Match lfo.eval(_timeSec): rate + phase
    final t = (_timeSec * lfo.rateHz) + lfo.phase;

    // 0..1 loop
    return t - t.floorToDouble();
  }

  // ---------------------------------------------------------------------------
  // PIVOT / TRANSFORM POLICY (REFACTOR CORE)
  // ---------------------------------------------------------------------------

  bool _isIdentityTransform(LayerTransform t) {
    return t.position == Offset.zero &&
        t.scale == 1.0 &&
        t.rotation == 0.0 &&
        t.opacity == 1.0;
  }

  bool _layerIsAnimatedNow(String layerId) {
    final anim = _layerRotation[layerId];
    final constantRotates = anim != null && anim.isActive;

    final lfoRotates = _routes.any((r) =>
        r.enabled &&
        r.layerId == layerId &&
        r.strokeId == null &&
        r.param == LfoParam.layerRotationDeg);

    final lfoMoves = _routes.any((r) =>
        r.enabled &&
        r.layerId == layerId &&
        r.strokeId == null &&
        (r.param == LfoParam.layerX ||
            r.param == LfoParam.layerY ||
            r.param == LfoParam.layerScale ||
            r.param == LfoParam.layerOpacity));

    return constantRotates || lfoRotates || lfoMoves;
  }

  bool _layerHasActiveLfoRotation(String layerId) {
    return _routes.any((r) =>
        r.enabled &&
        r.layerId == layerId &&
        !r.isStrokeTarget &&
        r.param == LfoParam.layerRotationDeg &&
        _lfos.any((l) => l.id == r.lfoId && l.enabled));
  }

  bool _layerHasActiveConstantRotation(String layerId) {
    final a = _layerRotation[layerId];
    return a != null && a.isActive;
  }

  /// "Needs pivot" means: even if base transform is identity, the *effective*
  /// transform isn't, because LFO/constant rotation applies in the renderer.
  bool _layerNeedsPivotNow(CanvasLayer layer) {
    final tr = layer.transform;

    final baseRot = tr.rotation.abs() > 0.000001;
    final baseScale = (tr.scale - 1.0).abs() > 0.000001;

    final constantRot = _layerHasActiveConstantRotation(layer.id);
    final lfoRot = _layerHasActiveLfoRotation(layer.id);

    return baseRot || baseScale || constantRot || lfoRot;
  }

  Offset _computeBoundsPivotForLayer(CanvasLayer layer) {
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
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return Offset.zero;
    }
    return Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
  }

  void _ensureLayerPivotForRotation(String layerId) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final layer = _state.layers[idx];
    final tr = layer.transform;

    final bool baseRotates = tr.rotation.abs() > 0.000001;

    final anim = _layerRotation[layerId];
    final bool constantRotates = anim != null && anim.isActive;

    final bool lfoRotates = _routes.any((r) =>
        r.enabled &&
        r.layerId == layerId &&
        r.strokeId == null &&
        r.param == LfoParam.layerRotationDeg);

    if (!baseRotates && !constantRotates && !lfoRotates) return;

    // ✅ Only set pivot if missing. DO NOT auto-refresh (prevents pivot jumping).
    if (tr.pivot != null) return;

    // ✅ Guard: if there's literally no geometry yet, don't set 0,0 and accidentally lock it forever
    final desired = _computeBoundsPivotForLayer(layer);
    if (desired == Offset.zero) {
      // If there are no points, bail. We'll set pivot once strokes exist.
      // (This prevents "pivot locked to 0,0" for empty layers.)
      return;
    }

    final layers = List<CanvasLayer>.from(_state.layers);
    layers[idx] = layer.copyWith(transform: tr.copyWith(pivot: desired));
    _state = _state.copyWith(layers: layers);
  }

  bool _ensureAllRotatingLayerPivotsAndRebuildIfChanged() {
    bool changed = false;

    for (final l in _state.layers) {
      final idx = _state.layers.indexWhere((x) => x.id == l.id);
      if (idx < 0) continue;

      final before = _state.layers[idx].transform.pivot;

      _ensureLayerPivotForRotation(l.id);

      final after = _state.layers[idx].transform.pivot;

      if (before != after) changed = true;
    }

    if (changed) {
      _renderer.rebuildFromLayers(_state.layers);
    }

    return changed;
  }

  /// Single source of truth:
  /// - If the layer will rotate/scale (base OR constant OR LFO), ensure pivot exists.
  /// - Keep it centered on the combined stroke bounds (refresh if strokes changed).
  void _ensureLayerPivot(String layerId) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final layer = _state.layers[idx];
    if (!_layerNeedsPivotNow(layer)) return;

    final tr = layer.transform;
    if (tr.pivot != null) return; // ✅ never auto-refresh

    final desired = _computeBoundsPivotForLayer(layer);
    if (desired == Offset.zero) return; // no geometry yet

    final layers = List<CanvasLayer>.from(_state.layers);
    layers[idx] = layer.copyWith(transform: tr.copyWith(pivot: desired));
    _state = _state.copyWith(layers: layers);
  }

  /// When we need to convert points between world/local, we must use a pivot that matches
  /// the *effective* transform (even if base transform is identity but LFO rotates).
  Offset _layerPivotForMath(CanvasLayer layer) {
    if (!_layerNeedsPivotNow(layer)) return Offset.zero;

    // Ensure pivot exists (but don't keep refreshing mid-gesture)
    _ensureLayerPivot(layer.id);

    final updated =
        _state.layers.firstWhere((l) => l.id == layer.id, orElse: () => layer);

    return updated.transform.pivot ?? _computeBoundsPivotForLayer(updated);
  }

  Offset _forwardTransformPoint(Offset p, LayerTransform t, Offset pivot) {
    final angle = t.rotation;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final local = p - pivot;

    final rotated = Offset(
      local.dx * cosA - local.dy * sinA,
      local.dx * sinA + local.dy * cosA,
    );

    final scaled = rotated * t.scale;

    return scaled + pivot + t.position;
  }

  Offset _inverseTransformPoint(Offset pWorld, LayerTransform t, Offset pivot) {
    final p = pWorld - t.position;
    final local = p - pivot;

    final s = (t.scale == 0.0) ? 1.0 : t.scale;
    final unscaled = Offset(local.dx / s, local.dy / s);

    final angle = -t.rotation;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final unrotated = Offset(
      unscaled.dx * cosA - unscaled.dy * sinA,
      unscaled.dx * sinA + unscaled.dy * cosA,
    );

    return unrotated + pivot;
  }

  double _defaultAmountForParam(LfoParam p) {
    switch (p) {
      // --- LAYER ---
      case LfoParam.layerRotationDeg:
        return 25.0;
      case LfoParam.layerX:
      case LfoParam.layerY:
        return 150.0;
      case LfoParam.layerScale:
        return 0.35; // used as extraScale where eff = base * (1 + extraScale)
      case LfoParam.layerOpacity:
        return 0.5; // additive delta on 0..1

      // --- STROKE TRANSFORM ---
      case LfoParam.strokeX:
      case LfoParam.strokeY:
        return 120.0;
      case LfoParam.strokeRotationDeg:
        return 45.0;

      // --- STROKE VISUAL (0..1 ranges) ---
      case LfoParam.strokeCoreOpacity:
        return 0.5;
      case LfoParam.strokeGlowRadius:
        return 0.5;
      case LfoParam.strokeGlowOpacity:
        return 1.0;
      case LfoParam.strokeGlowBrightness:
        return 1.0;

      // --- STROKE SIZE (pixels-ish) ---
      case LfoParam.strokeSize:
        return 25.0;

      default:
        return 25.0;
    }
  }

  // ---------------------------------------------------------------------------
  // LFO ROUTE EVAL HELPERS
  // ---------------------------------------------------------------------------

  double _evalRouteShaped(LfoRoute r, LfoParam param) {
    final i = _lfos.indexWhere((x) => x.id == r.lfoId);
    if (i < 0) return 0.0;
    final lfo = _lfos[i];
    if (!lfo.enabled) return 0.0;

    final raw = lfo.eval(_timeSec); // [-1..1]

    // ✅ Visual params should be unipolar by default: 0..1
    final bool forceUnipolar = (param == LfoParam.layerOpacity ||
        param == LfoParam.strokeCoreOpacity ||
        param == LfoParam.strokeGlowRadius ||
        param == LfoParam.strokeGlowOpacity ||
        param == LfoParam.strokeGlowBrightness);

    if (forceUnipolar) {
      return ((raw + 1.0) * 0.5); // [0..1]
    }

    // Existing behavior for transform params (X/Y/rot/scale etc.)
    return r.bipolar ? raw : ((raw + 1.0) * 0.5);
  }

  double _sumRoutes({
    required String layerId,
    String? strokeId,
    required LfoParam param,
  }) {
    if (_lfos.isEmpty || _routes.isEmpty) return 0.0;

    double total = 0.0;
    for (final r in _routes) {
      if (!r.enabled) continue;
      if (r.layerId != layerId) continue;
      if (r.param != param) continue;

      // stroke match rules:
      if (strokeId == null) {
        if (r.strokeId != null) continue; // layer param: ignore stroke routes
      } else {
        if (r.strokeId != strokeId) continue; // stroke param: must match
      }

      final shaped = _evalRouteShaped(r, param);
      total += (r.amount * shaped);
    }
    return total;
  }

  double _layerExtraRotationRadians(String layerId) {
    double degTotal = 0.0;

    // A) constant rotation (deg)
    final anim = _layerRotation[layerId];
    if (anim != null && anim.isActive) {
      degTotal += (anim.constantDegPerSec * _timeSec) % 360.0;
    }

    // B) LFO routes (deg)
    degTotal += _sumRoutes(layerId: layerId, param: LfoParam.layerRotationDeg);

    return degTotal * math.pi / 180.0;
  }

  double _layerExtraX(String layerId) {
    return _sumRoutes(layerId: layerId, param: LfoParam.layerX);
  }

  double _layerExtraY(String layerId) {
    return -_sumRoutes(layerId: layerId, param: LfoParam.layerY); // ✅ flip Y
  }

  double _layerExtraScale(String layerId) {
    return _sumRoutes(layerId: layerId, param: LfoParam.layerScale);
  }

  LayerTransform _effectiveLayerTransformForInput(
    String layerId,
    LayerTransform base,
  ) {
    final dx = _layerExtraX(layerId);
    final dy = _layerExtraY(layerId);
    final extraRot = _layerExtraRotationRadians(layerId);
    final extraScale = _layerExtraScale(layerId);

    final scaleMul = (1.0 + extraScale).clamp(0.01, 100.0).toDouble();
    final effScale = (base.scale * scaleMul).clamp(0.01, 100.0).toDouble();

    return base.copyWith(
      position: base.position + Offset(dx, dy),
      rotation: base.rotation + extraRot,
      scale: effScale,
    );
  }

  double _applyVitalMod({
    required double base,
    required double min,
    required double max,
    required double lfo01, // 0..1
    required double depth, // -1..1
  }) {
    base = base.clamp(min, max).toDouble();
    lfo01 = lfo01.clamp(0.0, 1.0).toDouble();
    depth = depth.clamp(-1.0, 1.0).toDouble();

    if (depth == 0.0) return base;

    if (depth > 0.0) {
      final headroom = max - base;
      return (base + headroom * depth * lfo01).clamp(min, max).toDouble();
    } else {
      final headroom = base - min;
      return (base + headroom * depth * lfo01).clamp(min, max).toDouble();
    }
  }

  // NOTE: this returns an ADDITIVE delta; renderer will clamp final opacity.
  double _layerExtraOpacity(String layerId) {
    return _sumRoutes(layerId: layerId, param: LfoParam.layerOpacity);
  }

  double _strokeExtraX(String layerId, String strokeId) =>
      _sumRoutes(layerId: layerId, strokeId: strokeId, param: LfoParam.strokeX);

  double _strokeExtraY(String layerId, String strokeId) => -_sumRoutes(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeY); // ✅ flip Y

  double _strokeExtraRotationRad(String layerId, String strokeId) {
    final deg = _sumRoutes(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeRotationDeg,
    );
    return deg * math.pi / 180.0;
  }

// ─────────────────────────────────────────────────────────────
// Stroke SIZE (unbounded, delta-based → keep old behavior)
// ─────────────────────────────────────────────────────────────
  double strokeExtraSize(String layerId, String strokeId) {
    return _sumRoutes(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeSize,
    );
  }

// ─────────────────────────────────────────────────────────────
// Stroke VISUAL PARAMS (0..1, Vital-style FINAL values)
// ─────────────────────────────────────────────────────────────

  double strokeCoreOpacityEffective(String layerId, String strokeId) {
    final base =
        _findStrokeBaseValue(layerId, strokeId, (s) => s.coreOpacity, 1.0);
    return _applyVitalStrokeParam(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeCoreOpacity,
      base: base,
    );
  }

  double strokeGlowRadiusEffective(String layerId, String strokeId) {
    final base =
        _findStrokeBaseValue(layerId, strokeId, (s) => s.glowRadius, 0.5);
    return _applyVitalStrokeParam(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeGlowRadius,
      base: base,
    );
  }

  double strokeGlowOpacityEffective(String layerId, String strokeId) {
    final base =
        _findStrokeBaseValue(layerId, strokeId, (s) => s.glowOpacity, 1.0);
    return _applyVitalStrokeParam(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeGlowOpacity,
      base: base,
    );
  }

  double strokeGlowBrightnessEffective(String layerId, String strokeId) {
    final base =
        _findStrokeBaseValue(layerId, strokeId, (s) => s.glowBrightness, 1.0);
    return _applyVitalStrokeParam(
      layerId: layerId,
      strokeId: strokeId,
      param: LfoParam.strokeGlowBrightness,
      base: base,
    );
  }

  double _applyVitalStrokeParam({
    required String layerId,
    required String strokeId,
    required LfoParam param,
    required double base,
  }) {
    double out = base;

    for (final r in _routes) {
      if (!r.enabled) continue;
      if (r.layerId != layerId) continue;
      if (r.strokeId != strokeId) continue;
      if (r.param != param) continue;

      final i = _lfos.indexWhere((l) => l.id == r.lfoId);
      if (i < 0) continue;

      final lfo = _lfos[i];
      if (!lfo.enabled) continue;

      final raw = lfo.eval(_timeSec); // [-1..1]
      final lfo01 = (raw + 1.0) * 0.5; // [0..1]
      final depth = r.amount.clamp(-1.0, 1.0);

      out = _applyVitalMod(
        base: base,
        min: 0.0,
        max: 1.0,
        lfo01: lfo01,
        depth: depth,
      );
    }

    return out;
  }

  String? _selectedStrokeIdFn() => _selectedStrokeId;

  late final Renderer _renderer = Renderer(
    repaint,
    () => symmetry,

    // ✅ always use latest layer transform (fixes stale pivot issue)
    layerTransformFn: (layerId) {
      final i = _state.layers.indexWhere((l) => l.id == layerId);
      if (i < 0) return const LayerTransform();
      return _state.layers[i].transform;
    },

    layerExtraRotationRadians: _layerExtraRotationRadians,
    layerExtraX: _layerExtraX,
    layerExtraY: _layerExtraY,
    layerExtraScale: _layerExtraScale,
    layerExtraOpacity: _layerExtraOpacity,

    strokeExtraX: _strokeExtraX,
    strokeExtraY: _strokeExtraY,
    strokeExtraRotationRad: _strokeExtraRotationRad,

    // size stays delta-based
    strokeExtraSize: strokeExtraSize,

    // ✅ visuals now pass FINAL effective values (0..1), no "base" param
    strokeExtraCoreOpacity: (layerId, strokeId) =>
        strokeCoreOpacityEffective(layerId, strokeId),

    strokeExtraGlowRadius: (layerId, strokeId) =>
        strokeGlowRadiusEffective(layerId, strokeId),

    strokeExtraGlowOpacity: (layerId, strokeId) =>
        strokeGlowOpacityEffective(layerId, strokeId),

    strokeExtraGlowBrightness: (layerId, strokeId) =>
        strokeGlowBrightnessEffective(layerId, strokeId),

    selectedStrokeIdFn: _selectedStrokeIdFn,
  );

  List<Stroke> get strokes => List.unmodifiable(_state.allStrokes);

  List<CanvasLayer> get layers => List.unmodifiable(_state.layers);
  String get activeLayerId => _state.activeLayerId;
  CanvasLayer get activeLayer => _state.activeLayer;

  int color = 0xFF00FFFF;
  double brushSize = 10.0;

  int backgroundColor = 0xFF000000;
  bool _hasCustomBackground = false;
  bool get hasCustomBackground => _hasCustomBackground;

  double coreOpacity = 0.86;

  double _brushGlow = 0.3;
  double get brushGlow => _brushGlow;

  double glowRadius = 0.3;
  double glowOpacity = 1.0;
  double glowBrightness = 0.3;

  bool glowRadiusScalesWithSize = false;

  bool _advancedGlowEnabled = false;
  bool get advancedGlowEnabled => _advancedGlowEnabled;

  double _savedAdvancedGlowRadius = 15.0 / 300.0;
  double _savedAdvancedGlowBrightness = 50.0 / 100.0;
  double _savedAdvancedGlowOpacity = 1.0;

  double _savedSimpleGlow = 0.3;

  CanvasState _state = CanvasState.initial();

  Stroke? _current;
  int _startMs = 0;
  int? _activePointerId;

  bool _drawingInWorld = false;
  String? _drawingLayerId;
  LayerTransform? _drawingBaseLayerTr;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Renderer get painter => _renderer;

  bool _suppressBlendDirty = false;

  final HistoryStack _history = HistoryStack();

  double _findStrokeBaseValue(
    String layerId,
    String strokeId,
    double Function(Stroke s) pick,
    double fallback,
  ) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return fallback;

    final layer = _state.layers[li];
    for (final g in layer.groups) {
      final si = g.strokes.indexWhere((s) => s.id == strokeId);
      if (si >= 0) return pick(g.strokes[si]);
    }
    return fallback;
  }

  // ---------------------------------------------------------------------------
  // CANVAS SIZE (needed for symmetry selection hit test)
  // ---------------------------------------------------------------------------

  Size _canvasSize = Size.zero;

  void setCanvasSize(Size s) {
    if (_canvasSize == s) return;
    _canvasSize = s;
  }

  // ---------------------------------------------------------------------------
// NO-HISTORY HELPERS (state only; _doCommand/_afterEdit handles rebuild+repaint)
// ---------------------------------------------------------------------------

  void _deleteStrokeNoHistory(String layerId, int groupIndex, String strokeId) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    strokes.removeAt(si);

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    // clear selection if we deleted the selected stroke
    if (_selectedStrokeId == strokeId) {
      clearSelection();
    }
  }

  void _insertStrokeNoHistory(
    String layerId,
    int groupIndex,
    int insertIndex,
    Stroke stroke,
  ) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);

    final idx = insertIndex.clamp(0, strokes.length);
    strokes.insert(idx, stroke);

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);
  }

  void _reorderStrokesNoHistory(
    String layerId,
    int groupIndex,
    List<String> orderedStrokeIds,
  ) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    if (orderedStrokeIds.length != group.strokes.length) return;

    final map = <String, Stroke>{for (final s in group.strokes) s.id: s};

    final newStrokes = <Stroke>[];
    for (final id in orderedStrokeIds) {
      final s = map[id];
      if (s == null) return; // invalid list
      newStrokes.add(s);
    }

    groups[groupIndex] = group.copyWith(strokes: newStrokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);
  }

  void _reorderLayersNoHistory(List<String> orderedIds) {
    if (orderedIds.length != _state.layers.length) return;

    final map = {for (final l in _state.layers) l.id: l};

    final newLayers = <CanvasLayer>[];
    for (final id in orderedIds) {
      final layer = map[id];
      if (layer == null) return;
      newLayers.add(layer);
    }

    _state = _state.copyWith(layers: newLayers);
  }

  void _removeLayerNoHistory(String layerId) {
    if (_state.layers.length <= 1) return;

    final newLayers = List<CanvasLayer>.from(_state.layers)
      ..removeWhere((l) => l.id == layerId);
    if (newLayers.isEmpty) return;

    String newActiveId = _state.activeLayerId;
    if (!newLayers.any((l) => l.id == newActiveId)) {
      newActiveId = newLayers.last.id;
    }

    _state = _state.copyWith(
      layers: newLayers,
      activeLayerId: newActiveId,
      redoStack: const [],
    );

    // if we removed the selected layer, clear selection
    if (_selectedLayerId == layerId) {
      clearSelection();
    }
  }

  void _insertLayerNoHistory(int insertIndex, CanvasLayer layerToInsert) {
    final layers = List<CanvasLayer>.from(_state.layers);
    final idx = insertIndex.clamp(0, layers.length);
    layers.insert(idx, layerToInsert);

    _state = _state.copyWith(
      layers: layers,
      // keep current active unless it no longer exists
      activeLayerId: _state.activeLayerId,
      redoStack: const [],
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTION MODE
  // ---------------------------------------------------------------------------

  bool selectionMode = false;

  String? _selectedStrokeId;
  String? _selectedLayerId;
  int? _selectedGroupIndex;

  bool _selectedMirrorX = false;
  bool _selectedMirrorY = false;

  Offset? _selectionAnchorWorld;

  bool _isDraggingSelection = false;
  Offset? _selectionDragLastWorld;

  bool _isSelectionGesturing = false;
  bool get isSelectionGesturing => _isSelectionGesturing;

  List<PointSample>? _gestureStartLocalPoints;
  Offset? _gestureStartPivotLocal;

  double _gestureLastScale = 1.0;
  double _gestureLastRotation = 0.0;

  bool get hasSelection => _selectedStrokeId != null;

  // ✅ Expose selection info for UI highlighting (Layer panel)
  String? get selectedStrokeId => _selectedStrokeId;
  String? get selectedLayerId => _selectedLayerId;
  int? get selectedGroupIndex => _selectedGroupIndex;

  void setSelectionMode(bool value) {
    if (selectionMode == value) return;
    selectionMode = value;

    if (!selectionMode) {
      clearSelection();
    } else {
      notifyListeners();
    }
  }

  void clearSelection() {
    _selectedStrokeId = null;
    _selectedLayerId = null;
    _selectedGroupIndex = null;

    _selectedMirrorX = false;
    _selectedMirrorY = false;
    _selectionAnchorWorld = null;

    _isDraggingSelection = false;
    _selectionDragLastWorld = null;

    _isSelectionGesturing = false;
    _gestureStartLocalPoints = null;
    _gestureStartPivotLocal = null;
    _gestureLastScale = 1.0;
    _gestureLastRotation = 0.0;

    notifyListeners();
  }

  void cancelActivePointer() {
    final pid = _activePointerId;
    if (pid != null) cancelPointer(pid);
  }

  /// Select a stroke from UI (Layer panel) without hit-testing.
  void selectStrokeRef(String layerId, int groupIndex, String strokeId) {
    if (!selectionMode) selectionMode = true;

    _selectedLayerId = layerId;
    _selectedGroupIndex = groupIndex;
    _selectedStrokeId = strokeId;

    _selectedMirrorX = false;
    _selectedMirrorY = false;

    _selectionAnchorWorld = null;

    notifyListeners();
  }

  /// Change stroke thickness (size) from UI. (LIVE ONLY; history commits on pointer up)
  void setStrokeSizeRef(
    String layerId,
    int groupIndex,
    String strokeId,
    double newSize,
  ) {
    final after = newSize.clamp(0.5, 200.0).toDouble();
    _applyStrokeSizeNoHistory(layerId, groupIndex, strokeId, after);
  }

  void setStrokeCoreOpacityRef(
      String layerId, int groupIndex, String strokeId, double v) {
    final clamped = v.clamp(0.0, 1.0).toDouble();
    final key = 'strokeKnob:core:$layerId:$groupIndex:$strokeId';

    _applyStrokePatchNoHistory(
      layerId,
      groupIndex,
      strokeId,
      knobKey: key,
      patch: (s) => s.copyWith(coreOpacity: clamped),
      redoLatest: () =>
          setStrokeCoreOpacityRef(layerId, groupIndex, strokeId, clamped),
    );
  }

  void setStrokeGlowRadiusRef(
      String layerId, int groupIndex, String strokeId, double v) {
    final clamped = v.clamp(0.0, 1.0).toDouble();
    final key = 'strokeKnob:radius:$layerId:$groupIndex:$strokeId';

    _applyStrokePatchNoHistory(
      layerId,
      groupIndex,
      strokeId,
      knobKey: key,
      patch: (s) => s.copyWith(glowRadius: clamped),
      redoLatest: () =>
          setStrokeGlowRadiusRef(layerId, groupIndex, strokeId, clamped),
    );
  }

  void setStrokeGlowOpacityRef(
      String layerId, int groupIndex, String strokeId, double v) {
    final clamped = v.clamp(0.0, 1.0).toDouble();
    final key = 'strokeKnob:glowOp:$layerId:$groupIndex:$strokeId';

    _applyStrokePatchNoHistory(
      layerId,
      groupIndex,
      strokeId,
      knobKey: key,
      patch: (s) => s.copyWith(glowOpacity: clamped),
      redoLatest: () =>
          setStrokeGlowOpacityRef(layerId, groupIndex, strokeId, clamped),
    );
  }

  void setStrokeGlowBrightnessRef(
      String layerId, int groupIndex, String strokeId, double v) {
    final clamped = v.clamp(0.0, 1.0).toDouble();
    final key = 'strokeKnob:bright:$layerId:$groupIndex:$strokeId';

    _applyStrokePatchNoHistory(
      layerId,
      groupIndex,
      strokeId,
      knobKey: key,
      patch: (s) => s.copyWith(glowBrightness: clamped),
      redoLatest: () =>
          setStrokeGlowBrightnessRef(layerId, groupIndex, strokeId, clamped),
    );
  }

  void _applyStrokeSizeNoHistory(
    String layerId,
    int groupIndex,
    String strokeId,
    double newSize,
  ) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final clamped = newSize.clamp(0.5, 200.0).toDouble();
    if ((strokes[si].size - clamped).abs() < 0.000001) return;

    strokes[si] = strokes[si].copyWith(size: clamped);
    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);
    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    // If a stroke-size knob edit is active for this stroke, keep updating redoLatest
    final key = 'strokeSize:$layerId:$groupIndex:$strokeId';
    if (_pendingKnob != null && _pendingKnob!.key == key) {
      final latest = clamped;
      knobEditUpdate(
        key: key,
        redoLatest: () =>
            _applyStrokeSizeNoHistory(layerId, groupIndex, strokeId, latest),
      );
    }

    notifyListeners();
  }

  void _applyStrokePatchNoHistory(
    String layerId,
    int groupIndex,
    String strokeId, {
    required String knobKey,
    required Stroke Function(Stroke s) patch,
    required VoidCallback redoLatest,
  }) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final before = strokes[si];
    final after = patch(before);

    // cheap equality guard: if nothing changed, bail
    if (identical(before, after) || before == after) return;

    strokes[si] = after;

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);
    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();

    // Keep updating redoLatest during drag (matches your size pattern)
    if (_pendingKnob != null && _pendingKnob!.key == knobKey) {
      knobEditUpdate(
        key: knobKey,
        redoLatest: redoLatest,
      );
    }

    notifyListeners();
  }

  void _applyStrokePointsNoHistory(
    String layerId,
    int groupIndex,
    String strokeId,
    List<PointSample> newPoints, {
    required String knobKey,
  }) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    // Optional tiny guard to avoid pointless churn
    if (strokes[si].points.length == newPoints.length) {
      bool same = true;
      for (int i = 0; i < newPoints.length; i++) {
        final a = strokes[si].points[i];
        final b = newPoints[i];
        if ((a.x - b.x).abs() > 0.000001 ||
            (a.y - b.y).abs() > 0.000001 ||
            (a.t - b.t).abs() > 0.000001) {
          same = false;
          break;
        }
      }
      if (same) return;
    }

    strokes[si] =
        strokes[si].copyWith(points: List<PointSample>.from(newPoints));

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);
    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();

    // keep redoLatest updated during drag
    if (_pendingKnob != null && _pendingKnob!.key == knobKey) {
      final latest = List<PointSample>.from(newPoints);
      knobEditUpdate(
        key: knobKey,
        redoLatest: () => _applyStrokePointsNoHistory(
          layerId,
          groupIndex,
          strokeId,
          latest,
          knobKey: knobKey,
        ),
      );
    }

    notifyListeners();
  }

  /// Call this from knob pointer-down / onChangeStart.
  void beginStrokeSizeKnob(
    String layerId,
    int groupIndex,
    String strokeId,
  ) {
    // locate stroke and capture BEFORE
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layer = _state.layers[li];
    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final group = layer.groups[groupIndex];
    final si = group.strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final before = group.strokes[si].size;

    final key = 'strokeSize:$layerId:$groupIndex:$strokeId';

    knobEditBegin(
      key: key,
      label: 'Stroke Size',
      layerId: layerId,
      undo: () =>
          _applyStrokeSizeNoHistory(layerId, groupIndex, strokeId, before),
      // redo closure will be updated while dragging via knobEditUpdate()
      redoLatest: () {},
    );
  }

  /// Call this from knob pointer-up / onChangeEnd.
  void endStrokeSizeKnob(
    String layerId,
    int groupIndex,
    String strokeId,
  ) {
    final key = 'strokeSize:$layerId:$groupIndex:$strokeId';
    final p = _pendingKnob;
    if (p == null) return;
    if (p.key != key) return;
    knobEditEnd();
  }

  // ---------------------------------------------------------------------------
// LAYER KNOB UNDO/REDO (X/Y/Scale/Rot/Opacity)
// ---------------------------------------------------------------------------

  void beginLayerKnob(String layerId, {required String label}) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final before = _state.layers[idx].transform;
    final key = 'layerKnob:$layerId';

    knobEditBegin(
      key: key,
      label: label,
      layerId: layerId,
      undo: () {
        _applyLayerTransformNoHistory(layerId, before, knobKey: key);
      },
      redoLatest: () {},
    );
  }

  void endLayerKnob(String layerId) {
    final key = 'layerKnob:$layerId';
    final p = _pendingKnob;
    if (p == null) return;
    if (p.key != key) return;
    knobEditEnd();
  }

  /// Apply transform live WITHOUT pushing history.
  /// Also keeps redo closure updated during drag.
  void _applyLayerTransformNoHistory(
    String layerId,
    LayerTransform newTr, {
    required String knobKey,
  }) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];

    layers[idx] = layer.copyWith(transform: newTr);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);
    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();

    // update redoLatest while dragging
    if (_pendingKnob != null && _pendingKnob!.key == knobKey) {
      final latest = newTr;
      knobEditUpdate(
        key: knobKey,
        redoLatest: () => _applyLayerTransformNoHistory(
          layerId,
          latest,
          knobKey: knobKey,
        ),
      );
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
// LAYER KNOB LIVE SETTERS (NO HISTORY; history commits on endLayerKnob)
// ---------------------------------------------------------------------------

  void setLayerXRef(String layerId, double x) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final layer = _state.layers[idx];
    final pos = layer.transform.position;
    final tr = layer.transform.copyWith(position: Offset(x, pos.dy));

    _applyLayerTransformNoHistory(layerId, tr, knobKey: 'layerKnob:$layerId');
  }

  void setLayerYRef(String layerId, double y) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final layer = _state.layers[idx];
    final pos = layer.transform.position;
    final tr = layer.transform.copyWith(position: Offset(pos.dx, -y)); // ✅ flip

    _applyLayerTransformNoHistory(layerId, tr, knobKey: 'layerKnob:$layerId');
  }

  void setLayerScaleRef(String layerId, double scale) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final v = scale.clamp(0.1, 5.0).toDouble();
    final layer = _state.layers[idx];
    final tr = layer.transform.copyWith(scale: v);

    _applyLayerTransformNoHistory(layerId, tr, knobKey: 'layerKnob:$layerId');
  }

  void setLayerOpacityRef(String layerId, double opacity) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final v = opacity.clamp(0.0, 1.0).toDouble();
    final layer = _state.layers[idx];
    final tr = layer.transform.copyWith(opacity: v);

    _applyLayerTransformNoHistory(layerId, tr, knobKey: 'layerKnob:$layerId');
  }

  void setLayerRotationDegRef(String layerId, double deg) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final radians = deg * math.pi / 180.0;
    final layer = _state.layers[idx];
    final tr = layer.transform.copyWith(rotation: radians);

    _applyLayerTransformNoHistory(layerId, tr, knobKey: 'layerKnob:$layerId');
  }

// ---------------------------------------------------------------------------
// STROKE KNOB UNDO/REDO (param-specific key)
// ---------------------------------------------------------------------------

  void beginStrokeParamKnob(
    String layerId,
    int groupIndex,
    String strokeId, {
    required String label,
    required String
        paramKey, // e.g. "core", "radius", "glowOp", "bright", "x", "y", "rot"
  }) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layer = _state.layers[li];
    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final group = layer.groups[groupIndex];
    final si = group.strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final beforeStroke = group.strokes[si];
    final key = 'strokeKnob:$paramKey:$layerId:$groupIndex:$strokeId';

    knobEditBegin(
      key: key,
      label: label,
      layerId: layerId,
      undo: () {
        _applyStrokePatchNoHistory(
          layerId,
          groupIndex,
          strokeId,
          knobKey: key,
          patch: (_) => beforeStroke,
          redoLatest: () {},
        );
      },
      redoLatest: () {},
    );
  }

  /// Live preview update for stroke transform knobs (X/Y/Rot).
  /// IMPORTANT: does NOT push history.
  void setStrokePointsPreviewRef(
    String layerId,
    int groupIndex,
    String strokeId,
    List<PointSample> points,
  ) {
    final key = 'strokeXform:$layerId:$groupIndex:$strokeId';
    _applyStrokePointsNoHistory(
      layerId,
      groupIndex,
      strokeId,
      points,
      knobKey: key,
    );
  }

  /// Call this on knob onChangeStart.
  /// You pass in the stroke's BASELINE points (the "before" snapshot).
  void beginStrokeTransformKnob(
    String layerId,
    int groupIndex,
    String strokeId, {
    required String label,
    required List<PointSample> beforePoints,
  }) {
    final key = 'strokeXform:$layerId:$groupIndex:$strokeId';

    knobEditBegin(
      key: key,
      label: label,
      layerId: layerId,
      undo: () {
        _applyStrokePointsNoHistory(
          layerId,
          groupIndex,
          strokeId,
          beforePoints,
          knobKey: key,
        );
      },
      redoLatest:
          () {}, // updated while dragging by _applyStrokePointsNoHistory
    );
  }

  /// Call this on knob onChangeEnd.
  /// You pass in the final computed "after" points.
  void endStrokeTransformKnob(
    String layerId,
    int groupIndex,
    String strokeId, {
    required List<PointSample> afterPoints,
  }) {
    final key = 'strokeXform:$layerId:$groupIndex:$strokeId';

    // Ensure current state is at AFTER (it should be already, but safe)
    _applyStrokePointsNoHistory(
      layerId,
      groupIndex,
      strokeId,
      afterPoints,
      knobKey: key,
    );

    final p = _pendingKnob;
    if (p == null) return;
    if (p.key != key) return;

    knobEditEnd();
  }

  void endStrokeParamKnob(
    String layerId,
    int groupIndex,
    String strokeId, {
    required String paramKey,
  }) {
    final key = 'strokeKnob:$paramKey:$layerId:$groupIndex:$strokeId';
    final p = _pendingKnob;
    if (p == null) return;
    if (p.key != key) return;
    knobEditEnd();
  }

  /// ✅ Rename stroke from UI.
  void renameStrokeRef(
    String layerId,
    int groupIndex,
    String strokeId,
    String newName,
  ) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    updateStrokeById(
        layerId, groupIndex, strokeId, (s) => s.copyWith(name: trimmed));
  }

  /// ✅ Toggle stroke visibility from UI.
  void setStrokeVisibilityRef(
    String layerId,
    int groupIndex,
    String strokeId,
    bool visible,
  ) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    if (strokes[si].visible == visible) return;

    strokes[si] = strokes[si].copyWith(visible: visible);

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    // If we hid the selected stroke, clear selection (avoids “ghost selection”).
    if (!visible && _selectedStrokeId == strokeId) {
      clearSelection();
    }

    // ✅ keep pivot centered if this layer is being rotated by LFO/constant/manual
    _ensureLayerPivot(layerId);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  /// Reorder strokes within a layer/group by ids (UNDO/REDO).
  void reorderStrokesRef(
    String layerId,
    int groupIndex,
    List<String> orderedStrokeIds,
  ) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layer = _state.layers[li];
    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final group = layer.groups[groupIndex];
    if (orderedStrokeIds.length != group.strokes.length) return;

    final beforeIds = [for (final s in group.strokes) s.id];
    // no-op guard
    if (_listEquals(beforeIds, orderedStrokeIds)) return;

    final afterIds = List<String>.from(orderedStrokeIds);

    final cmd = LambdaCommand(
      label: 'Reorder Strokes',
      apply: () {
        _reorderStrokesNoHistory(layerId, groupIndex, afterIds);
      },
      undo: () {
        _reorderStrokesNoHistory(layerId, groupIndex, beforeIds);
      },
    );

    _doCommand(cmd, layerId: layerId);
  }

  /// tiny helper
  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Delete stroke from UI (UNDO/REDO).
  void deleteStrokeRef(String layerId, int groupIndex, String strokeId) {
    final li = _state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return;

    final layer = _state.layers[li];
    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final group = layer.groups[groupIndex];
    final si = group.strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final deletedStroke = group.strokes[si];
    final deletedIndex = si;

    final wasSelected = (_selectedStrokeId == strokeId);
    final prevSelection = (
      strokeId: _selectedStrokeId,
      layerId: _selectedLayerId,
      groupIndex: _selectedGroupIndex,
    );

    final cmd = LambdaCommand(
      label: 'Delete Stroke',
      apply: () {
        _deleteStrokeNoHistory(layerId, groupIndex, strokeId);
      },
      undo: () {
        _insertStrokeNoHistory(
            layerId, groupIndex, deletedIndex, deletedStroke);
        // restore selection if it was selected
        if (wasSelected) {
          _selectedStrokeId = prevSelection.strokeId;
          _selectedLayerId = prevSelection.layerId;
          _selectedGroupIndex = prevSelection.groupIndex;
        }
      },
    );

    _doCommand(cmd, layerId: layerId);
  }

  // ---------------------------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------------------------

  void _recomputeBrushGlow() {
    final r = glowRadius.clamp(0.0, 1.0);
    final o = glowOpacity.clamp(0.0, 1.0);
    _brushGlow = r * o;
  }

  void _tick() {
    repaint.value++;
  }

  void _rebuildRendererSafe() {
    // 1) Ensure any rotating layer has a persisted pivot (prevents 0,0 fallback)
    for (final l in _state.layers) {
      _ensureLayerPivotForRotation(l.id);
    }

    // 2) Now rebuild renderer using the updated state
    _renderer.rebuildFromLayers(_state.layers);
  }

  // ---------------------------------------------------------------------------
  // SELECTION: MIRROR/TRUTH CORRECTIONS
  // ---------------------------------------------------------------------------

  Offset _correctedWorldDelta(Offset d) {
    final dx = _selectedMirrorX ? -d.dx : d.dx;
    final dy = _selectedMirrorY ? -d.dy : d.dy;
    return Offset(dx, dy);
  }

  double _correctedRotation(double r) {
    final oddMirror = _selectedMirrorX ^ _selectedMirrorY;
    return oddMirror ? -r : r;
  }

  // ---------------------------------------------------------------------------
  // SELECTION: HIT TEST + MOVE (+ symmetry copies)
  // ---------------------------------------------------------------------------

  Offset _mirrorV(Offset p, double cx) => Offset(2 * cx - p.dx, p.dy);
  Offset _mirrorH(Offset p, double cy) => Offset(p.dx, 2 * cy - p.dy);

  List<_SymVariant> _symmetryVariantsWithFlags(
      List<Offset> baseWorldPoints, String? symId) {
    if (_canvasSize == Size.zero) {
      return [
        _SymVariant(baseWorldPoints, mirrorX: false, mirrorY: false),
      ];
    }

    final cx = _canvasSize.width / 2.0;
    final cy = _canvasSize.height / 2.0;

    List<Offset> v(List<Offset> pts) => [for (final p in pts) _mirrorV(p, cx)];
    List<Offset> h(List<Offset> pts) => [for (final p in pts) _mirrorH(p, cy)];

    switch (symId ?? 'off') {
      case 'mirrorV':
        return [
          _SymVariant(baseWorldPoints, mirrorX: false, mirrorY: false),
          _SymVariant(v(baseWorldPoints), mirrorX: true, mirrorY: false),
        ];
      case 'mirrorH':
        return [
          _SymVariant(baseWorldPoints, mirrorX: false, mirrorY: false),
          _SymVariant(h(baseWorldPoints), mirrorX: false, mirrorY: true),
        ];
      case 'quad':
        final vv = v(baseWorldPoints);
        final hh = h(baseWorldPoints);
        final vh = h(vv);
        return [
          _SymVariant(baseWorldPoints, mirrorX: false, mirrorY: false),
          _SymVariant(vv, mirrorX: true, mirrorY: false),
          _SymVariant(hh, mirrorX: false, mirrorY: true),
          _SymVariant(vh, mirrorX: true, mirrorY: true),
        ];
      case 'off':
      default:
        return [
          _SymVariant(baseWorldPoints, mirrorX: false, mirrorY: false),
        ];
    }
  }

  Offset _closestPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLen2 == 0) return a;

    final t = ((ap.dx * ab.dx) + (ap.dy * ab.dy)) / abLen2;
    final tt = t.clamp(0.0, 1.0);
    return Offset(a.dx + ab.dx * tt, a.dy + ab.dy * tt);
  }

  _StrokeHit? _hitTestStrokeWorld(Offset worldPos) {
    for (int li = _state.layers.length - 1; li >= 0; li--) {
      final layer = _state.layers[li];
      if (!layer.visible) continue;

      final tr = layer.transform;

      // ✅ IMPORTANT: treat LFO/constant rotation as "non-identity" for pivot math
      final needsPivot = _layerNeedsPivotNow(layer);
      final pivot = needsPivot ? _layerPivotForMath(layer) : Offset.zero;

      for (int gi = layer.groups.length - 1; gi >= 0; gi--) {
        final group = layer.groups[gi];

        for (int si = group.strokes.length - 1; si >= 0; si--) {
          final sLocal = group.strokes[si];
          if (!sLocal.visible) continue; // ✅ cannot select hidden

          final hitRadius = math.max(12.0, sLocal.size * 0.9);
          final hitR2 = hitRadius * hitRadius;

          final baseWorldPts = <Offset>[];
          for (final p in sLocal.points) {
            final local = Offset(p.x, p.y);
            final world =
                needsPivot ? _forwardTransformPoint(local, tr, pivot) : local;
            baseWorldPts.add(world);
          }

          final variants =
              _symmetryVariantsWithFlags(baseWorldPts, sLocal.symmetryId);

          for (final variant in variants) {
            Offset? prev;
            for (final w in variant.pts) {
              if (prev != null) {
                final cp = _closestPointOnSegment(worldPos, prev, w);
                final d = worldPos - cp;
                final d2 = d.dx * d.dx + d.dy * d.dy;
                if (d2 <= hitR2) {
                  return _StrokeHit(
                    strokeId: sLocal.id,
                    layerId: layer.id,
                    groupIndex: gi,
                    mirrorX: variant.mirrorX,
                    mirrorY: variant.mirrorY,
                    grabWorld: cp,
                  );
                }
              }
              prev = w;
            }
          }
        }
      }
    }
    return null;
  }

  void selectAtWorld(Offset worldPos) {
    final hit = _hitTestStrokeWorld(worldPos);
    if (hit == null) {
      clearSelection();
      return;
    }

    _selectedStrokeId = hit.strokeId;
    _selectedLayerId = hit.layerId;
    _selectedGroupIndex = hit.groupIndex;

    _selectedMirrorX = hit.mirrorX;
    _selectedMirrorY = hit.mirrorY;

    _selectionAnchorWorld = hit.grabWorld;

    notifyListeners();
  }

  void _moveSelectedByWorldDelta(Offset deltaWorld) {
    final layerId = _selectedLayerId;
    final strokeId = _selectedStrokeId;
    final gi = _selectedGroupIndex;
    if (layerId == null || strokeId == null || gi == null) return;

    final layerIndex = _state.layers.indexWhere((l) => l.id == layerId);
    if (layerIndex < 0) return;

    final correctedWorldDelta = _correctedWorldDelta(deltaWorld);

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[layerIndex];

    if (gi < 0 || gi >= layer.groups.length) return;
    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[gi];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final tr = layer.transform;

    // ✅ IMPORTANT: treat LFO/constant rotation as "non-identity" for delta conversion
    final needsPivot = _layerNeedsPivotNow(layer);

    Offset deltaLocal;
    if (!needsPivot) {
      deltaLocal = correctedWorldDelta;
    } else {
      final s = (tr.scale == 0.0) ? 1.0 : tr.scale;
      final angle = -tr.rotation;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final unscaled =
          Offset(correctedWorldDelta.dx / s, correctedWorldDelta.dy / s);
      deltaLocal = Offset(
        unscaled.dx * cosA - unscaled.dy * sinA,
        unscaled.dx * sinA + unscaled.dy * cosA,
      );
    }

    final s0 = strokes[si];

    final movedPts = <PointSample>[
      for (final p in s0.points)
        PointSample(p.x + deltaLocal.dx, p.y + deltaLocal.dy, p.t),
    ];
    strokes[si] = s0.copyWith(points: movedPts);

    groups[gi] = group.copyWith(strokes: strokes);
    layers[layerIndex] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void selectionPointerDown(int pointer, Offset worldPos) {
    if (_activePointerId != null) return;
    if (_isSelectionGesturing) return;

    _activePointerId = pointer;

    selectAtWorld(worldPos);
    if (!hasSelection) return;

    _isDraggingSelection = true;
    _selectionDragLastWorld = worldPos;
  }

  void selectionPointerMove(int pointer, Offset worldPos) {
    if (_activePointerId != pointer) return;
    if (_isSelectionGesturing) return;
    if (!_isDraggingSelection) return;

    final last = _selectionDragLastWorld;
    if (last == null) return;

    final delta = worldPos - last;
    _selectionDragLastWorld = worldPos;

    if (delta.distanceSquared < 0.25) return;
    _moveSelectedByWorldDelta(delta);
  }

  void selectionPointerUp(int pointer) {
    if (_activePointerId != pointer) return;
    _activePointerId = null;

    _isDraggingSelection = false;
    _selectionDragLastWorld = null;
  }

  void selectionResumeDragAt(Offset worldPos) {
    if (!selectionMode || !hasSelection) return;
    if (_activePointerId == null) return;

    _isDraggingSelection = true;
    _selectionDragLastWorld = worldPos;
  }

  void selectionGestureStart({
    required Offset focalWorld,
    required double scale,
    required double rotation,
  }) {
    if (!selectionMode || !hasSelection) return;

    final layerId = _selectedLayerId;
    final strokeId = _selectedStrokeId;
    final gi = _selectedGroupIndex;
    if (layerId == null || strokeId == null || gi == null) return;

    final layerIndex = _state.layers.indexWhere((l) => l.id == layerId);
    if (layerIndex < 0) return;

    final layer = _state.layers[layerIndex];
    if (gi < 0 || gi >= layer.groups.length) return;

    final group = layer.groups[gi];
    final si = group.strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    _gestureStartLocalPoints = List<PointSample>.from(group.strokes[si].points);

    final anchorWorld = _selectionAnchorWorld ?? focalWorld;

    Offset pivotWorld = anchorWorld;
    if (_canvasSize != Size.zero) {
      final cx = _canvasSize.width / 2.0;
      final cy = _canvasSize.height / 2.0;

      if (_selectedMirrorX) pivotWorld = _mirrorV(pivotWorld, cx);
      if (_selectedMirrorY) pivotWorld = _mirrorH(pivotWorld, cy);
    }

    final tr = layer.transform;

    // ✅ IMPORTANT: treat LFO/constant rotation as "non-identity" for pivot conversion
    final needsPivot = _layerNeedsPivotNow(layer);
    final pivotLayer = needsPivot ? _layerPivotForMath(layer) : Offset.zero;

    final pivotLocal = needsPivot
        ? _inverseTransformPoint(pivotWorld, tr, pivotLayer)
        : pivotWorld;

    _gestureStartPivotLocal = pivotLocal;

    _gestureLastScale = scale;
    _gestureLastRotation = _correctedRotation(rotation);

    _isSelectionGesturing = true;
    notifyListeners();
  }

  void selectionGestureUpdate({
    required Offset focalWorld,
    required double scale,
    required double rotation,
  }) {
    if (!_isSelectionGesturing) return;

    final startPts = _gestureStartLocalPoints;
    final pivotLocal = _gestureStartPivotLocal;
    final layerId = _selectedLayerId;
    final strokeId = _selectedStrokeId;
    final gi = _selectedGroupIndex;

    if (startPts == null ||
        pivotLocal == null ||
        layerId == null ||
        strokeId == null ||
        gi == null) return;

    final layerIndex = _state.layers.indexWhere((l) => l.id == layerId);
    if (layerIndex < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[layerIndex];

    if (gi < 0 || gi >= layer.groups.length) return;
    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[gi];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    final ds = (scale <= 0.0001) ? 1.0 : scale;

    final ang = _correctedRotation(rotation);

    final cosA = math.cos(ang);
    final sinA = math.sin(ang);

    final newPts = <PointSample>[];
    for (final p in startPts) {
      final v = Offset(p.x, p.y) - pivotLocal;

      final vs = v * ds;

      final vr = Offset(
        vs.dx * cosA - vs.dy * sinA,
        vs.dx * sinA + vs.dy * cosA,
      );

      final out = pivotLocal + vr;
      newPts.add(PointSample(out.dx, out.dy, p.t));
    }

    final s0 = strokes[si];
    strokes[si] = s0.copyWith(points: newPts);

    groups[gi] = group.copyWith(strokes: strokes);
    layers[layerIndex] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();

    _gestureLastScale = scale;
    _gestureLastRotation = ang;
  }

  void selectionGestureEnd() {
    _isSelectionGesturing = false;
    _gestureStartLocalPoints = null;
    _gestureStartPivotLocal = null;
    _gestureLastScale = 1.0;
    _gestureLastRotation = 0.0;

    notifyListeners();
  }

  void cancelPointer(int pointer) {
    if (_activePointerId == pointer) {
      _activePointerId = null;
    }
    _current = null;

    _isDraggingSelection = false;
    _selectionDragLastWorld = null;

    _tick();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // BRUSH / GLOW / BACKGROUND
  // ---------------------------------------------------------------------------

  void setBrushGlow(double value) {
    final v = value.clamp(0.0, 1.0);

    glowRadius = v;
    glowOpacity = 1.0;

    final double b = (v * 1.0).clamp(0.0, 1.0);
    glowBrightness = b;

    _recomputeBrushGlow();
    notifyListeners();
  }

  void setGlowRadius(double value) {
    glowRadius = value.clamp(0.0, 1.0);

    if (_advancedGlowEnabled) {
      _savedAdvancedGlowRadius = glowRadius;
    }

    _recomputeBrushGlow();
    notifyListeners();
  }

  void setGlowOpacity(double value) {
    glowOpacity = value.clamp(0.0, 1.0);

    if (_advancedGlowEnabled) {
      _savedAdvancedGlowOpacity = glowOpacity;
    }

    _recomputeBrushGlow();
    notifyListeners();
  }

  void setGlowBrightness(double value) {
    glowBrightness = value.clamp(0.0, 1.0);

    if (_advancedGlowEnabled) {
      _savedAdvancedGlowBrightness = glowBrightness;
    }

    _recomputeBrushGlow();
    notifyListeners();
  }

  void setBackgroundColor(int value) {
    backgroundColor = value;
    _hasCustomBackground = true;
    _hasUnsavedChanges = true;

    _tick();
    notifyListeners();
  }

  void setAdvancedGlowEnabled(bool value) {
    if (_advancedGlowEnabled == value) return;

    if (value) {
      _savedSimpleGlow = brushGlow;

      glowRadius = _savedAdvancedGlowRadius.clamp(0.0, 1.0);
      glowBrightness = _savedAdvancedGlowBrightness.clamp(0.0, 1.0);
      glowOpacity = _savedAdvancedGlowOpacity.clamp(0.0, 1.0);

      _recomputeBrushGlow();
    } else {
      _savedAdvancedGlowRadius = glowRadius.clamp(0.0, 1.0);
      _savedAdvancedGlowBrightness = glowBrightness.clamp(0.0, 1.0);
      _savedAdvancedGlowOpacity = glowOpacity.clamp(0.0, 1.0);

      setBrushGlow(_savedSimpleGlow);
    }

    _advancedGlowEnabled = value;
    notifyListeners();
  }

  void setBrushSize(double v) {
    brushSize = v;
    notifyListeners();
  }

  void setCoreOpacity(double v) {
    coreOpacity = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setColor(int c) {
    color = c;
    notifyListeners();
  }

  void setBrush(String id) {
    brushId = id;
    notifyListeners();
  }

  void setSymmetry(SymmetryMode m) {
    symmetry = m;
    _tick();
    notifyListeners();
  }

  void cycleSymmetry() {
    switch (symmetry) {
      case SymmetryMode.off:
        setSymmetry(SymmetryMode.mirrorV);
        break;
      case SymmetryMode.mirrorV:
        setSymmetry(SymmetryMode.mirrorH);
        break;
      case SymmetryMode.mirrorH:
        setSymmetry(SymmetryMode.quad);
        break;
      case SymmetryMode.quad:
        setSymmetry(SymmetryMode.off);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // LAYER ROTATION API
  // ---------------------------------------------------------------------------

  void setLayerConstantRotation(
    String layerId, {
    required bool enabled,
    required double degPerSec,
  }) {
    final prev = _layerRotation[layerId] ?? const LayerRotationAnim();
    _layerRotation[layerId] = prev.copyWith(
      constantEnabled: enabled,
      constantDegPerSec: degPerSec,
    );

    // ✅ ensure pivot exists for constant rotation too
    _ensureLayerPivot(layerId);

    _renderer.rebuildFromLayers(_state.layers);

    _ensureTickerState();
    _tick();
  }

  void toggleActiveLayerConstantRotation({double degPerSec = 25.0}) {
    final id = activeLayerId;
    final prev = _layerRotation[id] ?? const LayerRotationAnim();
    final nextEnabled = !prev.constantEnabled;
    setLayerConstantRotation(
      id,
      enabled: nextEnabled,
      degPerSec: nextEnabled ? degPerSec : 0.0,
    );
  }

  // ---------------------------------------------------------------------------
  // LFO API (v1: routes -> layer extra rotation)
  // ---------------------------------------------------------------------------

  String addLfo({String? name}) {
    final id = 'lfo-${DateTime.now().millisecondsSinceEpoch}';
    final index = _lfos.length + 1;
    _lfos.add(Lfo(
      id: id,
      name: name ?? 'LFO $index',
      enabled: true,
      wave: LfoWave.sine,
      rateHz: 0.25,
      phase: 0.0,
      offset: 0.0,
    ));

    _hasUnsavedChanges = true; // ✅ ADD

    _ensureTickerState();
    _tick();
    notifyListeners();
    return id;
  }

  void removeLfo(String id) {
    _lfos.removeWhere((l) => l.id == id);
    _routes.removeWhere((r) => r.lfoId == id);

    _hasUnsavedChanges = true; // ✅ ADD

    _ensureTickerState();
    _tick();
    notifyListeners();
  }

  void renameLfo(String id, String name) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    _lfos[i] = _lfos[i].copyWith(name: trimmed);

    _hasUnsavedChanges = true; // ✅ ADD
    notifyListeners();
  }

  void reorderLfos(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _lfos.length) return;
    if (newIndex < 0 || newIndex >= _lfos.length) return;

    final item = _lfos.removeAt(oldIndex);
    _lfos.insert(newIndex, item);

    _hasUnsavedChanges = true; // ✅ ADD

    _tick();
    notifyListeners();
  }

  void setLfoEnabled(String id, bool enabled) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;
    _lfos[i] = _lfos[i].copyWith(enabled: enabled);

    // If this affects whether any layer "needs pivot", refresh pivots
    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setLfoCurveMode(String lfoId, LfoCurveMode mode) {
    final i = _lfos.indexWhere((x) => x.id == lfoId);
    if (i < 0) return;

    final old = _lfos[i];
    if (old.curveMode == mode) return;

    _lfos[i] = old.copyWith(curveMode: mode);
    notifyListeners(); // or your existing state update call
    _hasUnsavedChanges = true;
  }

  void setLfoWave(String id, LfoWave wave) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;
    _lfos[i] = _lfos[i].copyWith(wave: wave);

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setLfoRate(String id, double hz) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final v = hz.clamp(0.01, 20.0).toDouble();
    _lfos[i] = _lfos[i].copyWith(rateHz: v);

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setLfoPhase(String id, double phase01) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final v = phase01.clamp(0.0, 1.0).toDouble();
    _lfos[i] = _lfos[i].copyWith(phase: v);

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setLfoOffset(String id, double offset) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final v = offset.clamp(-1.0, 1.0).toDouble();
    _lfos[i] = _lfos[i].copyWith(offset: v);

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  // ---------------------------------------------------------------------------
  // LFO VISUAL CURVE API (Vital-style)
  // ---------------------------------------------------------------------------

  void setLfoShapeMode(String id, LfoShapeMode mode) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;

    var l = _lfos[i];

    // If switching to curve with no nodes, seed a nice default loop curve.
    if (mode == LfoShapeMode.curve && l.nodes.isEmpty) {
      l = l.copyWith(nodes: const [
        LfoNode(0.0, 0.0),
        LfoNode(0.25, 1.0),
        LfoNode(0.50, 0.0),
        LfoNode(0.75, -1.0),
        LfoNode(1.0, 0.0),
      ]);
    }

    _lfos[i] = l.copyWith(shapeMode: mode);
    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  /// Back-compat for UI code that calls setLfoCurve().
  /// This just forces curve mode and forwards to setLfoNodes().
  void setLfoCurve(String id, List<LfoNode> nodes) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;

    // sanitize + sort (same as setLfoNodes)
    final cleaned = nodes
        .map((n) => LfoNode(
              n.x.clamp(0.0, 1.0).toDouble(),
              n.y.clamp(-1.0, 1.0).toDouble(),
              bias: n.bias.clamp(0.0, 1.0).toDouble(),
              bulgeAmt: n.bulgeAmt.clamp(-2.5, 2.5).toDouble(),
              bendY: n.bendY.clamp(-1.0, 1.0).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    _lfos[i] = _lfos[i].copyWith(
      shapeMode: LfoShapeMode.curve,
      nodes: cleaned,
    );

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setLfoNodes(String id, List<LfoNode> nodes) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;

    // sanitize (KEEP handle data)
    final cleaned = nodes
        .map((n) => LfoNode(
              n.x.clamp(0.0, 1.0).toDouble(),
              n.y.clamp(-1.0, 1.0).toDouble(),
              bias: n.bias.clamp(0.0, 1.0).toDouble(),
              bulgeAmt: n.bulgeAmt.clamp(-2.5, 2.5).toDouble(),
              bendY: n.bendY.clamp(-1.0, 1.0).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    _lfos[i] = _lfos[i].copyWith(nodes: cleaned);
    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  /// Add a node at a normalized position.
  /// Returns the index in the sorted list.
  int addLfoNode(String id, {required double x01, required double y11}) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return -1;

    final l = _lfos[i];
    final nodes = List<LfoNode>.from(l.nodes);

    final nx = x01.clamp(0.0, 1.0).toDouble();
    final ny = y11.clamp(-1.0, 1.0).toDouble();

    nodes.add(LfoNode(nx, ny));
    nodes.sort((a, b) => a.x.compareTo(b.x));

    _lfos[i] = l.copyWith(nodes: nodes, shapeMode: LfoShapeMode.curve);
    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;

    return nodes
        .indexWhere((n) => (n.x - nx).abs() < 1e-9 && (n.y - ny).abs() < 1e-9);
  }

  void moveLfoNode(String id, int index,
      {required double x01, required double y11}) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;

    final l = _lfos[i];
    final nodes = List<LfoNode>.from(l.nodes);
    if (index < 0 || index >= nodes.length) return;

    final nx = x01.clamp(0.0, 1.0).toDouble();
    final ny = y11.clamp(-1.0, 1.0).toDouble();

    // If endpoints exist, you may want to "lock" x of 0 and 1 points.
    // We'll keep it simple: allow movement.
    nodes[index] = nodes[index].copyWith(x: nx, y: ny);
    nodes.sort((a, b) => a.x.compareTo(b.x));

    _lfos[i] = l.copyWith(nodes: nodes, shapeMode: LfoShapeMode.curve);
    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void removeLfoNode(String id, int index) {
    final i = _lfos.indexWhere((l) => l.id == id);
    if (i < 0) return;

    final l = _lfos[i];
    final nodes = List<LfoNode>.from(l.nodes);
    if (index < 0 || index >= nodes.length) return;

    // Don’t allow deleting if it would leave empty (optional).
    if (nodes.length <= 2) return;

    nodes.removeAt(index);

    _lfos[i] = l.copyWith(nodes: nodes, shapeMode: LfoShapeMode.curve);
    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  String addRouteToLayer(
    String lfoId,
    String layerId, {
    LfoParam param = LfoParam.layerRotationDeg,
    double amount = 25.0,
  }) {
    final exists = _lfos.any((l) => l.id == lfoId);
    if (!exists) return '';
    if (!_state.layers.any((l) => l.id == layerId)) return '';

    final id = 'route-${DateTime.now().millisecondsSinceEpoch}';
    _routes.add(LfoRoute(
      id: id,
      lfoId: lfoId,
      layerId: layerId,
      enabled: true,
      param: param,
      bipolar: true,
      amount: amount, // v1: also used as generic amount for X/Y
    ));

    // ✅ if the route is rotation and enabled, ensure pivot exists now
    if (param == LfoParam.layerRotationDeg) {
      _ensureLayerPivot(layerId);
    }

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
    return id;
  }

  void removeRoute(String routeId) {
    _routes.removeWhere((r) => r.id == routeId);

    // routes removal can change pivot necessity; refresh all
    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setRouteEnabled(String routeId, bool enabled) {
    final i = _routes.indexWhere((r) => r.id == routeId);
    if (i < 0) return;

    final prev = _routes[i];
    _routes[i] = prev.copyWith(enabled: enabled);

    final now = _routes[i];

    // ✅ If enabling a layer-rotation route, ensure pivot exists/refreshes
    if (now.enabled &&
        now.param == LfoParam.layerRotationDeg &&
        !now.isStrokeTarget) {
      _ensureLayerPivot(now.layerId);
    }

    // If disabling could remove "needs pivot", refresh pivots anyway
    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setRouteLayer(String routeId, String layerId) {
    final i = _routes.indexWhere((r) => r.id == routeId);
    if (i < 0) return;
    if (!_state.layers.any((l) => l.id == layerId)) return;

    _routes[i] = _routes[i].copyWith(layerId: layerId);

    final now = _routes[i];
    if (now.enabled &&
        now.param == LfoParam.layerRotationDeg &&
        !now.isStrokeTarget) {
      _ensureLayerPivot(layerId);
    }

    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setRouteAmount(String routeId, double amount) {
    final i = _routes.indexWhere((r) => r.id == routeId);
    if (i < 0) return;

    final r = _routes[i];

    // Rotation is degrees; X/Y are pixels (v1 uses amount as generic amount).
    final double v;
    switch (r.param) {
      case LfoParam.layerRotationDeg:
      case LfoParam.strokeRotationDeg:
        v = amount.clamp(0.0, 360.0).toDouble();
        break;

      case LfoParam.layerX:
      case LfoParam.layerY:
      case LfoParam.strokeX:
      case LfoParam.strokeY:
        v = amount.clamp(0.0, 4000.0).toDouble();
        break;

      case LfoParam.layerScale:
        v = amount
            .clamp(-0.99, 5.0)
            .toDouble(); // avoid negative/zero scale multipliers
        break;

      case LfoParam.strokeSize:
        v = amount.clamp(-200.0, 200.0).toDouble();
        break;

      // ✅ VISUAL PARAMS: treat "amount" as DEPTH above base (0..1)
      case LfoParam.layerOpacity:
      case LfoParam.strokeCoreOpacity:
      case LfoParam.strokeGlowRadius:
      case LfoParam.strokeGlowOpacity:
      case LfoParam.strokeGlowBrightness:
        v = amount.clamp(-1.0, 1.0).toDouble();
        break;

      default:
        v = amount.toDouble();
        break;
    }

    _routes[i] = r.copyWith(amount: v);

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setRouteParam(String routeId, LfoParam param) {
    final i = _routes.indexWhere((r) => r.id == routeId);
    if (i < 0) return;

    final prev = _routes[i];
    _routes[i] = prev.copyWith(param: param);

    final now = _routes[i];

    if (now.enabled &&
        now.param == LfoParam.layerRotationDeg &&
        !now.isStrokeTarget) {
      _ensureLayerPivot(now.layerId);
    }

    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  void setRouteBipolar(String routeId, bool bipolar) {
    final i = _routes.indexWhere((r) => r.id == routeId);
    if (i < 0) return;

    _routes[i] = _routes[i].copyWith(bipolar: bipolar);

    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  LfoRoute? findRouteForLayerParam(String layerId, LfoParam param) {
    for (final r in _routes) {
      if (r.layerId == layerId && r.param == param && r.strokeId == null) {
        return r;
      }
    }
    return null;
  }

  String upsertRouteForLayerParam({
    required String layerId,
    required LfoParam param,
    required String lfoId,
  }) {
    // enforce 1 route per (layer,param) for layer-level routes
    _routes.removeWhere(
        (r) => r.layerId == layerId && r.param == param && r.strokeId == null);

    final id = 'route-${DateTime.now().millisecondsSinceEpoch}';
    _routes.add(LfoRoute(
      id: id,
      lfoId: lfoId,
      layerId: layerId,
      strokeId: null,
      param: param,
      enabled: true,
      bipolar: true,
      amount: _defaultAmountForParam(param),
    ));

    if (param == LfoParam.layerRotationDeg) {
      _ensureLayerPivot(layerId);
    }

    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
    return id;
  }

  void clearRouteForLayerParam(String layerId, LfoParam param) {
    _routes.removeWhere(
        (r) => r.layerId == layerId && r.param == param && r.strokeId == null);

    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

// ---------------------------------------------------------------------------
// STROKE ROUTE HELPERS (LfoParam-based, matches layer_panel.dart)
// ---------------------------------------------------------------------------

  LfoRoute? findRouteForStrokeParam(
    String layerId,
    int groupIndex,
    String strokeId,
    LfoParam param,
  ) {
    for (final r in _routes) {
      if (r.layerId != layerId) continue;
      if (r.strokeId != strokeId) continue;
      if (r.param != param) continue;
      return r;
    }
    return null;
  }

  void clearRouteForStrokeParam(
    String layerId,
    int groupIndex,
    String strokeId,
    LfoParam param,
  ) {
    _routes.removeWhere(
      (r) => r.layerId == layerId && r.strokeId == strokeId && r.param == param,
    );

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;
  }

  String upsertRouteForStrokeParam({
    required String layerId,
    required String strokeId,
    required LfoParam param,
    required String lfoId,
    required int groupIndex,
  }) {
    // one route per (stroke,param)
    _routes.removeWhere(
      (r) => r.layerId == layerId && r.strokeId == strokeId && r.param == param,
    );

    final id = 'route-${DateTime.now().millisecondsSinceEpoch}';
    _routes.add(LfoRoute(
      id: id,
      lfoId: lfoId,
      layerId: layerId,
      strokeId: strokeId,
      param: param,
      enabled: true,
      bipolar: true,
      amount: _defaultAmountForParam(param),
    ));

    _ensureTickerState();
    _tick();
    notifyListeners();
    _hasUnsavedChanges = true;

    return id;
  }

  // ---------------------------------------------------------------------------
  // STROKE UPDATE API (only size + points edits in this build)
  // ---------------------------------------------------------------------------

  CanvasState _setStrokeInState(
    CanvasState state, {
    required String layerId,
    required int groupIndex,
    required String strokeId,
    required Stroke newStroke,
  }) {
    final li = state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return state;

    final layers = List<CanvasLayer>.from(state.layers);
    final layer = layers[li];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return state;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return state;

    strokes[si] = newStroke;

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[li] = layer.copyWith(groups: groups);
    return state.copyWith(layers: layers);
  }

  void updateStrokeById(
    String layerId,
    int groupIndex,
    String strokeId,
    Stroke Function(Stroke s) update,
  ) {
    final layerIndex = _state.layers.indexWhere((l) => l.id == layerId);
    if (layerIndex < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[layerIndex];

    if (groupIndex < 0 || groupIndex >= layer.groups.length) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final si = strokes.indexWhere((s) => s.id == strokeId);
    if (si < 0) return;

    strokes[si] = update(strokes[si]);

    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[layerIndex] = layer.copyWith(groups: groups);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(layerId);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  List<StrokeRef> strokesForLayer(String layerId) {
    final layerIndex = _state.layers.indexWhere((l) => l.id == layerId);
    if (layerIndex < 0) return const [];

    final layer = _state.layers[layerIndex];
    final out = <StrokeRef>[];
    for (int gi = 0; gi < layer.groups.length; gi++) {
      final g = layer.groups[gi];
      for (final s in g.strokes) {
        out.add(StrokeRef(layerId: layerId, groupIndex: gi, stroke: s));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // LAYER MANAGEMENT
  // ---------------------------------------------------------------------------

  void setActiveLayer(String id) {
    if (id == _state.activeLayerId) return;
    final exists = _state.layers.any((l) => l.id == id);
    if (!exists) return;
    _state = _state.copyWith(activeLayerId: id);

    if (_selectedLayerId != null && _selectedLayerId != id) {
      clearSelection();
    }

    notifyListeners();
  }

  String addLayer({String? name}) {
    final index = _state.layers.length + 1;
    final id = 'layer-$index';
    final layerName = name ?? 'Layer $index';

    final newLayer = const CanvasLayer(
      id: 'placeholder',
      name: 'placeholder',
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
    ).copyWith(id: id, name: layerName);

    final newLayers = List<CanvasLayer>.from(_state.layers)..add(newLayer);

    _state = _state.copyWith(
      layers: newLayers,
      activeLayerId: id,
      redoStack: const [],
    );

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
    return id;
  }

  void removeLayer(String id) {
    if (_state.layers.length <= 1) return;

    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final removedLayer = _state.layers[idx];

    // capture associated state we currently destroy
    final removedRotation = _layerRotation[id];
    final removedRoutes = _routes.where((r) => r.layerId == id).toList();

    final prevActive = _state.activeLayerId;

    final wasSelectedLayer = (_selectedLayerId == id);
    final prevSelection = (
      strokeId: _selectedStrokeId,
      layerId: _selectedLayerId,
      groupIndex: _selectedGroupIndex,
    );

    final cmd = LambdaCommand(
      label: 'Delete Layer',
      apply: () {
        // state
        _removeLayerNoHistory(id);

        // side state
        _layerRotation.remove(id);
        _routes.removeWhere((r) => r.layerId == id);

        if (wasSelectedLayer) clearSelection();
      },
      undo: () {
        // restore layer at same index
        _insertLayerNoHistory(idx, removedLayer);

        // restore active exactly
        if (_state.layers.any((l) => l.id == prevActive)) {
          _state = _state.copyWith(activeLayerId: prevActive);
        }

        // restore side state
        if (removedRotation != null) {
          _layerRotation[id] = removedRotation;
        }
        if (removedRoutes.isNotEmpty) {
          // remove any current routes to that layer (safety) then restore
          _routes.removeWhere((r) => r.layerId == id);
          _routes.addAll(removedRoutes);
        }

        // restore selection if it was on that layer
        if (wasSelectedLayer) {
          _selectedStrokeId = prevSelection.strokeId;
          _selectedLayerId = prevSelection.layerId;
          _selectedGroupIndex = prevSelection.groupIndex;
        }
      },
    );

    _doCommand(cmd, layerId: id);
  }

  void setLayerVisibility(String id, bool visible) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    if (layer.visible == visible) return;

    layers[idx] = layer.copyWith(visible: visible);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(id);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void setLayerLocked(String id, bool locked) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    if (layer.locked == locked) return;

    layers[idx] = layer.copyWith(locked: locked);
    _state = _state.copyWith(layers: layers);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void renameLayer(String id, String name) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    layers[idx] = layer.copyWith(name: name);
    _state = _state.copyWith(layers: layers);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setLayerPosition(String id, double x, double y) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];

    layers[idx] = layer.copyWith(
      transform: layer.transform.copyWith(position: Offset(x, -y)), // ✅ flip
    );
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(id);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void setLayerOpacity(String id, double opacity) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];

    final clamped = opacity.clamp(0.0, 1.0);

    layers[idx] = layer.copyWith(
      transform: layer.transform.copyWith(opacity: clamped),
    );

    _state = _state.copyWith(layers: layers);
    _hasUnsavedChanges = true;

    _ensureLayerPivot(id);

    _renderer.rebuildFromLayers(_state.layers);
    _tick();
    notifyListeners();
  }

  void setLayerRotationDegrees(String id, double degrees) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];

    final double radians = degrees * math.pi / 180.0;

    // 1) apply rotation
    final newTransform = layer.transform.copyWith(rotation: radians);
    layers[idx] = layer.copyWith(transform: newTransform);
    _state = _state.copyWith(layers: layers);

    // 2) ensure pivot exists for rotation (combined strokes center)
    _ensureLayerPivot(id);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void setLayerScale(String id, double scale) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final clamped = scale.clamp(0.1, 5.0);

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];

    layers[idx] = layer.copyWith(
      transform: layer.transform.copyWith(scale: clamped.toDouble()),
    );
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivot(id);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void reorderLayersByIds(List<String> orderedIds) {
    if (orderedIds.length != _state.layers.length) return;

    final beforeIds = [for (final l in _state.layers) l.id];
    if (_listEquals(beforeIds, orderedIds)) return;

    final afterIds = List<String>.from(orderedIds);

    final cmd = LambdaCommand(
      label: 'Reorder Layers',
      apply: () => _reorderLayersNoHistory(afterIds),
      undo: () => _reorderLayersNoHistory(beforeIds),
    );

    _doCommand(cmd);
  }

  // ---------------------------------------------------------------------------
  // DRAWING FLOW (store LOCAL; renderer transforms to WORLD)
  // ---------------------------------------------------------------------------

  void pointerDown(int pointer, Offset pos) {
    if (_activePointerId != null) return;
    if (activeLayer.locked) return;
    if (_isSelectionGesturing) return;

    _activePointerId = pointer;

    final layer = activeLayer;
    final baseTr = layer.transform;

    _drawingInWorld = _layerIsAnimatedNow(layer.id);
    _drawingLayerId = layer.id;
    _drawingBaseLayerTr = baseTr;

    _startMs = DateTime.now().millisecondsSinceEpoch;

    // ✅ If layer is animated, store WORLD points (normal drawing feel)
    final startPoint = pos;

    _current = Stroke(
      id: 's${_state.allStrokes.length}_$_startMs',
      brushId: brushId,
      name: 'Stroke ${_state.allStrokes.length + 1}',
      visible: true,
      color: color,
      size: brushSize,
      glow: brushGlow,
      glowRadius: glowRadius,
      glowOpacity: glowOpacity,
      glowBrightness: glowBrightness,
      coreOpacity: coreOpacity,
      glowRadiusScalesWithSize: glowRadiusScalesWithSize,
      seed: 0,
      points: [PointSample(startPoint.dx, startPoint.dy, 0)],
      symmetryId: _symmetryId(symmetry),
    );

    // ✅ IMPORTANT:
    // ✅ While dragging, draw active stroke in WORLD overlay (ignores layer rotation)
    _drawingInWorld = true;
    _drawingLayerId = layer.id;
    _drawingBaseLayerTr = baseTr;

    _renderer.beginStroke(_current!, '__WORLD__', const LayerTransform());

    _tick();
  }

  void pointerMove(int pointer, Offset pos) {
    if (_activePointerId != pointer) return;
    final sLocal = _current;
    if (sLocal == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final tMs = now - _startMs;

    sLocal.points.add(PointSample(pos.dx, pos.dy, tMs));

    _renderer.updateStroke(sLocal);
    _tick();
  }

  void pointerUp(int pointer) {
    if (_activePointerId != pointer) return;
    _activePointerId = null;

    final sWorld = _current;
    if (sWorld == null) return;
    _current = null;

    final layer = activeLayer;
    final baseTr = _drawingBaseLayerTr ?? layer.transform;

    // ✅ STEP 3: ensure pivot is persisted BEFORE baking/commit so it never changes on lift
    _ensureLayerPivotForRotation(layer.id);

    // Re-fetch the layer from state (because ensure pivot may have updated it)
    final li = _state.layers.indexWhere((l) => l.id == layer.id);
    final layerNow = (li >= 0) ? _state.layers[li] : layer;

    // ✅ Use ONLY the persisted pivot (never recompute during bake)
    final persistedPivot =
        layerNow.transform.pivot ?? baseTr.pivot ?? Offset.zero;

    // ✅ Bake: convert WORLD points into LAYER-LOCAL using EFFECTIVE transform at lift moment
    if (_drawingInWorld && _drawingLayerId == layer.id) {
      // Effective transform at lift moment (includes LFO rotation etc.)
      var eff = _effectiveLayerTransformForInput(layer.id, baseTr);

      // ✅ Force the effective transform to rotate around the same persisted pivot
      eff = eff.copyWith(pivot: persistedPivot);

      final isId = _isIdentityTransform(eff);

      final localPts = <PointSample>[];
      for (final p in sWorld.points) {
        final w = Offset(p.x, p.y);
        final l = isId ? w : _inverseTransformPoint(w, eff, persistedPivot);
        localPts.add(PointSample(l.dx, l.dy, p.t));
      }

      final bakedLocal = sWorld.copyWith(points: localPts);

      _renderer.commitStroke();

      final strokeToAdd = bakedLocal;

      final targetLayerId = _drawingLayerId ?? activeLayerId;
      const targetGroupIndex = 0;

      final cmd = LambdaCommand(
        label: 'Add Stroke',
        apply: () {
          _state = _addStrokeToLayer(
            _state,
            layerId: targetLayerId,
            groupIndex: targetGroupIndex,
            stroke: strokeToAdd,
          );
        },
        undo: () {
          _state = _removeStrokeById(
            _state,
            layerId: targetLayerId,
            strokeId: strokeToAdd.id,
          );
          if (_selectedStrokeId == strokeToAdd.id) clearSelection();
        },
      );

      _doCommand(cmd, layerId: targetLayerId);
    } else {
      _renderer.commitStroke();

      final strokeToAdd = sWorld;

      final targetLayerId = _drawingLayerId ?? activeLayerId;
      const targetGroupIndex = 0;

      final cmd = LambdaCommand(
        label: 'Add Stroke',
        apply: () {
          _state = _addStrokeToLayer(
            _state,
            layerId: targetLayerId,
            groupIndex: targetGroupIndex,
            stroke: strokeToAdd,
          );
        },
        undo: () {
          _state = _removeStrokeById(
            _state,
            layerId: targetLayerId,
            strokeId: strokeToAdd.id,
          );
          if (_selectedStrokeId == strokeToAdd.id) clearSelection();
        },
      );

      _doCommand(cmd, layerId: targetLayerId);
    }

    // reset flags
    _drawingInWorld = false;
    _drawingLayerId = null;
    _drawingBaseLayerTr = null;

    // ✅ Make sure pivot still exists (no refresh) + safe rebuild
    _ensureLayerPivotForRotation(activeLayerId);
    _rebuildRendererSafe();

    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  CanvasState _removeStrokeById(
    CanvasState state, {
    required String layerId,
    required String strokeId,
  }) {
    final li = state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return state;

    final layers = List<CanvasLayer>.from(state.layers);
    final layer = layers[li];

    final groups = List<StrokeGroup>.from(layer.groups);
    bool changed = false;

    for (int gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      final strokes = List<Stroke>.from(g.strokes);
      final idx = strokes.indexWhere((s) => s.id == strokeId);
      if (idx < 0) continue;

      strokes.removeAt(idx);
      groups[gi] = g.copyWith(strokes: strokes);
      changed = true;
      break;
    }

    if (!changed) return state;

    layers[li] = layer.copyWith(groups: groups);
    return state.copyWith(layers: layers);
  }

  CanvasState _addStrokeToLayer(
    CanvasState state, {
    required String layerId,
    required int groupIndex,
    required Stroke stroke,
  }) {
    final li = state.layers.indexWhere((l) => l.id == layerId);
    if (li < 0) return state;

    final layers = List<CanvasLayer>.from(state.layers);
    final layer = layers[li];
    if (layer.locked) return state;

    final groups = List<StrokeGroup>.from(layer.groups);
    if (groups.isEmpty) return state;

    final gi = groupIndex.clamp(0, groups.length - 1);
    final g = groups[gi];

    groups[gi] = g.copyWith(strokes: [...g.strokes, stroke]);
    layers[li] = layer.copyWith(groups: groups);

    return state.copyWith(layers: layers);
  }

  CanvasState _addStrokeToActiveLayer(CanvasState state, Stroke stroke) {
    if (state.layers.isEmpty) {
      final fresh = CanvasState.initial();
      return _addStrokeToActiveLayer(fresh, stroke);
    }

    final int layerIndex =
        state.layers.indexWhere((l) => l.id == state.activeLayerId);
    final int targetLayerIndex = layerIndex >= 0 ? layerIndex : 0;
    final CanvasLayer layer = state.layers[targetLayerIndex];

    if (layer.locked) return state;

    if (layer.groups.isEmpty) {
      final defaultGroup = StrokeGroup(
        id: 'group-main',
        name: 'Group 1',
        transform: const GroupTransform(),
        strokes: [stroke],
      );
      final newLayer = layer.copyWith(groups: [defaultGroup]);
      final newLayers = List<CanvasLayer>.from(state.layers);
      newLayers[targetLayerIndex] = newLayer;
      return state.copyWith(layers: newLayers);
    }

    final groups = List<StrokeGroup>.from(layer.groups);
    final firstGroup = groups.first;
    final updatedGroup =
        firstGroup.copyWith(strokes: [...firstGroup.strokes, stroke]);
    groups[0] = updatedGroup;

    final newLayer = layer.copyWith(groups: groups);
    final newLayers = List<CanvasLayer>.from(state.layers);
    newLayers[targetLayerIndex] = newLayer;

    return state.copyWith(layers: newLayers);
  }

  String _symmetryId(SymmetryMode m) {
    switch (m) {
      case SymmetryMode.mirrorV:
        return 'mirrorV';
      case SymmetryMode.mirrorH:
        return 'mirrorH';
      case SymmetryMode.quad:
        return 'quad';
      case SymmetryMode.off:
        return 'off';
    }
  }

  // ---------------------------------------------------------------------------
  // DOC LOAD / NEW DOC
  // ---------------------------------------------------------------------------

  void loadFromBundle(CanvasDocumentBundle bundle) {
    final hasLayers = bundle.layers != null && bundle.layers!.isNotEmpty;

    // ---- 1) Restore core canvas state (layers/strokes) ----
    if (hasLayers) {
      final restoredLayers = List<CanvasLayer>.from(bundle.layers!);

      final savedActive = bundle.activeLayerId;
      final fallbackActive =
          restoredLayers.isNotEmpty ? restoredLayers.last.id : 'layer-main';

      final activeId = (savedActive != null &&
              restoredLayers.any((l) => l.id == savedActive))
          ? savedActive
          : fallbackActive;

      _state = CanvasState(
        layers: restoredLayers,
        activeLayerId: activeId,
        redoStack: const [],
      );
    } else {
      _state = CanvasState.fromStrokes(List<Stroke>.from(bundle.strokes));
    }

    _current = null;
    _activePointerId = null;

    // ---- 2) Restore per-document LFO state FIRST (so pivots/renderer see it) ----
    _lfos
      ..clear()
      ..addAll(bundle.lfos ?? const []);

    _routes
      ..clear()
      ..addAll(bundle.lfoRoutes ?? const []);

    // ---- 3) Clear selection + history for a freshly loaded doc ----
    clearSelection();
    _rebuildHistoryFromState();

    // ---- 4) Restore background ----
    final bg = bundle.doc.background;
    if (bg.type == doc_model.BackgroundType.solid &&
        bg.params['color'] is int) {
      backgroundColor = bg.params['color'] as int;
      _hasCustomBackground = true;
    } else {
      backgroundColor = 0xFF000000;
      _hasCustomBackground = false;
    }

    // ---- 5) Restore blend mode without flagging as dirty ----
    _suppressBlendDirty = true;
    final key = bundle.doc.blendModeKey;
    final mode = gb.glowBlendFromKey(key);
    gb.GlowBlendState.I.setMode(mode);

    // ---- 6) Ensure pivots AFTER LFO restore (because LFO routes affect "needs pivot") ----
    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    // ---- 7) Rebuild renderer + ticker state ----
    _rebuildRendererSafe();
    _ensureTickerState();

    // ---- 8) Loaded docs start "clean" ----
    _hasUnsavedChanges = false;

    _tick();
    notifyListeners();
  }

  void newDocument() {
    _state = CanvasState.initial();
    _current = null;
    _activePointerId = null;
    _hasUnsavedChanges = false;

    clearSelection();

    _history.clear();

    backgroundColor = 0xFF000000;
    _hasCustomBackground = false;

    _suppressBlendDirty = true;
    gb.GlowBlendState.I.setMode(gb.GlowBlend.additive);

    if (_maybeDevEnableSpin) {
      _layerRotation['layer-main'] = const LayerRotationAnim(
        constantEnabled: true,
        constantDegPerSec: 25,
      );
    } else {
      _layerRotation.remove('layer-main');
    }

    // ✅ v1: keep LFOs/routes session-only; reset them for new doc
    _lfos.clear();
    _routes.clear();

    // ✅ ensure pivots after resets
    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _rebuildRendererSafe();

    _ensureTickerState();
    _tick();
    notifyListeners();
  }

  void markSaved() {
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  void _afterEdit({String? layerId}) {
    // Keep pivots stable & renderer consistent after any edit
    if (layerId != null) _ensureLayerPivot(layerId);
    _rebuildRendererSafe();

    _hasUnsavedChanges = true;
    _ensureTickerState();
    _tick();
    notifyListeners();
  }

  void _doCommand(
    HistoryCommand cmd, {
    String? layerId,
    bool alreadyApplied = false,
  }) {
    if (!alreadyApplied) {
      cmd.apply();
    }
    _history.push(cmd);
    _afterEdit(layerId: layerId);
  }

  void _rebuildHistoryFromState() {
    // When loading a document, history should start clean.
    _history.clear();
  }

// ---------------------------------------------------------------------------
// KNOB HISTORY (NO TIMERS): begin -> update -> end
// ---------------------------------------------------------------------------

  _PendingKnobEdit? _pendingKnob;

  /// Call on finger DOWN (or onChangeStart).
  void knobEditBegin({
    required String key,
    required String label,
    required String? layerId,
    required VoidCallback undo,
    required VoidCallback redoLatest,
  }) {
    // If something else was mid-edit, commit it first
    if (_pendingKnob != null && _pendingKnob!.key != key) {
      knobEditEnd();
    }

    // Start a new pending edit (captures BEFORE via undo callback)
    _pendingKnob = _PendingKnobEdit(
      key: key,
      label: label,
      layerId: layerId,
      undo: undo,
      redo: redoLatest,
    );
  }

  /// Call on finger MOVE (or onChanged).
  void knobEditUpdate({
    required String key,
    required VoidCallback redoLatest,
  }) {
    final p = _pendingKnob;
    if (p == null) return;
    if (p.key != key) return;

    // Keep updating the redo closure to the latest value
    p.redo = redoLatest;
  }

  /// Call on finger UP (or onChangeEnd).
  void knobEditEnd() {
    final p = _pendingKnob;
    if (p == null) return;

    _pendingKnob = null;

    final cmd = LambdaCommand(
      label: p.label,
      apply: p.redo,
      undo: p.undo,
    );

    // State is already at "after" because we applied live during drag
    _doCommand(cmd, layerId: p.layerId, alreadyApplied: true);
  }

  // ---------------------------------------------------------------------------
  // UNDO / REDO
  // ---------------------------------------------------------------------------

  void undo() {
    if (!_history.canUndo) return;
    _history.undo();
    _afterEdit(); // rebuild + repaint
  }

  void redo() {
    if (!_history.canRedo) return;
    _history.redo();
    _afterEdit(); // rebuild + repaint
  }

  // ---------------------------------------------------------------------------
  // MISC
  // ---------------------------------------------------------------------------

  void setGlowRadiusScalesWithSize(bool value) {
    if (glowRadiusScalesWithSize == value) return;
    glowRadiusScalesWithSize = value;
    notifyListeners();
  }

  void _handleBlendChanged() {
    if (_suppressBlendDirty) {
      _suppressBlendDirty = false;
    } else {
      _hasUnsavedChanges = true;
    }

    // blend changes can alter renderer behaviour; keep pivots valid
    for (final l in _state.layers) {
      _ensureLayerPivot(l.id);
    }

    _rebuildRendererSafe();

    _tick();
    notifyListeners();
  }

  @override
  void dispose() {
    gb.GlowBlendState.I.removeListener(_handleBlendChanged);
    if (_tickerRunning) _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }
}

/// Small DTO for UI lists: stroke + where it lives.
class StrokeRef {
  final String layerId;
  final int groupIndex;
  final Stroke stroke;

  const StrokeRef({
    required this.layerId,
    required this.groupIndex,
    required this.stroke,
  });
}
