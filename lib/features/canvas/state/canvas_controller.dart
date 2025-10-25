import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/brush.dart';
import '../render/renderer.dart';
import 'canvas_state.dart';
import 'stroke_recorder.dart';

final canvasControllerProvider = ChangeNotifierProvider<CanvasController>((ref) {
  return CanvasController();
});

class CanvasController extends ChangeNotifier {
  final StrokeRecorder _rec = StrokeRecorder();

  // repaint driver
  final ValueNotifier<int> repaint = ValueNotifier<int>(0);
  late final Renderer _renderer = Renderer(repaint);

  CanvasState _state = const CanvasState();
  CanvasState get state => _state;

  CustomPainter get painter => _renderer;

  String brushId = Brush.liquidNeon.id;
  double brushSize = Brush.liquidNeon.baseSize;
  double brushGlow = Brush.liquidNeon.glow;
  int color = 0xFFFF77FF;

  // Settings
  bool dynamicThickness = true;
  void setDynamicThickness(bool v) { dynamicThickness = v; notifyListeners(); }

  // Single active pointer tracking
  int? _activePointerId;
  void pointerDown(int id, Offset pos) {
    if (_activePointerId != null) return; // ignore extra fingers
    _activePointerId = id;
    onPointerDown(pos);
  }
  void pointerMove(int id, Offset pos) {
    if (id != _activePointerId) return;
    onPointerMove(pos);
  }
  void pointerUp(int id) {
    if (id != _activePointerId) return;
    onPointerUp();
    _activePointerId = null;
  }

  // Drawing hooks
  void onPointerDown(Offset pos) {
    _rec.begin(pos, brushId: brushId, color: color, size: brushSize, glow: brushGlow);
    _renderer.beginStroke(_rec.current!);
    _tick();
  }

  void onPointerMove(Offset pos) {
    _rec.add(pos);
    _renderer.updateStroke(_rec.current!);
    _tick();
  }

  void onPointerUp() {
    final done = _rec.end();
    if (done != null) {
      _state = CanvasState(
        strokes: [..._state.strokes, done],
        redoStack: const [],
      );
      _renderer.commitStroke(done);
      _tick();
    }
  }

  void undo() {
    if (_state.strokes.isEmpty) return;
    final last = _state.strokes.last;
    _state = _state.copyWith(
      strokes: List.of(_state.strokes)..removeLast(),
      redoStack: List.of(_state.redoStack)..add(last),
    );
    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  void redo() {
    if (_state.redoStack.isEmpty) return;
    final last = _state.redoStack.last;
    _state = _state.copyWith(
      strokes: List.of(_state.strokes)..add(last),
      redoStack: List.of(_state.redoStack)..removeLast(),
    );
    _renderer.rebuildFrom(_state.strokes);
    _tick();
  }

  void setBrushSize(double v) {
    brushSize = v;
    notifyListeners();
  }

  Future<void> pickColor(BuildContext context) async {
    final newColor = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              0xFFFF77FF, 0xFF5DE0E6, 0xFFEE6DFA, 0xFFFFC857, 0xFF8AFF80, 0xFF7FB2FF
            ].map((c) => GestureDetector(
              onTap: () => Navigator.of(ctx).pop(c),
              child: Container(width: 28, height: 28, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle)),
            )).toList(),
          ),
        );
      },
    );
    if (newColor != null) {
      color = newColor;
      notifyListeners();
    }
  }

  void _tick() => repaint.value++;
}
