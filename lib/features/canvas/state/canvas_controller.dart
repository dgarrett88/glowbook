import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/brush.dart';
import '../../../core/models/stroke.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_doc.dart' as doc_model;
import '../render/renderer.dart';
import 'glow_blend.dart' as gb;

import 'canvas_state.dart';

enum SymmetryMode { off, mirrorV, mirrorH, quad }

final canvasControllerProvider =
    ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

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

  late final Renderer _renderer = Renderer(repaint, () => symmetry);

  List<Stroke> get strokes => List.unmodifiable(_state.strokes);

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

  CanvasState _state = const CanvasState();

  Stroke? _current;
  int _startMs = 0;

  int? _activePointerId;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Renderer get painter => _renderer;

  /// When true, blend mode/intensity changes should *not* mark the doc dirty.
  /// Used when restoring state from a document or creating a new one.
  bool _suppressBlendDirty = false;

  void _recomputeBrushGlow() {
    final r = glowRadius.clamp(0.0, 1.0);
    final o = glowOpacity.clamp(0.0, 1.0);
    _brushGlow = r * o;
  }

  /// Legacy single-glow setter used by older UI.
  void setBrushGlow(double value) {
    final v = value.clamp(0.0, 1.0);

    glowRadius = v;
    glowOpacity = 1.0;

    // brightness scales 0 → 1.0
    double b = (v * 1.0).clamp(0.0, 1.0);
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

  void _tick() {
    repaint.value++;
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

  void pointerDown(int pointer, Offset pos) {
    if (_activePointerId != null) return;
    _activePointerId = pointer;

    _startMs = DateTime.now().millisecondsSinceEpoch;
    _current = Stroke(
      id: 's${_state.strokes.length}_$_startMs',
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

    _state = _state.copyWith(
      strokes: [..._state.strokes, s],
      redoStack: [],
    );

    _hasUnsavedChanges = true;
    _tick();
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
      default:
        return 'off';
    }
  }

  void loadFromBundle(CanvasDocumentBundle bundle) {
    _state = CanvasState(
      strokes: List<Stroke>.from(bundle.strokes),
      redoStack: const [],
    );
    _current = null;
    _activePointerId = null;
    _hasUnsavedChanges = false;

    // Restore background from doc metadata (solid colour only).
    final bg = bundle.doc.background;
    if (bg.type == doc_model.BackgroundType.solid &&
        bg.params['color'] is int) {
      backgroundColor = bg.params['color'] as int;
      _hasCustomBackground = true;
    } else {
      backgroundColor = 0xFF000000;
      _hasCustomBackground = false;
    }

    // Restore blend mode, but don't mark as dirty.
    _suppressBlendDirty = true;
    final key = bundle.doc.blendModeKey;
    final mode = gb.glowBlendFromKey(key);
    gb.GlowBlendState.I.setMode(mode);

    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  void newDocument() {
    _state = const CanvasState();
    _current = null;
    _activePointerId = null;
    _hasUnsavedChanges = false;

    // Reset background to default black; not considered a "change".
    backgroundColor = 0xFF000000;
    _hasCustomBackground = false;

    // New documents start in Additive, but that shouldn't mark them dirty.
    _suppressBlendDirty = true;
    gb.GlowBlendState.I.setMode(gb.GlowBlend.additive);

    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  void markSaved() {
    _hasUnsavedChanges = false;
  }

  void undo() {
    if (_state.strokes.isEmpty) return;

    final last = _state.strokes.last;

    _state = _state.copyWith(
      strokes: List.of(_state.strokes)..removeLast(),
      redoStack: List.of(_state.redoStack)..add(last),
    );

    _renderer.rebuildFrom(_state.strokes);
    _hasUnsavedChanges = true;
    _tick();
  }

  void redo() {
    if (_state.redoStack.isEmpty) return;

    final s = _state.redoStack.last;

    _state = _state.copyWith(
      strokes: List.of(_state.strokes)..add(s),
      redoStack: List.of(_state.redoStack)..removeLast(),
    );

    _renderer.rebuildFrom(_state.strokes);
    _hasUnsavedChanges = true;
    _tick();
  }

  void setGlowRadiusScalesWithSize(bool value) {
    if (glowRadiusScalesWithSize == value) return;
    glowRadiusScalesWithSize = value;
    notifyListeners();
  }

  void _handleBlendChanged() {
    if (_suppressBlendDirty) {
      // This change came from restoring state / new document setup.
      _suppressBlendDirty = false;
    } else {
      // User-driven change → mark as unsaved.
      _hasUnsavedChanges = true;
    }

    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  @override
  void dispose() {
    gb.GlowBlendState.I.removeListener(_handleBlendChanged);
    super.dispose();
  }
}
