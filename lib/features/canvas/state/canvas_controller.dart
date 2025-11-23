import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/brush.dart';
import '../../../core/models/stroke.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../render/renderer.dart';
import 'canvas_state.dart';

enum SymmetryMode { off, mirrorV, mirrorH, quad }

final canvasControllerProvider =
    ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

enum GlowBlend { additive, screen }

class CanvasController extends ChangeNotifier {
  CanvasController();

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

  int color = 0xFFFF66FF;
  double brushSize = 10.0;

  /// How solid the inner stroke core is (0..1).
  double coreOpacity = 0.86;

  // Legacy effective glow value (0..1) used by existing brushes.
  // This is derived from the three multi-glow controls so older code
  // that only reads [brushGlow] keeps working.
  double _brushGlow = 0.7;
  double get brushGlow => _brushGlow;

  // Multi-glow controls (0..1). These are the source of truth; [_brushGlow]
  // is recomputed from them.
  double glowRadius = 0.7;
  double glowOpacity = 1.0;
  double glowBrightness = 0.7;

  // Whether the HUD is in "advanced glow" mode.
  bool _advancedGlowEnabled = false;
  bool get advancedGlowEnabled => _advancedGlowEnabled;

  // Saved advanced glow settings so they survive when the user
  // turns advanced OFF, plays with the simple Glow slider, and
  // later turns advanced back ON again.
  double _savedAdvancedGlowRadius = 0.7;
  double _savedAdvancedGlowBrightness = 0.8;
  double _savedAdvancedGlowOpacity = 1.0;

  void _recomputeBrushGlow() {
    // Radius = how far the glow spreads
    // Opacity = master fade
    final r = glowRadius.clamp(0.0, 1.0);
    final o = glowOpacity.clamp(0.0, 1.0);

    // Brightness does NOT affect geometry – only colour inside the brushes.
    _brushGlow = r * o;
  }

  /// Legacy single-glow setter used by older UI.
  /// When called, we interpret this as "link all glow controls" and set
  /// radius and brightness to the same value with full opacity.
  void setBrushGlow(double value) {
    final v = value.clamp(0.0, 1.0);
    glowRadius = v;
    glowBrightness = v;
    glowOpacity = 1.0;
    _recomputeBrushGlow();
    notifyListeners();
  }

  void setGlowRadius(double value) {
    glowRadius = value.clamp(0.0, 1.0);

    // If we're in advanced mode, keep the saved advanced radius in sync.
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

  void setAdvancedGlowEnabled(bool value) {
    if (_advancedGlowEnabled == value) return;

    if (value) {
      // Turning advanced ON:
      // Restore the last advanced settings into the live glow fields,
      // so the sliders show what the user previously configured.
      glowRadius = _savedAdvancedGlowRadius.clamp(0.0, 1.0);
      glowBrightness = _savedAdvancedGlowBrightness.clamp(0.0, 1.0);
      glowOpacity = _savedAdvancedGlowOpacity.clamp(0.0, 1.0);
      _recomputeBrushGlow();
    } else {
      // Turning advanced OFF:
      // 1) Snapshot the current advanced settings so we can restore them
      //    next time advanced is enabled.
      _savedAdvancedGlowRadius = glowRadius.clamp(0.0, 1.0);
      _savedAdvancedGlowBrightness = glowBrightness.clamp(0.0, 1.0);
      _savedAdvancedGlowOpacity = glowOpacity.clamp(0.0, 1.0);

      // 2) Reset live glow fields back to the default "Liquid Neon" style.
      glowRadius = 0.7;
      glowBrightness = 0.7;
      glowOpacity = 1.0;

      _recomputeBrushGlow();
    }

    _advancedGlowEnabled = value;
    notifyListeners();
  }

  CanvasState _state = const CanvasState();

  Stroke? _current;
  int _startMs = 0;

  // Track single active pointer id to prevent 2-finger line connection.
  int? _activePointerId;

  // Tracks whether the canvas has changed since it was opened/created/saved.
  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Renderer get painter => _renderer;

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
    // If a stroke is in progress, ignore any extra fingers.
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
      seed: 0,
      points: [PointSample(pos.dx, pos.dy, 0)],
      symmetryId: _symmetryId(symmetry),
    );
  }

  void pointerMove(int pointer, Offset pos) {
    if (_activePointerId != pointer) return; // ignore other pointers
    final s = _current;
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = now - _startMs;
    s.points.add(PointSample(pos.dx, pos.dy, t));
    _renderer.updateStroke(s);
    _tick();
  }

  void pointerUp(int pointer) {
    if (_activePointerId != pointer) return; // ignore irrelevant ups
    _activePointerId = null;
    final s = _current;
    if (s == null) return;
    _current = null;
    _renderer.commitStroke(s);
    _state = _state.copyWith(strokes: [..._state.strokes, s], redoStack: []);
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
        return 'off';
    }
  }

  /// Clears current strokes/redos and starts a fresh blank canvas.
  void loadFromBundle(CanvasDocumentBundle bundle) {
    _state = CanvasState(
      strokes: List<Stroke>.from(bundle.strokes),
      redoStack: const [],
    );
    _current = null;
    _activePointerId = null;
    _hasUnsavedChanges = false;
    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  void newDocument() {
    _state = const CanvasState();
    _current = null;
    _activePointerId = null;
    _hasUnsavedChanges = false;
    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  // Mark the current state as saved so callers can skip
  // save/discard prompts when nothing has changed.
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
}
