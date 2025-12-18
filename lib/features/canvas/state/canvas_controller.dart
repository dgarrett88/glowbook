import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/brush.dart';
import '../../../core/models/stroke.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_doc.dart' as doc_model;
import '../../../core/models/canvas_layer.dart';

import '../render/renderer.dart';
import 'glow_blend.dart' as gb;
import 'dart:math' as math;

import 'canvas_state.dart';

enum SymmetryMode { off, mirrorV, mirrorH, quad }

final canvasControllerProvider =
    ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

/// Internal: where a stroke lives in the layer stack.
/// This lets undo/redo stay stable even if you reorder layers.
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

class CanvasController extends ChangeNotifier {
  CanvasController() {
    gb.GlowBlendState.I.addListener(_handleBlendChanged);
  }

  final ValueNotifier<int> repaint = ValueNotifier<int>(0);

  SymmetryMode symmetry = SymmetryMode.off;

  // Current brush
  String brushId = Brush.liquidNeon.id;

  // Palette slots policy: free=8; we can raise to 24/32 for premium later.
  int paletteSlots = 8;

  // Palette list (we'll only render first `paletteSlots`)
  final List<int> palette = [
    0xFF00FFFF, // cyan
    0xFFFF00FF, // magenta
    0xFFFFFF00, // yellow
    0xFFFF6EFF, // pink neon
    0xFF80FF00, // lime
    0xFFFFA500, // orange
    0xFF00FF9A, // mint
    0xFF9A7BFF, // violet
    // extra prepared slots for premium
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

  // ✅ Renderer now uses controller background (and preserves Multiply default)
  late final Renderer _renderer = Renderer(
    repaint,
    () => symmetry,
  );

  /// Flattened strokes for save/export/etc.
  List<Stroke> get strokes => List.unmodifiable(_state.allStrokes);

  /// Expose layers & active layer for UI / tools.
  List<CanvasLayer> get layers => List.unmodifiable(_state.layers);
  String get activeLayerId => _state.activeLayerId;
  CanvasLayer get activeLayer => _state.activeLayer;

  int color = 0xFF00FFFF; // default cyan
  double brushSize = 10.0;

  /// Canvas background colour (ARGB). Default black.
  int backgroundColor = 0xFF000000;
  bool _hasCustomBackground = false;
  bool get hasCustomBackground => _hasCustomBackground;

  /// How solid the inner stroke core is (0..1).
  double coreOpacity = 0.86;

  // Simple glow – base 0.3 (30%)
  double _brushGlow = 0.3;
  double get brushGlow => _brushGlow;

  // Multi-glow controls (0..1)
  double glowRadius = 0.3;
  double glowOpacity = 1.0;
  double glowBrightness = 0.3;

  /// If true, glow radius scales with brush size when rendering.
  bool glowRadiusScalesWithSize = false;

  // Whether the HUD is in "advanced glow" mode.
  bool _advancedGlowEnabled = false;
  bool get advancedGlowEnabled => _advancedGlowEnabled;

  // Advanced glow saved settings
  double _savedAdvancedGlowRadius = 15.0 / 300.0;
  double _savedAdvancedGlowBrightness = 50.0 / 100.0;
  double _savedAdvancedGlowOpacity = 1.0;

  // Store the user's simple-glow setting when switching modes
  double _savedSimpleGlow = 0.3;

  CanvasState _state = CanvasState.initial();

  Stroke? _current;
  int _startMs = 0;

  int? _activePointerId;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Renderer get painter => _renderer;

  /// When true, blend mode/intensity changes should *not* mark the doc dirty.
  /// Used when restoring state from a document or creating a new one.
  bool _suppressBlendDirty = false;

  /// Stroke history for undo/redo – uses logical locations, not visual order.
  final List<_StrokeLocation> _history = [];
  final List<_StrokeLocation> _redoLocations = [];

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

  void _recordStrokeCreation(Stroke s) {
    // Find where this stroke actually ended up in the layer tree.
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
          // Any new stroke wipes redo history.
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
    final layers = _state.layers;
    for (final layer in layers) {
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
  // BRUSH / GLOW / BACKGROUND
  // ---------------------------------------------------------------------------

  /// Legacy single-glow setter used by older UI.
  void setBrushGlow(double value) {
    final v = value.clamp(0.0, 1.0);

    glowRadius = v;
    glowOpacity = 1.0;

    // brightness scales 0 → 1.0
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

  /// Set the canvas background colour.
  void setBackgroundColor(int value) {
    backgroundColor = value;
    _hasCustomBackground = true;
    _hasUnsavedChanges = true;

    // Force repaint immediately (background is painted by renderer now)
    _tick();
    notifyListeners();
  }

  /// ✅ Correct advanced/simple glow behaviour
  void setAdvancedGlowEnabled(bool value) {
    if (_advancedGlowEnabled == value) return;

    if (value) {
      // Turning advanced ON
      _savedSimpleGlow = brushGlow; // save user's last simple glow

      glowRadius = _savedAdvancedGlowRadius.clamp(0.0, 1.0);
      glowBrightness = _savedAdvancedGlowBrightness.clamp(0.0, 1.0);
      glowOpacity = _savedAdvancedGlowOpacity.clamp(0.0, 1.0);

      _recomputeBrushGlow();
    } else {
      // Turning advanced OFF
      _savedAdvancedGlowRadius = glowRadius.clamp(0.0, 1.0);
      _savedAdvancedGlowBrightness = glowBrightness.clamp(0.0, 1.0);
      _savedAdvancedGlowOpacity = glowOpacity.clamp(0.0, 1.0);

      // Restore user's simple glow instead of forcing defaults
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
  // LAYER MANAGEMENT
  // ---------------------------------------------------------------------------

  /// Set the active layer for drawing by id.
  void setActiveLayer(String id) {
    if (id == _state.activeLayerId) return;
    final exists = _state.layers.any((l) => l.id == id);
    if (!exists) return;
    _state = _state.copyWith(activeLayerId: id);
    notifyListeners();
  }

  /// Create a new layer on top, with one empty group.
  /// Returns the new layer id.
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

    _renderer.rebuildFrom(_state.allStrokes);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
    return id;
  }

  /// Remove a layer by id. We never allow removing the last layer.
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

    // Drop any history entries that referenced this layer.
    _history.removeWhere((loc) => loc.layerId == id);
    _redoLocations.removeWhere((loc) => loc.layerId == id);

    _renderer.rebuildFrom(_state.allStrokes);
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

    _renderer.rebuildFrom(_state.allStrokes);
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

  /// Set layer position (X/Y) in canvas space.
  void setLayerPosition(String id, double x, double y) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    final oldT = layer.transform;

    final newT = oldT.copyWith(
      position: Offset(x, y),
    );

    layers[idx] = layer.copyWith(transform: newT);
    _state = _state.copyWith(layers: layers);

    _renderer.rebuildFrom(_state.allStrokes);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  ///Set layer opacity (0..1).
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

    _renderer.rebuildFrom(_state.allStrokes);
    _tick();
    notifyListeners();
  }

  /// Set layer rotation in **degrees** from the UI.
  void setLayerRotationDegrees(String id, double degrees) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    final oldT = layer.transform;

    final double radians = degrees * math.pi / 180.0;

    final newT = oldT.copyWith(
      rotation: radians,
    );

    layers[idx] = layer.copyWith(transform: newT);
    _state = _state.copyWith(layers: layers);

    _renderer.rebuildFrom(_state.allStrokes);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  /// Set layer scale (uniform).
  void setLayerScale(String id, double scale) {
    final idx = _state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;

    final clamped = scale.clamp(0.1, 5.0);

    final layers = List<CanvasLayer>.from(_state.layers);
    final layer = layers[idx];
    final oldT = layer.transform;

    final newT = oldT.copyWith(
      scale: clamped.toDouble(),
    );

    layers[idx] = layer.copyWith(transform: newT);
    _state = _state.copyWith(layers: layers);

    _renderer.rebuildFrom(_state.allStrokes);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  /// Reorder layers by internal index.
  /// 0 = bottom-most layer, last = top-most layer.
  void moveLayer(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;

    final layers = List<CanvasLayer>.from(_state.layers);
    if (fromIndex < 0 ||
        fromIndex >= layers.length ||
        toIndex < 0 ||
        toIndex >= layers.length) {
      return;
    }

    final moved = layers.removeAt(fromIndex);
    layers.insert(toIndex, moved);

    _state = _state.copyWith(layers: layers);

    _renderer.rebuildFrom(_state.allStrokes);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  /// Reorder layers to exactly match [orderedIds].
  /// Length must equal current layers length and IDs must match.
  void reorderLayersByIds(List<String> orderedIds) {
    if (orderedIds.length != _state.layers.length) return;

    final map = {
      for (final l in _state.layers) l.id: l,
    };

    final newLayers = <CanvasLayer>[];
    for (final id in orderedIds) {
      final layer = map[id];
      if (layer == null) {
        return;
      }
      newLayers.add(layer);
    }

    _state = _state.copyWith(layers: newLayers);

    _renderer.rebuildFrom(_state.allStrokes);
    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // DRAWING FLOW
  // ---------------------------------------------------------------------------

  void pointerDown(int pointer, Offset pos) {
    if (_activePointerId != null) return;

    if (activeLayer.locked) {
      return;
    }

    _activePointerId = pointer;

    _startMs = DateTime.now().millisecondsSinceEpoch;
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
      points: [PointSample(pos.dx, pos.dy, 0)],
      symmetryId: _symmetryId(symmetry),
    );
  }

  void pointerMove(int pointer, Offset pos) {
    if (_activePointerId != pointer) return;
    final s = _current;
    if (s == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final t = now - _startMs;

    s.points.add(PointSample(pos.dx, pos.dy, t));
    _renderer.updateStroke(s);
    _tick();
  }

  void pointerUp(int pointer) {
    if (_activePointerId != pointer) return;
    _activePointerId = null;

    final s = _current;
    if (s == null) return;

    _current = null;
    _renderer.commitStroke(s);

    _state = _addStrokeToActiveLayer(_state, s);
    _recordStrokeCreation(s);

    _hasUnsavedChanges = true;
    _tick();
    notifyListeners();
  }

  CanvasState _addStrokeToActiveLayer(
    CanvasState state,
    Stroke stroke,
  ) {
    if (state.layers.isEmpty) {
      final fresh = CanvasState.initial();
      return _addStrokeToActiveLayer(fresh, stroke);
    }

    final int layerIndex = state.layers.indexWhere(
      (l) => l.id == state.activeLayerId,
    );
    final int targetLayerIndex = layerIndex >= 0 ? layerIndex : 0;
    final CanvasLayer layer = state.layers[targetLayerIndex];

    if (layer.locked) {
      return state;
    }

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
      return state.copyWith(
        layers: newLayers,
      );
    }

    final groups = List<StrokeGroup>.from(layer.groups);
    final firstGroup = groups.first;
    final updatedGroup = firstGroup.copyWith(
      strokes: [...firstGroup.strokes, stroke],
    );
    groups[0] = updatedGroup;

    final newLayer = layer.copyWith(groups: groups);
    final newLayers = List<CanvasLayer>.from(state.layers);
    newLayers[targetLayerIndex] = newLayer;

    return state.copyWith(
      layers: newLayers,
    );
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

    _renderer.rebuildFrom(_state.allStrokes);
    _tick();
    notifyListeners();
  }

  void newDocument() {
    _state = CanvasState.initial();
    _current = null;
    _activePointerId = null;
    _hasUnsavedChanges = false;

    _history.clear();
    _redoLocations.clear();

    backgroundColor = 0xFF000000;
    _hasCustomBackground = false;

    _suppressBlendDirty = true;
    gb.GlowBlendState.I.setMode(gb.GlowBlend.additive);

    _renderer.rebuildFrom(_state.allStrokes);
    _tick();
    notifyListeners();
  }

  void markSaved() {
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // UNDO / REDO (history-based, stable under layer reordering)
  // ---------------------------------------------------------------------------

  void undo() {
    if (_history.isEmpty) return;

    final lastLoc = _history.removeLast();

    final layers = List<CanvasLayer>.from(_state.layers);
    final layerIndex = layers.indexWhere((l) => l.id == lastLoc.layerId);
    if (layerIndex == -1) {
      return;
    }

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
    if (strokeIndex == -1) {
      return;
    }

    final removed = strokes.removeAt(strokeIndex);

    groups[lastLoc.groupIndex] = group.copyWith(strokes: strokes);
    layers[layerIndex] = layer.copyWith(groups: groups);

    final newRedo = List<Stroke>.from(_state.redoStack)..add(removed);

    _state = _state.copyWith(
      layers: layers,
      redoStack: newRedo,
    );

    _redoLocations.add(lastLoc);

    _renderer.rebuildFrom(_state.allStrokes);
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
    if (layerIndex == -1) {
      return;
    }

    final layer = layers[layerIndex];
    if (layer.locked) {
      return;
    }

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

    _renderer.rebuildFrom(_state.allStrokes);
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

    _renderer.rebuildFrom(_state.allStrokes);
    _tick();
    notifyListeners();
  }

  @override
  void dispose() {
    gb.GlowBlendState.I.removeListener(_handleBlendChanged);
    super.dispose();
  }
}
