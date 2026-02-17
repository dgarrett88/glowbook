// lib/features/canvas/state/lfo_editor_types.dart

/// UI/controller shared curve mode (editor-side).
enum CurveMode { bulge, bend }

/// Shared editor node payload (normalized editor space)
/// x: 0..1
/// y: -1..1  (IMPORTANT: shared type uses core-friendly y range)
/// bias: 0..1
/// bulgeAmt: -1..1 (editor contract)  -> controller will map to core range
/// bendY: -1..1
class LfoEditorNode {
  final double x;
  final double y;
  final double bias;
  final double bulgeAmt;
  final double bendY;

  const LfoEditorNode({
    required this.x,
    required this.y,
    this.bias = 0.5,
    this.bulgeAmt = 0.0,
    double? bendY,
  }) : bendY = bendY ?? y;

  LfoEditorNode copyWith({
    double? x,
    double? y,
    double? bias,
    double? bulgeAmt,
    double? bendY,
  }) {
    return LfoEditorNode(
      x: x ?? this.x,
      y: y ?? this.y,
      bias: bias ?? this.bias,
      bulgeAmt: bulgeAmt ?? this.bulgeAmt,
      bendY: bendY ?? this.bendY,
    );
  }
}

class LfoEditorCurve {
  final CurveMode mode;
  final List<LfoEditorNode> nodes;

  const LfoEditorCurve({
    required this.mode,
    required this.nodes,
  });
}
