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

import '../render/renderer.dart';
import 'canvas_state.dart';
import 'glow_blend.dart' as gb;

enum SymmetryMode { off, mirrorV, mirrorH, quad }

final canvasControllerProvider =
    ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

class _StrokeLocation {
  final String strokeId;
  final String layerId;
  final int groupIndex;

  const _StrokeLocation({
    required this.strokeId,
    required this.layerId,
    required this.groupIndex,
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

    // -----------------------------------------------------------------------
    // DEV VISUAL TOGGLE:
    // If you want to SEE it immediately, set this true.
    // It will auto-spin layer-main after app starts / newDocument.
    // -----------------------------------------------------------------------
    _maybeDevEnableSpin = true;

    if (_maybeDevEnableSpin) {
      // Make sure the default layer is actually spinning immediately on launch
      _layerRotation['layer-main'] = const LayerRotationAnim(
          constantEnabled: true, constantDegPerSec: 25.0);

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

  // DEV toggle (see constructor)
  late bool _maybeDevEnableSpin;

  // Per-layer anim config
  final Map<String, LayerRotationAnim> _layerRotation = {};

  void _onTick(Duration elapsed) {
    _timeSec = elapsed.inMicroseconds / 1000000.0;
    // repaint only; no notifyListeners needed for UI panels
    _tick();
  }

  void _ensureTickerState() {
    final anyActive = _layerRotation.values.any((a) => a.isActive);
    if (anyActive && !_tickerRunning) {
      _ticker.start();
      _tickerRunning = true;
    } else if (!anyActive && _tickerRunning) {
      _ticker.stop();
      _tickerRunning = false;
      _timeSec = 0.0;
      _tick(); // final repaint to settle
    }
  }

  // This is what the renderer calls:
  double _layerExtraRotationRadians(String layerId) {
    final anim = _layerRotation[layerId];
    if (anim == null || !anim.isActive) return 0.0;

    // constant deg/sec * time
    final deg = anim.constantDegPerSec * _timeSec;

    // keep it bounded to avoid huge floats over long sessions
    final wrapped = deg % 360.0;

    return wrapped * math.pi / 180.0;
  }

  String? _selectedStrokeIdFn() => _selectedStrokeId;

  late final Renderer _renderer = Renderer(
    repaint,
    () => symmetry,
    layerExtraRotationRadians: _layerExtraRotationRadians,
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

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Renderer get painter => _renderer;

  bool _suppressBlendDirty = false;

  final List<_StrokeLocation> _history = [];
  final List<_StrokeLocation> _redoLocations = [];

  // ---------------------------------------------------------------------------
  // CANVAS SIZE (needed for symmetry selection hit test)
  // ---------------------------------------------------------------------------

  Size _canvasSize = Size.zero;

  void setCanvasSize(Size s) {
    if (_canvasSize == s) return;
    _canvasSize = s;
  }

  // ---------------------------------------------------------------------------
  // SELECTION MODE (UNCHANGED)
  // ---------------------------------------------------------------------------

  bool selectionMode = false;

  String? _selectedStrokeId;
  String? _selectedLayerId;
  int? _selectedGroupIndex;

  bool _selectedMirrorX = false;
  bool _selectedMirrorY = false;

  Offset? _selectionAnchorWorld;

  bool get hasSelection => _selectedStrokeId != null;

  bool _isDraggingSelection = false;
  Offset? _selectionDragLastWorld;

  bool _isSelectionGesturing = false;
  bool get isSelectionGesturing => _isSelectionGesturing;

  List<PointSample>? _gestureStartLocalPoints;
  Offset? _gestureStartPivotLocal;

  double _gestureLastScale = 1.0;
  double _gestureLastRotation = 0.0;

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

  bool _isIdentityTransform(LayerTransform t) {
    return t.position == Offset.zero &&
        t.scale == 1.0 &&
        t.rotation == 0.0 &&
        t.opacity == 1.0;
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

  void _ensureLayerPivotPersisted(String layerId) {
    final idx = _state.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;

    final layer = _state.layers[idx];
    final tr = layer.transform;

    if (_isIdentityTransform(tr)) return;
    if (tr.pivot != null) return;

    final pivot = _computeBoundsPivotForLayer(layer);

    final layers = List<CanvasLayer>.from(_state.layers);
    layers[idx] = layer.copyWith(transform: tr.copyWith(pivot: pivot));
    _state = _state.copyWith(layers: layers);
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

  void _recordStrokeCreation(Stroke s) {
    for (final layer in _state.layers) {
      for (int gi = 0; gi < layer.groups.length; gi++) {
        final group = layer.groups[gi];
        final idx = group.strokes.indexWhere((st) => st.id == s.id);
        if (idx != -1) {
          _history.add(_StrokeLocation(
            strokeId: s.id,
            layerId: layer.id,
            groupIndex: gi,
          ));
          _redoLocations.clear();
          _state = _state.copyWith(redoStack: []);
          return;
        }
      }
    }
  }

  void _rebuildHistoryFromState() {
    _history.clear();
    _redoLocations.clear();
    for (final layer in _state.layers) {
      for (int gi = 0; gi < layer.groups.length; gi++) {
        final group = layer.groups[gi];
        for (final s in group.strokes) {
          _history.add(_StrokeLocation(
            strokeId: s.id,
            layerId: layer.id,
            groupIndex: gi,
          ));
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // SELECTION: MIRROR/TRUTH CORRECTIONS (UNCHANGED)
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
  // SELECTION: HIT TEST + MOVE (+ symmetry copies) (UNCHANGED)
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
      final isIdentity = _isIdentityTransform(tr);
      final pivot = isIdentity
          ? Offset.zero
          : (tr.pivot ?? _computeBoundsPivotForLayer(layer));

      for (int gi = layer.groups.length - 1; gi >= 0; gi--) {
        final group = layer.groups[gi];

        for (int si = group.strokes.length - 1; si >= 0; si--) {
          final sLocal = group.strokes[si];

          final hitRadius = math.max(12.0, sLocal.size * 0.9);
          final hitR2 = hitRadius * hitRadius;

          final baseWorldPts = <Offset>[];
          for (final p in sLocal.points) {
            final local = Offset(p.x, p.y);
            final world =
                isIdentity ? local : _forwardTransformPoint(local, tr, pivot);
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
    final isIdentity = _isIdentityTransform(tr);

    Offset deltaLocal;
    if (isIdentity) {
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

    _ensureLayerPivotPersisted(layerId);

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
    final isIdentity = _isIdentityTransform(tr);
    final pivotLayer = isIdentity
        ? Offset.zero
        : (tr.pivot ?? _computeBoundsPivotForLayer(layer));

    final pivotLocal = isIdentity
        ? pivotWorld
        : _inverseTransformPoint(pivotWorld, tr, pivotLayer);

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

    _ensureLayerPivotPersisted(layerId);

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
  // BRUSH / GLOW / BACKGROUND (unchanged)
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
  // LAYER ROTATION API (new, safe)
  // ---------------------------------------------------------------------------

  /// Enable/disable constant rotation for a specific layer.
  /// Does not change active layer and does not affect selection logic.
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

    // If we changed an animation state, baked cache might need recalculation.
    _renderer.rebuildFromLayers(_state.layers);

    _ensureTickerState();
    _tick();
  }

  /// Convenience: toggle constant rotation on the active layer.
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
  // LAYER MANAGEMENT (unchanged except renderer rebuild call)
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
    );

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
    return id;
  }

  void removeLayer(String id) {
    if (_state.layers.length <= 1) return;

    final newLayers = List<CanvasLayer>.from(_state.layers)
      ..removeWhere((l) => l.id == id);
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

    _history.removeWhere((loc) => loc.layerId == id);
    _redoLocations.removeWhere((loc) => loc.layerId == id);

    // cleanup rotation state
    _layerRotation.remove(id);
    _ensureTickerState();

    if (_selectedLayerId == id) clearSelection();

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void setLayerVisibility(String id, bool visible) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    if (layer.visible == visible) return;

    layers[idx] = layer.copyWith(visible: visible);
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivotPersisted(id);

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
      transform: layer.transform.copyWith(position: Offset(x, y)),
    );
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivotPersisted(id);

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

    _ensureLayerPivotPersisted(id);

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

    layers[idx] = layer.copyWith(
      transform: layer.transform.copyWith(rotation: radians),
    );
    _state = _state.copyWith(layers: layers);

    _ensureLayerPivotPersisted(id);

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

    _ensureLayerPivotPersisted(id);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void reorderLayersByIds(List<String> orderedIds) {
    if (orderedIds.length != _state.layers.length) return;

    final map = {for (final l in _state.layers) l.id: l};

    final newLayers = <CanvasLayer>[];
    for (final id in orderedIds) {
      final layer = map[id];
      if (layer == null) return;
      newLayers.add(layer);
    }

    _state = _state.copyWith(layers: newLayers);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
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
    final tr = layer.transform;
    final isIdentity = _isIdentityTransform(tr);

    Offset pivot = Offset.zero;
    if (!isIdentity) {
      pivot = tr.pivot ?? _computeBoundsPivotForLayer(layer);

      if (tr.pivot == null) {
        final idx = _state.layers.indexWhere((l) => l.id == layer.id);
        if (idx >= 0) {
          final layers = List<CanvasLayer>.from(_state.layers);
          layers[idx] = layer.copyWith(transform: tr.copyWith(pivot: pivot));
          _state = _state.copyWith(layers: layers);
        }
      }
    }

    _startMs = DateTime.now().millisecondsSinceEpoch;

    final startPoint =
        isIdentity ? pos : _inverseTransformPoint(pos, tr, pivot);

    _current = Stroke(
      id: 's${_state.allStrokes.length}_$_startMs',
      brushId: brushId,
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

    _renderer.beginStroke(_current!, layer.id, layer.transform);
    _tick();
  }

  void pointerMove(int pointer, Offset pos) {
    if (_activePointerId != pointer) return;
    final sLocal = _current;
    if (sLocal == null) return;

    final layer = activeLayer;
    final tr = layer.transform;
    final isIdentity = _isIdentityTransform(tr);

    Offset pivot = Offset.zero;
    if (!isIdentity) {
      pivot = tr.pivot ?? _computeBoundsPivotForLayer(layer);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final tMs = now - _startMs;

    final localPoint =
        isIdentity ? pos : _inverseTransformPoint(pos, tr, pivot);
    sLocal.points.add(PointSample(localPoint.dx, localPoint.dy, tMs));

    _renderer.updateStroke(sLocal);
    _tick();
  }

  void pointerUp(int pointer) {
    if (_activePointerId != pointer) return;
    _activePointerId = null;

    final sLocal = _current;
    if (sLocal == null) return;
    _current = null;

    _renderer.commitStroke();

    _state = _addStrokeToActiveLayer(_state, sLocal);
    _recordStrokeCreation(sLocal);

    _renderer.rebuildFromLayers(_state.layers);

    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
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
    _hasUnsavedChanges = false;

    clearSelection();

    _rebuildHistoryFromState();

    final bg = bundle.doc.background;
    if (bg.type == doc_model.BackgroundType.solid &&
        bg.params['color'] is int) {
      backgroundColor = bg.params['color'] as int;
      _hasCustomBackground = true;
    } else {
      backgroundColor = 0xFF000000;
      _hasCustomBackground = false;
    }

    _suppressBlendDirty = true;
    final key = bundle.doc.blendModeKey;
    final mode = gb.glowBlendFromKey(key);
    gb.GlowBlendState.I.setMode(mode);

    for (final l in _state.layers) {
      _ensureLayerPivotPersisted(l.id);
    }

    _renderer.rebuildFromLayers(_state.layers);
    _ensureTickerState();
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
    _redoLocations.clear();

    backgroundColor = 0xFF000000;
    _hasCustomBackground = false;

    _suppressBlendDirty = true;
    gb.GlowBlendState.I.setMode(gb.GlowBlend.additive);

    for (final l in _state.layers) {
      _ensureLayerPivotPersisted(l.id);
    }

    // DEV: optional auto spin so you can see it working
    if (_maybeDevEnableSpin) {
      _layerRotation['layer-main'] =
          const LayerRotationAnim(constantEnabled: true, constantDegPerSec: 25);
    } else {
      _layerRotation.remove('layer-main');
    }

    _renderer.rebuildFromLayers(_state.layers);
    _ensureTickerState();
    _tick();
    notifyListeners();
  }

  void markSaved() {
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // UNDO / REDO (only renderer rebuild call changed)
  // ---------------------------------------------------------------------------

  void undo() {
    if (_history.isEmpty) return;

    final lastLoc = _history.removeLast();

    final layers = List<CanvasLayer>.from(_state.layers);
    final layerIndex = layers.indexWhere((l) => l.id == lastLoc.layerId);
    if (layerIndex == -1) return;

    final layer = layers[layerIndex];
    if (layer.groups.isEmpty ||
        lastLoc.groupIndex < 0 ||
        lastLoc.groupIndex >= layer.groups.length) {
      return;
    }

    final groups = List<StrokeGroup>.from(layer.groups);
    final group = groups[lastLoc.groupIndex];

    final strokes = List<Stroke>.from(group.strokes);
    final strokeIndex = strokes.indexWhere((st) => st.id == lastLoc.strokeId);
    if (strokeIndex == -1) return;

    final removed = strokes.removeAt(strokeIndex);

    groups[lastLoc.groupIndex] = group.copyWith(strokes: strokes);
    layers[layerIndex] = layer.copyWith(groups: groups);

    final newRedo = List<Stroke>.from(_state.redoStack)..add(removed);

    _state = _state.copyWith(
      layers: layers,
      redoStack: newRedo,
    );

    _redoLocations.add(lastLoc);

    if (_selectedStrokeId == removed.id) clearSelection();

    _ensureLayerPivotPersisted(lastLoc.layerId);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  void redo() {
    if (_state.redoStack.isEmpty || _redoLocations.isEmpty) return;

    final loc = _redoLocations.last;
    final stroke = _state.redoStack.last;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layerIndex = layers.indexWhere((l) => l.id == loc.layerId);
    if (layerIndex == -1) return;

    final layer = layers[layerIndex];
    if (layer.locked) return;

    final groups = List<StrokeGroup>.from(layer.groups);
    final groupIndex = (loc.groupIndex >= 0 && loc.groupIndex < groups.length)
        ? loc.groupIndex
        : 0;
    final group = groups[groupIndex];

    final strokes = List<Stroke>.from(group.strokes)..add(stroke);
    groups[groupIndex] = group.copyWith(strokes: strokes);
    layers[layerIndex] = layer.copyWith(groups: groups);

    final newRedo = List<Stroke>.from(_state.redoStack)..removeLast();
    _redoLocations.removeLast();

    _state = _state.copyWith(
      layers: layers,
      redoStack: newRedo,
    );

    _history.add(loc);

    _ensureLayerPivotPersisted(loc.layerId);

    _renderer.rebuildFromLayers(_state.layers);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
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

    for (final l in _state.layers) {
      _ensureLayerPivotPersisted(l.id);
    }

    _renderer.rebuildFromLayers(_state.layers);
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
