import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/canvas_controller.dart' as canvas_state;
import '../../state/lfo_editor_types.dart';
import 'package:glowbook/core/models/lfo_curve_math.dart';
import 'package:glowbook/core/models/lfo.dart'; // if you need LfoCurveMode/LfoNode

class LfoVisualEditor extends ConsumerStatefulWidget {
  const LfoVisualEditor({
    super.key,
    required this.lfoId,
    this.onInteractionChanged,

    // persisted curve
    this.initialMode = CurveMode.bulge,
    this.initialNodes,

    // persist curve changes to controller
    this.onCurveChanged,
  });

  final String lfoId;
  final ValueChanged<bool>? onInteractionChanged;

  /// Shared types:
  /// - x 0..1
  /// - y -1..1
  final CurveMode initialMode;
  final List<LfoEditorNode>? initialNodes;

  final ValueChanged<LfoEditorCurve>? onCurveChanged;

  @override
  ConsumerState<LfoVisualEditor> createState() => _LfoVisualEditorState();
}

class _LfoNode {
  Offset p; // internal normalized editor space: x 0..1, y 0..1

  double bias; // 0.0..1.0 (segment-local X position of handle)
  double bulgeAmt; // internal: -2.5..2.5
  double bendY; // internal: 0..1

  _LfoNode(
    this.p, {
    this.bias = 0.5,
    this.bulgeAmt = 0.0,
    double? bendY,
  }) : bendY = bendY ?? p.dy;
}

enum _DragKind { none, node, handleAmt, handleCurve }

class _Hit {
  final bool isNode;
  final int index; // node index OR segment start index
  const _Hit.node(this.index) : isNode = true;
  const _Hit.handle(this.index) : isNode = false;
}

class _LfoVisualEditorState extends ConsumerState<LfoVisualEditor> {
  late CurveMode _mode;
  bool _lockedOrder = true; // default ON
  bool _linkEndpoints = false; // endpoints move independently by default

  late List<_LfoNode> _nodes;

  int? _selectedIndex;

  _DragKind _dragKind = _DragKind.none;
  int? _dragIndex; // node index OR segment index

  static const double _nodeHitRadiusPx = 28.0;
  static const double _handleHitRadiusPx = 24.0;
  static const double _endNodeHitRadiusPx = 35.0;

  // Graph padding so nodes/handles stay fully visible & easy to grab.
  static const double _graphPadPx = 8.0;

  static const double _bottomAssistZonePx = 26.0;
  static const double _bottomAssistBoostPx = 22.0;

  // Visuals
  static const double _nodeRadius = 8.0; // parent nodes
  static const double _handleRadius = 5.0;
  static const double _strokeWidth = 3.0;

  static const int _curveResolution = 140;

  // --- LONG PRESS CURVE DRAG ---
  static const Duration _longPressDelay = Duration(milliseconds: 100);
  static const double _curveDragSensitivity = .2;

  Timer? _lpTimer;
  bool _lpArmed = false;
  bool _lpActive = false;
  Offset? _lpStartLocal;
  double? _lpStartBulge;
  double? _lpStartBendY;
  int? _lpSeg;

  @override
  void initState() {
    super.initState();

    _mode = widget.initialMode;

    final init = widget.initialNodes;
    if (init != null && init.length >= 2) {
      _nodes = init.map((n) {
        // shared y (-1..1) -> internal y01 (0..1, top=0)
        final y01 = ((-n.y + 1.0) * 0.5).clamp(0.0, 1.0);
        final bend01 = ((-n.bendY + 1.0) * 0.5).clamp(0.0, 1.0);

        return _LfoNode(
          Offset(n.x.clamp(0.0, 1.0), y01),
          bias: n.bias.clamp(0.0, 1.0),
          // shared bulge (-1..1) -> internal (-2.5..2.5)
          bulgeAmt: (n.bulgeAmt.clamp(-1.0, 1.0) * 2.5),
          bendY: bend01,
        );
      }).toList();
    } else {
      _nodes = <_LfoNode>[
        _LfoNode(const Offset(0.0, 1.0), bendY: 1.0),
        _LfoNode(const Offset(1.0, 1.0), bendY: 1.0),
      ];
    }

    _ensureSortedAndSafe();

    // Emit once on load so controller can “adopt” the curve if needed.
    _emitCurve();

    // ✅ NEW: tell controller LFO editor is open (start ticker preview)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(canvas_state.canvasControllerProvider)
          .setLfoEditorPreviewActive(true);
    });
  }

  @override
  void dispose() {
    // ✅ NEW: tell controller LFO editor is closing (allow ticker to stop)
    ref
        .read(canvas_state.canvasControllerProvider)
        .setLfoEditorPreviewActive(false);

    _lpTimer?.cancel();
    super.dispose();
  }

  static Rect _graphRectFor(Size size) {
    final padX = _graphPadPx + _nodeRadius + 2.0;
    final padTop = _graphPadPx + _nodeRadius + 2.0;
    final padBottom = _graphPadPx + _nodeRadius + 2.0;

    return Rect.fromLTWH(
      padX,
      padTop,
      math.max(1.0, size.width - padX * 2),
      math.max(1.0, size.height - padTop - padBottom),
    );
  }

  Rect _graphRect(Size size) => _graphRectFor(size);

  void _emitCurve() {
    final cb = widget.onCurveChanged;
    if (cb == null) return;

    final nodes = _nodes.map((n) {
      // internal y01 -> shared y (-1..1)
      final y = (1.0 - (n.p.dy.clamp(0.0, 1.0) * 2.0)).clamp(-1.0, 1.0);
      final bendY = (1.0 - (n.bendY.clamp(0.0, 1.0) * 2.0)).clamp(-1.0, 1.0);

      return LfoEditorNode(
        x: n.p.dx.clamp(0.0, 1.0),
        y: y,
        bias: n.bias.clamp(0.0, 1.0),
        // internal (-2.5..2.5) -> shared (-1..1)
        bulgeAmt: (n.bulgeAmt / 2.5).clamp(-1.0, 1.0),
        bendY: bendY,
      );
    }).toList(growable: false);

    cb(LfoEditorCurve(mode: _mode, nodes: nodes));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TopBar(
              mode: _mode,
              lockedOrder: _lockedOrder,
              linkEndpoints: _linkEndpoints,
              onToggleMode: () {
                setState(() {
                  _mode = (_mode == CurveMode.bulge)
                      ? CurveMode.bend
                      : CurveMode.bulge;
                  _ensureSortedAndSafe();
                });
                _emitCurve();
              },
              onToggleLockedOrder: () {
                setState(() {
                  _lockedOrder = !_lockedOrder;
                  _ensureSortedAndSafe();
                });
                _emitCurve();
              },
              onToggleLinkEndpoints: () {
                setState(() {
                  _linkEndpoints = !_linkEndpoints;
                  if (_linkEndpoints) {
                    final y = _nodes.first.p.dy;
                    _nodes.first.p = Offset(0.0, y);
                    _nodes.last.p = Offset(1.0, y);
                  }
                });
                _emitCurve();
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, gc) {
                  final graphSize = Size(gc.maxWidth, gc.maxHeight);

                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F18),
                        border: Border.all(color: Colors.white10),
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                      ),
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) {
                          widget.onInteractionChanged?.call(true);

                          final hit = _hitTest(e.localPosition, graphSize);
                          if (hit == null) {
                            _cancelLongPress();
                            setState(() {
                              _dragKind = _DragKind.none;
                              _dragIndex = null;
                            });
                            return;
                          }

                          if (hit.isNode) {
                            _cancelLongPress();
                            setState(() {
                              _selectedIndex = hit.index;
                              _dragKind = _DragKind.node;
                              _dragIndex = hit.index;
                            });
                          } else {
                            _armLongPressForSegment(hit.index, e.localPosition);
                            setState(() {
                              _selectedIndex = null;
                              _dragKind = _DragKind.handleAmt;
                              _dragIndex = hit.index;
                            });
                          }
                        },
                        onPointerUp: (_) {
                          _cancelLongPress();
                          _dragKind = _DragKind.none;
                          _dragIndex = null;
                          widget.onInteractionChanged?.call(false);
                          setState(() {});
                        },
                        onPointerCancel: (_) {
                          _cancelLongPress();
                          _dragKind = _DragKind.none;
                          _dragIndex = null;
                          widget.onInteractionChanged?.call(false);
                          setState(() {});
                        },
                        child: _buildGestures(graphSize),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _armLongPressForSegment(int seg, Offset local) {
    _lpTimer?.cancel();
    _lpArmed = true;
    _lpActive = false;
    _lpStartLocal = local;
    _lpSeg = seg;

    if (seg >= 0 && seg < _nodes.length - 1) {
      _lpStartBulge = _nodes[seg].bulgeAmt;
      _lpStartBendY = _nodes[seg].bendY;
    } else {
      _lpStartBulge = null;
      _lpStartBendY = null;
    }

    _lpTimer = Timer(_longPressDelay, () {
      if (!_lpArmed) return;
      _lpActive = true;
      setState(() {
        _dragKind = _DragKind.handleCurve;
        _dragIndex = _lpSeg;
      });
    });
  }

  void _cancelLongPress() {
    _lpTimer?.cancel();
    _lpTimer = null;
    _lpArmed = false;
    _lpActive = false;
    _lpStartLocal = null;
    _lpStartBulge = null;
    _lpStartBendY = null;
    _lpSeg = null;
  }

  Widget _buildGestures(Size size) {
    // ✅ watch inside the method body
    final controller = ref.watch(canvas_state.canvasControllerProvider);
    final playhead01 = controller.lfoPlayhead01(widget.lfoId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,

      // Double tap add/remove node
      onDoubleTapDown: (d) {
        final hit = _hitTest(d.localPosition, size);

        // remove node
        if (hit != null && hit.isNode) {
          final idx = hit.index;
          if (idx == 0 || idx == _nodes.length - 1) return;

          setState(() {
            _nodes.removeAt(idx);
            _selectedIndex = null;
            _dragKind = _DragKind.none;
            _dragIndex = null;
            _ensureSortedAndSafe();
          });
          _emitCurve();
          return;
        }

        // add node
        final n = _toNorm(d.localPosition, size);
        final p = Offset(_clamp01(n.dx), _clamp01(n.dy));
        if (p.dx < 0.02 || p.dx > 0.98) return;

        setState(() {
          _nodes.add(_LfoNode(p, bendY: p.dy));
          _ensureSortedAndSafe();
          _selectedIndex = _closestNodeIndex(p);
        });
        _emitCurve();
      },

      onPanStart: (d) {
        final hit = _hitTest(d.localPosition, size);
        if (hit == null) return;

        setState(() {
          if (hit.isNode) {
            _selectedIndex = hit.index;
            _dragKind = _DragKind.node;
            _dragIndex = hit.index;
          } else {
            _selectedIndex = null;
            _dragKind = _DragKind.handleAmt;
            _dragIndex = hit.index;
          }
        });
      },

      onPanUpdate: (d) {
        final idx = _dragIndex;
        if (idx == null) return;

        // If we started moving before long press triggered, cancel it.
        if (_lpArmed && !_lpActive) {
          final start = _lpStartLocal;
          if (start != null) {
            final moved = (d.localPosition - start).distance;
            if (moved > 6.0) {
              _cancelLongPress();
            }
          }
        }

        // NODE DRAG
        if (_dragKind == _DragKind.node) {
          final n = _toNorm(d.localPosition, size);
          final next = Offset(_clamp01(n.dx), _clamp01(n.dy));

          // start endpoint
          if (idx == 0) {
            final dy = _clampNodeY(next.dy);
            _nodes[0].p = Offset(0.0, dy);
            if (_linkEndpoints) _nodes.last.p = Offset(1.0, dy);
            setState(() {});
            _emitCurve();
            return;
          }

          // end endpoint
          if (idx == _nodes.length - 1) {
            final dy = _clampNodeY(next.dy);
            _nodes.last.p = Offset(1.0, dy);
            if (_linkEndpoints) _nodes[0].p = Offset(0.0, dy);
            setState(() {});
            _emitCurve();
            return;
          }

          // locked order
          if (_lockedOrder) {
            final leftX = _nodes[idx - 1].p.dx;
            final rightX = _nodes[idx + 1].p.dx;
            final clampedX = next.dx.clamp(leftX, rightX);
            _nodes[idx].p = Offset(clampedX, next.dy);
            setState(() {});
            _emitCurve();
            return;
          }

          // free order
          _nodes[idx].p = next;
          _ensureSortedAndSafe();
          final newIdx = _closestNodeIndex(next);
          _dragIndex = newIdx;
          _selectedIndex = newIdx;

          setState(() {});
          _emitCurve();
          return;
        }

        // LONG PRESS CURVE DRAG
        if (_dragKind == _DragKind.handleCurve) {
          final seg = idx;
          if (seg < 0 || seg >= _nodes.length - 1) return;

          final start = _lpStartLocal;
          if (start == null) return;

          final dyPx = d.localPosition.dy - start.dy;
          final delta = (-dyPx / (size.height <= 0 ? 1.0 : size.height)) *
              _curveDragSensitivity;

          if (_mode == CurveMode.bulge) {
            final base = _lpStartBulge ?? _nodes[seg].bulgeAmt;
            final nextAmt = (base + delta * 6.0).clamp(-2.5, 2.5).toDouble();
            setState(() {
              _nodes[seg].bulgeAmt = nextAmt;
            });
          } else {
            final a = _nodes[seg];
            final b = _nodes[seg + 1];
            final minY = math.min(a.p.dy, b.p.dy);
            final maxY = math.max(a.p.dy, b.p.dy);

            final base = _lpStartBendY ?? a.bendY;
            final nextY = (base - delta).clamp(minY, maxY).toDouble();

            setState(() {
              a.bendY = nextY;
            });
          }

          _emitCurve();
          return;
        }

        // NORMAL HANDLE DRAG (bias + amt/bendY)
        if (_dragKind == _DragKind.handleAmt) {
          final seg = idx;
          if (seg < 0 || seg >= _nodes.length - 1) return;

          final a = _nodes[seg];
          final b = _nodes[seg + 1];

          final n = _toNorm(d.localPosition, size);

          final x0 = a.p.dx;
          final x1 = b.p.dx;
          final spanX = (x1 - x0).abs() < 1e-9 ? 1e-9 : (x1 - x0);

          const edge = 0.0;
          final xClamped =
              n.dx.clamp(math.min(x0, x1) + edge, math.max(x0, x1) - edge);

          final rawBias =
              ((xClamped - x0) / spanX).clamp(0.001, 0.999).toDouble();
          final bias = _clampBiasPxSafe(seg, size, rawBias);

          if (_mode == CurveMode.bend) {
            final minY = math.min(a.p.dy, b.p.dy);
            final maxY = math.max(a.p.dy, b.p.dy);
            final yBound = _boundedBetween(n.dy, minY, maxY);

            setState(() {
              a.bias = bias;
              a.bendY = yBound;
            });
          } else {
            final linY = lerpDouble(a.p.dy, b.p.dy, bias)!;
            final y = n.dy;
            final amt = ((linY - y) / 0.45);

            setState(() {
              a.bias = bias;
              a.bulgeAmt = amt.clamp(-2.5, 2.5).toDouble();
            });
          }

          _emitCurve();
          return;
        }
      },

      onPanEnd: (_) {
        _cancelLongPress();
        setState(() {
          _dragKind = _DragKind.none;
          _dragIndex = null;
        });
      },

      // ✅ paint as the child
      child: CustomPaint(
        painter: _LfoEditorPainter(
          repaint: controller, // ✅ ADD THIS
          nodes: _nodes,
          selectedIndex: _selectedIndex,
          mode: _mode,
          resolution: _curveResolution,
          nodeRadius: _nodeRadius,
          handleRadius: _handleRadius,
          strokeWidth: _strokeWidth,
          playhead01: playhead01,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  // hit testing
  _Hit? _hitTest(Offset local, Size size) {
    // 0) If you're actually on a node, the node wins.
    for (int i = 0; i < _nodes.length; i++) {
      final np = _toLocal(_nodes[i].p, size);
      final r = (i == 0 || i == _nodes.length - 1) ? 18.0 : 16.0;
      if ((np - local).distance <= r) return _Hit.node(i);
    }

    // 1) Handles first
    for (int i = 0; i < _nodes.length - 1; i++) {
      const epsX = 0.0005;
      if ((_nodes[i].p.dx - _nodes[i + 1].p.dx).abs() <= epsX) continue;

      final hp = _handleLocalForSegment(i, size);
      var r = _handleHitRadiusPx;

      if ((size.height - hp.dy) <= _bottomAssistZonePx) {
        r += _bottomAssistBoostPx;
      }

      if ((hp - local).distance <= r) return _Hit.handle(i);
    }

    // 2) Nodes fallback (bigger hit for endpoints)
    for (int i = 0; i < _nodes.length; i++) {
      final hp = _toLocal(_nodes[i].p, size);

      double r = (i == 0 || i == _nodes.length - 1)
          ? _endNodeHitRadiusPx
          : _nodeHitRadiusPx;

      if ((size.height - hp.dy) <= _bottomAssistZonePx) {
        r += _bottomAssistBoostPx;
      }

      if ((hp - local).distance <= r) return _Hit.node(i);
    }

    return null;
  }

  Offset _handleLocalForSegment(int seg, Size size) {
    final h = _handleNormForSegment(seg);
    return _toLocal(h, size);
  }

  Offset _handleNormForSegment(int seg) {
    final a = _nodes[seg];
    final b = _nodes[seg + 1];

    final bias = a.bias.clamp(0.001, 0.999);
    final xH = lerpDouble(a.p.dx, b.p.dx, bias)!.clamp(0.0, 1.0);

    if (_mode == CurveMode.bend) {
      final minY = math.min(a.p.dy, b.p.dy);
      final maxY = math.max(a.p.dy, b.p.dy);
      final yH = a.bendY.clamp(minY, maxY);
      return Offset(xH, yH);
    } else {
      final span = (b.p.dx - a.p.dx);
      if (span.abs() <= 1e-9) return Offset(a.p.dx, a.p.dy);

      final t = bias;
      final y = _segmentSampleYBulge(seg, t);
      return Offset(xH, y);
    }
  }

  int _closestNodeIndex(Offset norm) {
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < _nodes.length; i++) {
      final d = (norm - _nodes[i].p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _ensureSortedAndSafe() {
    _nodes.sort((a, b) => a.p.dx.compareTo(b.p.dx));

    _nodes.first.p = Offset(0.0, _nodes.first.p.dy);
    _nodes.last.p = Offset(1.0, _nodes.last.p.dy);

    for (int i = 1; i < _nodes.length - 1; i++) {
      final prevX = _nodes[i - 1].p.dx;
      final nextX = _nodes[i + 1].p.dx;
      var x = _nodes[i].p.dx;
      if (x < prevX) x = prevX;
      if (x > nextX) x = nextX;
      _nodes[i].p = Offset(x, _nodes[i].p.dy);
    }

    for (int i = 0; i < _nodes.length - 1; i++) {
      _nodes[i].bias = _nodes[i].bias.clamp(0.001, 0.999);
      _nodes[i].bulgeAmt = _nodes[i].bulgeAmt.clamp(-2.5, 2.5);

      final aY = _nodes[i].p.dy;
      final bY = _nodes[i + 1].p.dy;
      final minY = math.min(aY, bY);
      final maxY = math.max(aY, bY);
      _nodes[i].bendY = _nodes[i].bendY.clamp(minY, maxY);
    }
  }

  // coordinate helpers
  Offset _toNorm(Offset local, Size size) {
    final r = _graphRect(size);

    final dx = (local.dx - r.left) / (r.width <= 0 ? 1.0 : r.width);
    final dy = (local.dy - r.top) / (r.height <= 0 ? 1.0 : r.height);

    return Offset(dx, dy);
  }

  Offset _toLocal(Offset norm, Size size) {
    final r = _graphRect(size);
    return Offset(
      r.left + norm.dx * r.width,
      r.top + norm.dy * r.height,
    );
  }

  double _clamp01(double v) => v.clamp(0.0, 1.0);
  double _clampNodeY(double y) => y.clamp(0.0, 1.0);

  double _clampBiasPxSafe(int seg, Size size, double bias) {
    final aPx = _toLocal(_nodes[seg].p, size);
    final bPx = _toLocal(_nodes[seg + 1].p, size);
    final segLen = (bPx - aPx).distance;

    const gap = 6.0;
    final minDistPx = _nodeRadius + _handleRadius + gap;

    if (segLen <= 1.0) return 0.5;

    final minT = (minDistPx / segLen).clamp(0.001, 0.45).toDouble();
    return bias.clamp(minT, 1.0 - minT).toDouble();
  }

  double _tanh(double x) {
    final ex = math.exp(x);
    final emx = math.exp(-x);
    return (ex - emx) / (ex + emx);
  }

  double _boundedBetween(double v, double min, double max) {
    final span = max - min;
    if (span <= 1e-9) return min;

    final mid = (min + max) * 0.5;
    final half = span * 0.5;

    const k = 2.6;

    final z = (v - mid) / half;
    final t = _tanh(k * z);

    return mid + t * half;
  }

  // Bulge sampling
  double _segmentSampleYBulge(int seg, double t) {
    final a = _nodes[seg];
    final b = _nodes[seg + 1];

    final bias = a.bias.clamp(0.05, 0.95);
    final amt = a.bulgeAmt.clamp(-2.5, 2.5);

    final linY = lerpDouble(a.p.dy, b.p.dy, t)!;
    final bulge = _bulge01(t, bias);

    return (linY - (amt * 0.45) * bulge).clamp(0.0, 1.0);
  }

  double _bulge01(double t, double bias) {
    t = t.clamp(0.0, 1.0);
    bias = bias.clamp(0.05, 0.95);

    if (t <= bias) {
      final u = t / bias;
      return math.sin(u * math.pi * 0.5);
    } else {
      final u = (1.0 - t) / (1.0 - bias);
      return math.sin(u * math.pi * 0.5);
    }
  }
}

class _LfoEditorPainter extends CustomPainter {
  _LfoEditorPainter({
    required Listenable repaint, // ✅ NEW: drives paint when ticker updates
    required this.nodes,
    required this.selectedIndex,
    required this.mode,
    required this.resolution,
    required this.nodeRadius,
    required this.handleRadius,
    required this.strokeWidth,
    required this.playhead01,
  }) : super(repaint: repaint); // ✅ NEW

  final List<_LfoNode> nodes;
  final int? selectedIndex;
  final CurveMode mode;
  final int resolution;

  final double nodeRadius;
  final double handleRadius;
  final double strokeWidth;

  final double playhead01;

  @override
  void paint(Canvas canvas, Size size) {
    final r = _LfoVisualEditorState._graphRectFor(size);

    Offset toPx(Offset n) => Offset(
          r.left + n.dx * r.width,
          r.top + n.dy * r.height,
        );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    for (int i = 1; i < 8; i++) {
      final x = r.left + r.width * (i / 8);
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), gridPaint);
    }
    for (int i = 1; i < 4; i++) {
      final y = r.top + r.height * (i / 4);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), gridPaint);
    }

    // --- playhead line (0..1) ---
    final ph = playhead01.clamp(0.0, 1.0);
    final phX = r.left + (ph * r.width);

    final playheadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.18);

    canvas.drawLine(
      Offset(phX, r.top),
      Offset(phX, r.bottom),
      playheadPaint,
    );

    final epsXNorm = 0.9 / (r.width <= 0 ? 1.0 : r.width);
    final epsYNorm = 0.9 / (r.height <= 0 ? 1.0 : r.height);

    if (nodes.isEmpty) return;

    final curvePath = Path();
    final firstPx = toPx(nodes.first.p);
    curvePath.moveTo(firstPx.dx, firstPx.dy);

    for (int seg = 0; seg < nodes.length - 1; seg++) {
      final a = nodes[seg];
      final b = nodes[seg + 1];

      final ax = a.p.dx, ay = a.p.dy;
      final bx = b.p.dx, by = b.p.dy;

      final dx = bx - ax;
      final dy = by - ay;

      final aPx = toPx(a.p);
      final bPx = toPx(b.p);

      if (dx.abs() < epsXNorm) {
        curvePath.lineTo(aPx.dx, bPx.dy);
        continue;
      }

      if (mode == CurveMode.bulge) {
        final bias = a.bias.clamp(0.05, 0.95);
        final amt = a.bulgeAmt.clamp(-2.5, 2.5);

        double bulge01(double t) {
          t = t.clamp(0.0, 1.0);
          if (t <= bias) {
            final u = t / bias;
            return math.sin(u * math.pi * 0.5);
          } else {
            final u = (1.0 - t) / (1.0 - bias);
            return math.sin(u * math.pi * 0.5);
          }
        }

        for (int i = 1; i <= resolution; i++) {
          final t = i / resolution;
          final x = lerpDouble(ax, bx, t)!;
          final linY = lerpDouble(ay, by, t)!;
          final y = (linY - (amt * 0.45) * bulge01(t)).clamp(0.0, 1.0);
          curvePath.lineTo(r.left + x * r.width, r.top + y * r.height);
        }
        continue;
      }

      final bias = a.bias.clamp(0.001, 0.999);
      final xH = lerpDouble(ax, bx, bias)!;

      final minY = math.min(ay, by);
      final maxY = math.max(ay, by);
      final yH = a.bendY.clamp(minY, maxY);

      if (dy.abs() < epsYNorm && (yH - ay).abs() < epsYNorm) {
        curvePath.lineTo(bPx.dx, bPx.dy);
        continue;
      }

      final pA = Offset(ax, ay);
      final pH = Offset(xH, yH);
      final pB = Offset(bx, by);

      Offset norm(Offset v) {
        final d = v.distance;
        if (d <= 1e-9) return const Offset(1, 0);
        return Offset(v.dx / d, v.dy / d);
      }

      final d1 = norm(pH - pA);
      final d2 = norm(pB - pH);
      var tan = Offset(d1.dx + d2.dx, d1.dy + d2.dy);

      if (tan.distance <= 1e-9) {
        tan = norm(pB - pA);
      } else {
        tan = norm(tan);
      }

      if (dx > 0 && tan.dx < 0) tan = Offset(-tan.dx, -tan.dy);
      if (dx < 0 && tan.dx > 0) tan = Offset(-tan.dx, -tan.dy);

      final s = math.min((pH - pA).distance, (pB - pH).distance) * 0.30;

      double clampX(double x, double lo, double hi) {
        final mn = math.min(lo, hi);
        final mx = math.max(lo, hi);
        return x.clamp(mn, mx).toDouble();
      }

      final cA1 = Offset(
        lerpDouble(pA.dx, pH.dx, 0.35)!,
        lerpDouble(pA.dy, pH.dy, 0.35)!,
      );
      final cA2 = Offset(
        clampX(pH.dx - tan.dx * s, pA.dx, pH.dx),
        (pH.dy - tan.dy * s).clamp(minY, maxY),
      );

      final cB1 = Offset(
        clampX(pH.dx + tan.dx * s, pH.dx, pB.dx),
        (pH.dy + tan.dy * s).clamp(minY, maxY),
      );
      final cB2 = Offset(
        lerpDouble(pH.dx, pB.dx, 0.65)!,
        lerpDouble(pH.dy, b.p.dy, 0.65)!,
      );

      final a1Px = toPx(cA1);
      final a2Px = toPx(cA2);
      final hPx = toPx(pH);
      final b1Px = toPx(cB1);
      final b2Px = toPx(cB2);
      final bPx2 = toPx(pB);

      curvePath.cubicTo(a1Px.dx, a1Px.dy, a2Px.dx, a2Px.dy, hPx.dx, hPx.dy);
      curvePath.cubicTo(b1Px.dx, b1Px.dy, b2Px.dx, b2Px.dy, bPx2.dx, bPx2.dy);
    }

    final fillPath = Path.from(curvePath)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0xFF66FFB3).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    final curvePaint = Paint()
      ..color = const Color(0xFF66FFB3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(curvePath, curvePaint);

    // Nodes
    for (int i = 0; i < nodes.length; i++) {
      final p = toPx(nodes[i].p);
      final isSelected = (selectedIndex != null && selectedIndex == i);

      final outer = Paint()
        ..color = const Color(0xFF66FFB3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 2;

      final inner = Paint()
        ..color = const Color(0xFF0F0F18)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p, isSelected ? (nodeRadius + 1) : nodeRadius, inner);
      canvas.drawCircle(p, isSelected ? (nodeRadius + 1) : nodeRadius, outer);

      if (isSelected) {
        final glow = Paint()
          ..color = const Color(0xFF66FFB3).withValues(alpha: 0.22)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, nodeRadius + 6, glow);
      }
    }

    // Handles
    for (int seg = 0; seg < nodes.length - 1; seg++) {
      final a = nodes[seg];
      final b = nodes[seg + 1];

      const epsX = 0.0005;
      if ((a.p.dx - b.p.dx).abs() <= epsX) continue;

      final bias = a.bias.clamp(0.001, 0.999);
      final xH = lerpDouble(a.p.dx, b.p.dx, bias)!;

      final yH = (mode == CurveMode.bend)
          ? a.bendY.clamp(
              math.min(a.p.dy, b.p.dy),
              math.max(a.p.dy, b.p.dy),
            )
          : _handleYOnBulge(a: a, b: b, t: bias);

      final hp = Offset(
        r.left + xH * r.width,
        r.top + yH * r.height,
      );

      final handleFill = Paint()
        ..color = const Color(0xFF66FFB3)
        ..style = PaintingStyle.fill;

      final handleOutline = Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(hp, handleRadius, handleFill);
      canvas.drawCircle(hp, handleRadius, handleOutline);
    }
  }

  static double _handleYOnBulge({
    required _LfoNode a,
    required _LfoNode b,
    required double t,
  }) {
    final bias = a.bias.clamp(0.05, 0.95);
    final amt = a.bulgeAmt.clamp(-2.5, 2.5);

    double bulge01(double tt) {
      tt = tt.clamp(0.0, 1.0);
      if (tt <= bias) {
        final u = tt / bias;
        return math.sin(u * math.pi * 0.5);
      } else {
        final u = (1.0 - tt) / (1.0 - bias);
        return math.sin(u * math.pi * 0.5);
      }
    }

    final linY = lerpDouble(a.p.dy, b.p.dy, t)!;
    return (linY - (amt * 0.45) * bulge01(t)).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _LfoEditorPainter oldDelegate) {
    // repaint is already driven by the Listenable, but keep sensible checks too
    return oldDelegate.playhead01 != playhead01 ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.mode != mode ||
        oldDelegate.resolution != resolution ||
        oldDelegate.nodeRadius != nodeRadius ||
        oldDelegate.handleRadius != handleRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.nodes.length != nodes.length;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.lockedOrder,
    required this.linkEndpoints,
    required this.onToggleMode,
    required this.onToggleLockedOrder,
    required this.onToggleLinkEndpoints,
  });

  final CurveMode mode;
  final bool lockedOrder;
  final bool linkEndpoints;

  final VoidCallback onToggleMode;
  final VoidCallback onToggleLockedOrder;
  final VoidCallback onToggleLinkEndpoints;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B12),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          right: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          _IconToggleButton(
            tooltip: 'Curve: ${mode == CurveMode.bulge ? "Bulge" : "Bend"}',
            selected: true,
            onPressed: onToggleMode,
            child: CustomPaint(
              size: const Size(22, 22),
              painter: _SideSCurveIconPainter(isBend: mode == CurveMode.bend),
            ),
          ),
          const SizedBox(width: 8),
          _IconToggleButton(
            tooltip: lockedOrder ? 'Node order: locked' : 'Node order: free',
            selected: lockedOrder,
            onPressed: onToggleLockedOrder,
            child: Text(
              lockedOrder ? '⇄̸' : '⇄',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _IconToggleButton(
            tooltip:
                linkEndpoints ? 'Endpoints: linked' : 'Endpoints: independent',
            selected: linkEndpoints,
            onPressed: onToggleLinkEndpoints,
            child: Icon(
              linkEndpoints ? Icons.link : Icons.link_off,
              size: 18,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          Text(
            mode == CurveMode.bulge ? 'Bulge' : 'Bend',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconToggleButton extends StatelessWidget {
  const _IconToggleButton({
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          width: 34,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: selected ? 0.16 : 0.10),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SideSCurveIconPainter extends CustomPainter {
  _SideSCurveIconPainter({required this.isBend});
  final bool isBend;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(w * 0.12, h * 0.70);
    path.cubicTo(
      w * 0.32,
      h * (isBend ? 0.70 : 0.85),
      w * 0.40,
      h * (isBend ? 0.30 : 0.15),
      w * 0.55,
      h * 0.30,
    );
    path.cubicTo(
      w * 0.72,
      h * 0.30,
      w * 0.74,
      h * (isBend ? 0.70 : 0.85),
      w * 0.88,
      h * 0.70,
    );

    canvas.drawPath(path, p);

    final dot = Paint()..color = Colors.white60;
    canvas.drawCircle(Offset(w * 0.53, h * 0.50), 2.2, dot);
  }

  @override
  bool shouldRepaint(covariant _SideSCurveIconPainter oldDelegate) {
    return oldDelegate.isBend != isBend;
  }
}
