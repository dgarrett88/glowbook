// lib/features/canvas/history/history_command.dart

typedef VoidFn = void Function();

abstract class HistoryCommand {
  String get label;
  void apply();
  void undo();
}

class LambdaCommand implements HistoryCommand {
  final String _label;
  final VoidFn _apply;
  final VoidFn _undo;

  LambdaCommand({
    required String label,
    required VoidFn apply,
    required VoidFn undo,
  })  : _label = label,
        _apply = apply,
        _undo = undo;

  @override
  String get label => _label;

  @override
  void apply() => _apply();

  @override
  void undo() => _undo();
}

class CompoundCommand implements HistoryCommand {
  final String _label;
  final List<HistoryCommand> _commands;

  CompoundCommand(this._label, this._commands);

  @override
  String get label => _label;

  @override
  void apply() {
    for (final c in _commands) {
      c.apply();
    }
  }

  @override
  void undo() {
    for (final c in _commands.reversed) {
      c.undo();
    }
  }
}
