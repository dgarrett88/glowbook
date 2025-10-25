import '../../../core/models/stroke.dart';

class CanvasState {
  final List<Stroke> strokes;
  final List<Stroke> redoStack;

  const CanvasState({this.strokes = const [], this.redoStack = const []});

  CanvasState copyWith({List<Stroke>? strokes, List<Stroke>? redoStack}) =>
      CanvasState(
        strokes: strokes ?? this.strokes,
        redoStack: redoStack ?? this.redoStack,
      );
}
