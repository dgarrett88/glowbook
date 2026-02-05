import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class LfoVisualEditor extends StatefulWidget {
  const LfoVisualEditor({
    super.key,
    required this.lfoId,
    this.onInteractionChanged,
  });

  final String lfoId;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<LfoVisualEditor> createState() => _LfoVisualEditorState();
}

/// Two curvature styles:
/// - Bulge: your “rounding / overshoot vibe” using a bulge amount.
/// - Bend: “Vital-ish bend handle” (bias X + bend Y clamped between endpoints).
enum CurveMode { bulge, bend }

class _LfoNode {
  Offset p;

  double bias; // 0.0..1.0 (segment-local X position of handle)
  double bulgeAmt; // -2.5..2.5 (bulge strength)
  double bendY; // clamped between endpoints in Bend mode

  _LfoNode(
    this.p, {
    this.bias = 0.5,
    this.bulgeAmt = 0.0,
    double? bendY,
  }) : bendY = bendY ?? p.dy;
}

enum _DragKind { none, node, handleAmt, handleCurve } // ✅ NEW handleCurve

class _Hit {
  final bool isNode;
  final int index; // node index OR segment start index
  const _Hit.node(this.index) : isNode = true;
  const _Hit.handle(this.index) : isNode = false;
}

class _LfoVisualEditorState extends State<LfoVisualEditor> {
  CurveMode _mode = CurveMode.bulge;

  final List<_LfoNode> _nodes = <_LfoNode>[
    _LfoNode(const Offset(0.0, 1.0), bendY: 1.0),
    _LfoNode(const Offset(1.0, 1.0), bendY: 1.0),
  ];

  int? _selectedIndex;

  _DragKind _dragKind = _DragKind.none;
  int? _dragIndex; // node index OR segment index

  static const double _nodeHitRadiusPx = 28.0;
  static const double _handleHitRadiusPx = 24.0;

  // Visuals
  static const double _nodeRadius = 8.0; // parent nodes
  static const double _handleRadius = 5.0; // same as nodes = center alignment
  static const double _strokeWidth = 3.0;

  static const int _curveResolution = 140;

  // --- LONG PRESS CURVE DRAG ---
  static const Duration _longPressDelay = Duration(milliseconds: 100);
  static const double _curveDragSensitivity = .2; // tweak feel

  Timer? _lpTimer;
  bool _lpArmed = false; // we are waiting to see if it becomes a long press
  bool _lpActive = false; // long press triggered (curve mode)
  Offset? _lpStartLocal;
  double? _lpStartBulge;
  double? _lpStartBendY;
  int? _lpSeg;

  @override
  void dispose() {
    _lpTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TopBar(
              mode: _mode,
              onToggleMode: () {
                setState(() {
                  _mode = (_mode == CurveMode.bulge)
                      ? CurveMode.bend
                      : CurveMode.bulge;
                  _ensureSortedAndSafe();
                });
              },
            ),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F18),
                    border: Border.all(color: Colors.white10),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      widget.onInteractionChanged?.call(true);

                      final hit = _hitTest(e.localPosition, size);
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
                        // ✅ segment handle pressed: arm long-press curve drag
                        _armLongPressForSegment(hit.index, e.localPosition);

                        setState(() {
                          _selectedIndex = null;
                          _dragKind = _DragKind.handleAmt;
                          _dragIndex = hit.index; // seg index
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
                    child: _buildGestures(size),
                  ),
                ),
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

    // capture starting value so we adjust relative
    if (seg >= 0 && seg < _nodes.length - 1) {
      _lpStartBulge = _nodes[seg].bulgeAmt;
      _lpStartBendY = _nodes[seg].bendY;
    } else {
      _lpStartBulge = null;
      _lpStartBendY = null;
    }

    _lpTimer = Timer(_longPressDelay, () {
      if (!_lpArmed) return;
      // trigger curve drag mode
      _lpActive = true;
      setState(() {
        _dragKind = _DragKind.handleCurve; // ✅ switch mode
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,

      // Double tap add/remove node
      onDoubleTapDown: (d) {
        final hit = _hitTest(d.localPosition, size);

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
          return;
        }

        final n = _toNorm(d.localPosition, size);
        final p = Offset(_clamp01(n.dx), _clamp01(n.dy));
        if (p.dx < 0.02 || p.dx > 0.98) return;

        setState(() {
          _nodes.add(_LfoNode(p, bendY: p.dy));
          _ensureSortedAndSafe();
          _selectedIndex = _closestNodeIndex(p);
        });
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

        // -----------------------
        // NODE DRAG
        // -----------------------
        if (_dragKind == _DragKind.node) {
          final n = _toNorm(d.localPosition, size);
          var next = Offset(_clamp01(n.dx), _clamp01(n.dy));

          // endpoints: lock X but free Y
          if (idx == 0) next = Offset(0.0, next.dy);
          if (idx == _nodes.length - 1) next = Offset(1.0, next.dy);

          _nodes[idx].p = next;

          if (idx != 0 && idx != _nodes.length - 1) {
            _ensureSortedAndSafe();
            final newIdx = _closestNodeIndex(next);
            _dragIndex = newIdx;
            _selectedIndex = newIdx;
          }

          setState(() {});
          return;
        }

        // -----------------------
        // LONG PRESS CURVE DRAG
        // -----------------------
        if (_dragKind == _DragKind.handleCurve) {
          final seg = idx;
          if (seg < 0 || seg >= _nodes.length - 1) return;

          final start = _lpStartLocal;
          if (start == null) return;

          final dyPx = d.localPosition.dy - start.dy;

          // Drag up => more curve (Vital-ish)
          final delta = (-dyPx / (size.height <= 0 ? 1.0 : size.height)) *
              _curveDragSensitivity;

          if (_mode == CurveMode.bulge) {
            final base = _lpStartBulge ?? _nodes[seg].bulgeAmt;
            final nextAmt = (base + delta * 6.0).clamp(-2.5, 2.5).toDouble();
            setState(() {
              _nodes[seg].bulgeAmt = nextAmt;
            });
          } else {
            // Bend mode: adjust bendY within endpoints
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
          return;
        }

        // -----------------------
        // NORMAL HANDLE DRAG (bias + amt/bendY)
        // -----------------------
        if (_dragKind == _DragKind.handleAmt) {
          final seg = idx;
          if (seg < 0 || seg >= _nodes.length - 1) return;

          final a = _nodes[seg];
          final b = _nodes[seg + 1];

          final n = _toNorm(d.localPosition, size);

          final x0 = a.p.dx;
          final x1 = b.p.dx;
          final spanX = (x1 - x0).abs() < 1e-9 ? 1e-9 : (x1 - x0);

          // ✅ THIS is the “padding between parent nodes” you meant:
          // allow the handle to actually reach the segment endpoints.
          const edge = 0.0;

          final xClamped =
              n.dx.clamp(math.min(x0, x1) + edge, math.max(x0, x1) - edge);

          // ✅ allow near-0 / near-1 so it can visually line up with parent node X
          final bias = ((xClamped - x0) / spanX).clamp(0.001, 0.999).toDouble();

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

      child: CustomPaint(
        painter: _LfoEditorPainter(
          nodes: _nodes,
          selectedIndex: _selectedIndex,
          mode: _mode,
          resolution: _curveResolution,
          nodeRadius: _nodeRadius,
          handleRadius: _handleRadius,
          strokeWidth: _strokeWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  // ----------------------------
  // hit testing
  // ----------------------------

  _Hit? _hitTest(Offset local, Size size) {
    for (int i = 0; i < _nodes.length; i++) {
      final hp = _toLocal(_nodes[i].p, size);
      if ((hp - local).distance <= _nodeHitRadiusPx) return _Hit.node(i);
    }

    for (int i = 0; i < _nodes.length - 1; i++) {
      final hp = _handleLocalForSegment(i, size);
      if ((hp - local).distance <= _handleHitRadiusPx) return _Hit.handle(i);
    }
    return null;
  }

  Offset _handleLocalForSegment(int seg, Size size) {
    final h = _handleNormForSegment(seg);
    return Offset(h.dx * size.width, h.dy * size.height);
  }

  Offset _handleNormForSegment(int seg) {
    final a = _nodes[seg];
    final b = _nodes[seg + 1];

    // ✅ render handle exactly where math says it is
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

    // keep internal x ordered (still stable)
    for (int i = 1; i < _nodes.length - 1; i++) {
      final prevX = _nodes[i - 1].p.dx;
      final nextX = _nodes[i + 1].p.dx;
      var x = _nodes[i].p.dx;
      if (x < prevX) x = prevX;
      if (x > nextX) x = nextX;
      _nodes[i].p = Offset(x, _nodes[i].p.dy);
    }

    for (int i = 0; i < _nodes.length - 1; i++) {
      // ✅ keep consistent with the new “can reach endpoints” behaviour
      _nodes[i].bias = _nodes[i].bias.clamp(0.001, 0.999);
      _nodes[i].bulgeAmt = _nodes[i].bulgeAmt.clamp(-2.5, 2.5);

      final aY = _nodes[i].p.dy;
      final bY = _nodes[i + 1].p.dy;
      final minY = math.min(aY, bY);
      final maxY = math.max(aY, bY);
      _nodes[i].bendY = _nodes[i].bendY.clamp(minY, maxY);
    }
  }

  // ----------------------------
  // coordinate helpers
  // ----------------------------

  Offset _toNorm(Offset local, Size size) {
    final w = size.width <= 0 ? 1.0 : size.width;
    final h = size.height <= 0 ? 1.0 : size.height;
    return Offset(local.dx / w, local.dy / h);
  }

  Offset _toLocal(Offset norm, Size size) =>
      Offset(norm.dx * size.width, norm.dy * size.height);

  double _clamp01(double v) => v.clamp(0.0, 1.0);

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

  // ----------------------------
  // Bulge sampling (segment-local)
  // ----------------------------

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
    required this.nodes,
    required this.selectedIndex,
    required this.mode,
    required this.resolution,
    required this.nodeRadius,
    required this.handleRadius,
    required this.strokeWidth,
  });

  final List<_LfoNode> nodes;
  final int? selectedIndex;
  final CurveMode mode;
  final int resolution;

  final double nodeRadius;
  final double handleRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    for (int i = 1; i < 8; i++) {
      final x = size.width * (i / 8);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final epsXNorm = 0.9 / (size.width <= 0 ? 1.0 : size.width);
    final epsYNorm = 0.9 / (size.height <= 0 ? 1.0 : size.height);

    if (nodes.isEmpty) return;

    final curvePath = Path();
    Offset toPx(Offset n) => Offset(n.dx * size.width, n.dy * size.height);

    curvePath.moveTo(
      nodes.first.p.dx * size.width,
      nodes.first.p.dy * size.height,
    );

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
          curvePath.lineTo(x * size.width, y * size.height);
        }
        continue;
      }

      // ✅ Bend mode: allow handle to reach very close to endpoints too
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
        lerpDouble(pH.dy, pB.dy, 0.65)!,
      );

      final A = toPx(pA);
      final H = toPx(pH);
      final B = toPx(pB);

      final A1 = toPx(cA1);
      final A2 = toPx(cA2);
      final B1 = toPx(cB1);
      final B2 = toPx(cB2);

      curvePath.cubicTo(A1.dx, A1.dy, A2.dx, A2.dy, H.dx, H.dy);
      curvePath.cubicTo(B1.dx, B1.dy, B2.dx, B2.dy, B.dx, B.dy);
    }

    final fillPath = Path.from(curvePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
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

    for (int seg = 0; seg < nodes.length - 1; seg++) {
      final a = nodes[seg];
      final b = nodes[seg + 1];

      // ✅ draw handle using the same near-endpoint clamp
      final bias = a.bias.clamp(0.001, 0.999);
      final xH = lerpDouble(a.p.dx, b.p.dx, bias)!;

      final yH = (mode == CurveMode.bend)
          ? a.bendY.clamp(math.min(a.p.dy, b.p.dy), math.max(a.p.dy, b.p.dy))
          : _handleYOnBulge(a: a, b: b, t: bias);

      final hp = Offset(xH * size.width, yH * size.height);

      final handleOuter = Paint()
        ..color = const Color(0xFF66FFB3).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final handleInner = Paint()
        ..color = const Color(0xFF0F0F18)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(hp, handleRadius, handleInner);
      canvas.drawCircle(hp, handleRadius, handleOuter);
    }

    for (int i = 0; i < nodes.length; i++) {
      final p = Offset(nodes[i].p.dx * size.width, nodes[i].p.dy * size.height);
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
  bool shouldRepaint(covariant _LfoEditorPainter oldDelegate) => true;
}

/// Small bar above graph (ready for more buttons)
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.onToggleMode,
  });

  final CurveMode mode;
  final VoidCallback onToggleMode;

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
            tooltip: 'Coming soon',
            selected: false,
            onPressed: () {},
            child:
                const Icon(Icons.more_horiz, size: 18, color: Colors.white38),
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

/// Tiny sideways “S curve” icon painter (like a curve glyph)
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
