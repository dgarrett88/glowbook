import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/brush.dart';
import '../../../core/models/stroke.dart';
import '../render/renderer.dart';
import 'canvas_state.dart';

enum SymmetryMode { off, mirrorV, mirrorH, quad }

final canvasControllerProvider = ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

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

  int color = 0xFFFF66FF;
  double brushSize = 10.0;
  double brushGlow = 0.7;

  CanvasState _state = const CanvasState();
  Stroke? _current;
  int _startMs = 0;

  // Track single active pointer id to prevent 2-finger line connection.
  int? _activePointerId;

  Renderer get painter => _renderer;

  void _tick() { repaint.value++; }

  void setBrushSize(double v){ brushSize = v; notifyListeners(); }
  void setColor(int c){ color = c; notifyListeners(); }
  void setBrush(String id){ brushId = id; notifyListeners(); }

  void setSymmetry(SymmetryMode m){
    symmetry = m;
    _tick();
    notifyListeners();
  }

  void cycleSymmetry(){
    switch(symmetry){
      case SymmetryMode.off: setSymmetry(SymmetryMode.mirrorV); break;
      case SymmetryMode.mirrorV: setSymmetry(SymmetryMode.mirrorH); break;
      case SymmetryMode.mirrorH: setSymmetry(SymmetryMode.quad); break;
      case SymmetryMode.quad: setSymmetry(SymmetryMode.off); break;
    }
  }

  void pointerDown(int pointer, Offset pos){
    // If a stroke is in progress, ignore any extra fingers.
    if (_activePointerId != null) return;
    _activePointerId = pointer;

    _startMs = DateTime.now().millisecondsSinceEpoch;
    _current = Stroke(
      id: 's${_state.strokes.length}_$_startMs',
      color: color,
      size: brushSize,
      glow: brushGlow,
      brushId: brushId,
      seed: 0,
      points: [PointSample(pos.dx, pos.dy, 0)],
      symmetryId: _symmetryId(symmetry),
    );
    _renderer.beginStroke(_current!);
    _tick();
  }

  void pointerMove(int pointer, Offset pos){
    if (_activePointerId != pointer) return; // ignore other pointers
    final s = _current;
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = now - _startMs;
    s.points.add(PointSample(pos.dx, pos.dy, t));
    _renderer.updateStroke(s);
    _tick();
  }

  void pointerUp(int pointer){
    if (_activePointerId != pointer) return; // ignore irrelevant ups
    _activePointerId = null;
    final s = _current;
    if (s == null) return;
    _current = null;
    _renderer.commitStroke(s);
    _state = _state.copyWith(strokes: [..._state.strokes, s], redoStack: []);
    _tick();
  }

  String _symmetryId(SymmetryMode m){
    switch(m){
      case SymmetryMode.mirrorV: return 'mirrorV';
      case SymmetryMode.mirrorH: return 'mirrorH';
      case SymmetryMode.quad: return 'quad';
      case SymmetryMode.off: return 'off';
    }
  }

  void undo(){
    if (_state.strokes.isEmpty) return;
    final last = _state.strokes.last;
    _state = _state.copyWith(
      strokes: List.of(_state.strokes)..removeLast(),
      redoStack: List.of(_state.redoStack)..add(last),
    );
    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  void redo(){
    if (_state.redoStack.isEmpty) return;
    final s = _state.redoStack.last;
    _state = _state.copyWith(
      strokes: List.of(_state.strokes)..add(s),
      redoStack: List.of(_state.redoStack)..removeLast(),
    );
    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }
}
