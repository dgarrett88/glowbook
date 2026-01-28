// lib/features/canvas/history/history_stack.dart
import 'history_command.dart';

class HistoryStack {
  final List<HistoryCommand> _undo = [];
  final List<HistoryCommand> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void push(HistoryCommand cmd) {
    _undo.add(cmd);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final cmd = _undo.removeLast();
    cmd.undo();
    _redo.add(cmd);
  }

  void redo() {
    if (_redo.isEmpty) return;
    final cmd = _redo.removeLast();
    cmd.apply();
    _undo.add(cmd);
  }
}
