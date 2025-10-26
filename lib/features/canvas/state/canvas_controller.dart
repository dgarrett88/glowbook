import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/brush.dart';
import '../../../core/models/stroke.dart';
import '../render/renderer.dart';
import 'canvas_state.dart';

final canvasControllerProvider = ChangeNotifierProvider<CanvasController>((ref) => CanvasController());

class CanvasController extends ChangeNotifier {
  CanvasController();

  // This ValueNotifier drives the CustomPainter's repaint.
  final ValueNotifier<int> repaint = ValueNotifier<int>(0);

  // IMPORTANT: Renderer must listen to *this* repaint notifier.
  late final Renderer _renderer = Renderer(repaint);

  // Tool state
  int color = 0xFFFF66FF;
  double brushSize = 10.0;
  double brushGlow = 0.7;

  // Strokes
  CanvasState _state = const CanvasState();
  Stroke? _current;
  int _startMs = 0;

  Renderer get painter => _renderer;

  void _tick() {
    // Bump the repaint notifier so the painter redraws.
    repaint.value++;
  }

  void setBrushSize(double v){ brushSize = v; notifyListeners(); }
  void setColor(int c){ color = c; notifyListeners(); }

  Future<void> pickColor(BuildContext context) async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick color'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _colorBox(ctx, Colors.cyan),
            _colorBox(ctx, const Color(0xFFFF00FF)), // magenta
            _colorBox(ctx, Colors.yellow),
            _colorBox(ctx, Colors.white),
          ],
        ),
      ),
    );
    if (chosen != null) setColor(chosen.toARGB32());
  }

  Widget _colorBox(BuildContext ctx, Color c) => InkWell(
    onTap: ()=> Navigator.pop(ctx, c),
    child: Container(width: 28, height: 28, margin: const EdgeInsets.all(6), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
  );

  // Pointer API: (pointerId, Offset)
  void pointerDown(int pointer, Offset pos){
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _current = Stroke(
      id: 's${_state.strokes.length}_$_startMs',
      color: color,
      size: brushSize,
      glow: brushGlow,
      brushId: Brush.liquidNeon.id,
      seed: 0,
      points: [PointSample(pos.dx, pos.dy, 0)],
    );
    _renderer.beginStroke(_current!);
    _tick();
  }

  void pointerMove(int pointer, Offset pos){
    final s = _current;
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = now - _startMs;
    s.points.add(PointSample(pos.dx, pos.dy, t));
    _renderer.updateStroke(s);
    _tick();
  }

  void pointerUp(int pointer){
    final s = _current;
    if (s == null) return;
    _current = null;
    _renderer.commitStroke(s);
    _state = _state.copyWith(strokes: [..._state.strokes, s], redoStack: []);
    _tick();
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
