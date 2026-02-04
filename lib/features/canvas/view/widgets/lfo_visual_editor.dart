import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

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
/// - Bulge: your original “rounding / overshoot vibe” using a bulge amount.
/// - Bend: “Vital-ish bend handle” (bias X + bend Y clamped between endpoints).
enum CurveMode { bulge, bend }

class _LfoNode {
  Offset p;

  double bias; // 0.05..0.95
  double bulgeAmt; // can be >1 now
  double bendY; // clamped between endpoints

  _LfoNode(
    this.p, {
    this.bias = 0.5,
    this.bulgeAmt = 0.0,
    double? bendY,
  }) : bendY = bendY ?? p.dy;
}

enum _DragKind { none, node, handleAmt, handleBias }

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
  static const double _handleHitRadiusPx = 22.0;

  static const int _curveResolution = 90;

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
                        bottom: Radius.circular(12)),
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,

                    // ✅ instantly disable parent scroll on ANY touch
                    onPointerDown: (e) {
                      widget.onInteractionChanged?.call(true);

                      final hit = _hitTest(e.localPosition, size);
                      if (hit == null) {
                        setState(() {
                          _dragKind = _DragKind.none;
                          _dragIndex = null;
                        });
                        return;
                      }

                      if (hit.isNode) {
                        setState(() {
                          _selectedIndex = hit.index;
                          _dragKind = _DragKind.node;
                          _dragIndex = hit.index;
                        });
                      } else {
                        final seg = hit.index;
                        setState(() {
                          _selectedIndex = null;
                          _dragKind = _DragKind.handleAmt;
                          _dragIndex = seg;
                        });
                      }
                    },

                    onPointerUp: (_) {
                      _dragKind = _DragKind.none;
                      _dragIndex = null;
                      widget.onInteractionChanged?.call(false);
                      setState(() {});
                    },
                    onPointerCancel: (_) {
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

  Widget _buildGestures(Size size) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,

      // Double tap add/remove node (unchanged)
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
            _dragKind = _DragKind.handleAmt; // handle drag always “free” now
            _dragIndex = hit.index; // seg index
          }
        });
      },

      onPanUpdate: (d) {
        final idx = _dragIndex;
        if (idx == null) return;

        // -----------------------
        // NODE DRAG (unchanged)
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
        // HANDLE DRAG (NEW)
        // -----------------------
        if (_dragKind == _DragKind.handleAmt) {
          final seg = idx;
          if (seg < 0 || seg >= _nodes.length - 1) return;

          final a = _nodes[seg];
          final b = _nodes[seg + 1];

          final n = _toNorm(d.localPosition, size);

          // clamp X inside parent X bounds
          final x0 = a.p.dx;
          final x1 = b.p.dx;
          final spanX = (x1 - x0).abs() < 1e-9 ? 1e-9 : (x1 - x0);

          // Keep handle away from exact ends so bias stays sane
          const edge = 0.02;
          final xClamped = n.dx.clamp(x0 + edge, x1 - edge);

          // bias derived from handle X
          final bias = ((xClamped - x0) / spanX).clamp(0.05, 0.95).toDouble();

          if (_mode == CurveMode.bend) {
            // Bend: handle can move anywhere within the bbox (X between parents, Y between parent Ys)
            final minY = math.min(a.p.dy, b.p.dy);
            final maxY = math.max(a.p.dy, b.p.dy);
            final yBound = _boundedBetween(n.dy, minY, maxY);

            setState(() {
              a.bias = bias;
              a.bendY = yBound;
            });
          } else {
            // Bulge: X bound, Y free (can exceed parent Ys)
            // We invert bulgeAmt from desired handle Y at t=bias.
            // At t=bias, bulge01 == 1, so:
            // yHandle = linY - (amt * 0.45)
            final linY = lerpDouble(a.p.dy, b.p.dy, bias)!;
            final y = n.dy; // unrestricted
            final amt = ((linY - y) / 0.45);

            setState(() {
              a.bias = bias;
              // allow more range than [-1..1] so it can overshoot harder
              a.bulgeAmt = amt.clamp(-2.5, 2.5).toDouble();
            });
          }

          return;
        }
      },

      onPanEnd: (_) {
        setState(() {
          _dragKind = _DragKind.none;
          _dragIndex = null;
        });
      },

      child: CustomPaint(
        painter: _LfoEditorPainter(
          nodes: _nodes,
          selectedIndex: _selectedIndex,
          resolution: _curveResolution,
          mode: _mode,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  // ----------------------------
  // hit testing
  // ----------------------------

  _Hit? _hitTest(Offset local, Size size) {
    // nodes first
    for (int i = 0; i < _nodes.length; i++) {
      final hp = _toLocal(_nodes[i].p, size);
      if ((hp - local).distance <= _nodeHitRadiusPx) return _Hit.node(i);
    }

    // then handles
    for (int i = 0; i < _nodes.length - 1; i++) {
      final hp = _handleLocalForSegment(i, size);
      if ((hp - local).distance <= _handleHitRadiusPx) return _Hit.handle(i);
    }
    return null;
  }

  Offset _handleLocalForSegment(int seg, Size size) {
    final a = _nodes[seg];
    final b = _nodes[seg + 1];

    final bias = a.bias.clamp(0.05, 0.95);
    final x = lerpDouble(a.p.dx, b.p.dx, bias)!;

    final y =
        (_mode == CurveMode.bulge) ? _sampleYBulge(x) : _sampleYBendAtX(seg, x);

    return Offset(x * size.width, y * size.height);
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

    // lock endpoint X
    _nodes.first.p = Offset(0.0, _nodes.first.p.dy);
    _nodes.last.p = Offset(1.0, _nodes.last.p.dy);

    // keep internal x strictly increasing
    const eps = 0.001;
    for (int i = 1; i < _nodes.length - 1; i++) {
      final prevX = _nodes[i - 1].p.dx;
      final nextX = _nodes[i + 1].p.dx;

      var x = _nodes[i].p.dx;
      x = x.clamp(prevX + eps, nextX - eps);
      _nodes[i].p = Offset(x, _nodes[i].p.dy);
    }

    // clamp segment params
    for (int i = 0; i < _nodes.length - 1; i++) {
      _nodes[i].bias = _nodes[i].bias.clamp(0.05, 0.95);
      _nodes[i].bulgeAmt = _nodes[i].bulgeAmt.clamp(-1.0, 1.0);

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
    // tanh(x) = (e^x - e^-x) / (e^x + e^-x)
    final ex = math.exp(x);
    final emx = math.exp(-x);
    return (ex - emx) / (ex + emx);
  }

  double _boundedBetween(double v, double min, double max) {
    // Smoothly maps any v into [min..max] with no snapping and no overshoot.
    final span = max - min;
    if (span <= 1e-9) return min;

    // center/span normalize
    final mid = (min + max) * 0.5;
    final half = span * 0.5;

    // k controls “how quickly” it resists at edges.
    // 2.2–3.0 feels good for touch.
    const k = 2.6;

    final z = (v - mid) / half; // unbounded
    final t = _tanh(k * z); // [-1..1]

    return mid + t * half;
  }

  double _softSnapY(double y, double aY, double bY) {
    // Soft “magnet” toward either parent’s Y (no hard snap).
    // Increase snapBand for stronger magnet, decrease for weaker.
    const double snapBand = 0.020; // ~2% of height

    double apply(double target) {
      final d = (y - target).abs();
      if (d >= snapBand) return y;

      // Smoothstep 0..1 where 1 = exactly on target
      final t = 1.0 - (d / snapBand);
      final k = t * t * (3 - 2 * t);

      return y + (target - y) * k;
    }

    // Apply toward whichever target is closer
    final da = (y - aY).abs();
    final db = (y - bY).abs();
    return (da <= db) ? apply(aY) : apply(bY);
  }

  // ----------------------------
  // curve sampling
  // ----------------------------

  // --- Bulge mode ---
  double _sampleYBulge(double x) {
    x = x.clamp(0.0, 1.0);

    for (int i = 0; i < _nodes.length - 1; i++) {
      final a = _nodes[i];
      final b = _nodes[i + 1];

      if (x >= a.p.dx && x <= b.p.dx) {
        final span = b.p.dx - a.p.dx;
        final t = span <= 1e-9 ? 0.0 : (x - a.p.dx) / span;
        return _segmentSampleYBulge(i, t);
      }
    }
    return _nodes.last.p.dy;
  }

  double _segmentSampleYBulge(int seg, double t) {
    final a = _nodes[seg];
    final b = _nodes[seg + 1];

    final bias = a.bias.clamp(0.05, 0.95);
    final amt = a.bulgeAmt.clamp(-1.0, 1.0);

    final linY = lerpDouble(a.p.dy, b.p.dy, t)!;
    final bulge = _bulge01(t, bias);

    // amt > 0 should visually bulge UP (smaller y) => subtract
    final y = (linY - (amt * 0.45) * bulge).clamp(0.0, 1.0);
    return y;
  }

  double _bulge01(double t, double bias) {
    t = t.clamp(0.0, 1.0);
    bias = bias.clamp(0.05, 0.95);

    if (t <= bias) {
      final u = t / bias; // 0..1
      return math.sin(u * math.pi * 0.5);
    } else {
      final u = (1.0 - t) / (1.0 - bias); // 1..0
      return math.sin(u * math.pi * 0.5);
    }
  }

  // --- Bend mode (smooth Vital-ish) ---
  double _sampleYBend(double x) {
    x = x.clamp(0.0, 1.0);

    for (int i = 0; i < _nodes.length - 1; i++) {
      final a = _nodes[i];
      final b = _nodes[i + 1];
      if (x >= a.p.dx && x <= b.p.dx) {
        return _sampleYBendAtX(i, x);
      }
    }
    return _nodes.last.p.dy;
  }

  // ✅ FIX 2:
  // Replace the “two separate quadratics” (which can create a kink at the handle)
  // with a Catmull–Rom spline across A -> Handle -> B (with reflected endpoints),
  // then re-parameterize by X so sampling stays stable.
  double _sampleYBendAtX(int seg, double x) {
    final a = _nodes[seg];
    final b = _nodes[seg + 1];

    final bias = a.bias.clamp(0.05, 0.95);
    final xH = lerpDouble(a.p.dx, b.p.dx, bias)!;

    final aY = a.p.dy;
    final bY = b.p.dy;
    final minY = math.min(aY, bY);
    final maxY = math.max(aY, bY);
    final yH = a.bendY.clamp(minY, maxY);

    // Main points
    final pA = Offset(a.p.dx, aY);
    final pH = Offset(xH, yH);
    final pB = Offset(b.p.dx, bY);

    // If x is on left side, evaluate cubic A->H. Else evaluate cubic H->B.
    if (x <= xH) {
      final x0 = pA.dx;
      final x1 = pH.dx;
      final span = (x1 - x0).abs();
      if (span <= 1e-9) return pH.dy;

      // Control points: flat at A, arrives at H
      final c1 = Offset(lerpDouble(pA.dx, pH.dx, 0.33)!, pA.dy);
      final c2 = Offset(lerpDouble(pA.dx, pH.dx, 0.66)!, pH.dy);

      // Solve t by x (monotone), binary search
      double lo = 0.0, hi = 1.0;
      for (int i = 0; i < 14; i++) {
        final mid = (lo + hi) * 0.5;
        final xm = _cubic1D(pA.dx, c1.dx, c2.dx, pH.dx, mid);
        if (xm < x) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final t = (lo + hi) * 0.5;
      final y = _cubic1D(pA.dy, c1.dy, c2.dy, pH.dy, t);
      return y.clamp(0.0, 1.0);
    } else {
      final x0 = pH.dx;
      final x1 = pB.dx;
      final span = (x1 - x0).abs();
      if (span <= 1e-9) return pB.dy;

      // Control points: leaves H, flat at B
      final c1 = Offset(lerpDouble(pH.dx, pB.dx, 0.33)!, pH.dy);
      final c2 = Offset(lerpDouble(pH.dx, pB.dx, 0.66)!, pB.dy);

      double lo = 0.0, hi = 1.0;
      for (int i = 0; i < 14; i++) {
        final mid = (lo + hi) * 0.5;
        final xm = _cubic1D(pH.dx, c1.dx, c2.dx, pB.dx, mid);
        if (xm < x) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final t = (lo + hi) * 0.5;
      final y = _cubic1D(pH.dy, c1.dy, c2.dy, pB.dy, t);
      return y.clamp(0.0, 1.0);
    }
  }

// Cubic Bézier 1D evaluation helper
  double _cubic1D(double p0, double p1, double p2, double p3, double t) {
    final u = 1.0 - t;
    return (u * u * u) * p0 +
        3.0 * (u * u) * t * p1 +
        3.0 * u * (t * t) * p2 +
        (t * t * t) * p3;
  }
}

class _LfoEditorPainter extends CustomPainter {
  _LfoEditorPainter({
    required this.nodes,
    required this.selectedIndex,
    required this.resolution,
    required this.mode,
  });

  final List<_LfoNode> nodes;
  final int? selectedIndex;
  final int resolution;
  final CurveMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
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

    if (nodes.isEmpty) return;

    double bulge01(double t, double bias) {
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

    double sampleYBulge(double x) {
      x = x.clamp(0.0, 1.0);
      for (int i = 0; i < nodes.length - 1; i++) {
        final a = nodes[i];
        final b = nodes[i + 1];
        if (x >= a.p.dx && x <= b.p.dx) {
          final span = b.p.dx - a.p.dx;
          final t = span <= 1e-9 ? 0.0 : (x - a.p.dx) / span;

          final linY = lerpDouble(a.p.dy, b.p.dy, t)!;
          // amt > 0 should visually bulge UP => subtract
          final y =
              (linY - (a.bulgeAmt.clamp(-1.0, 1.0) * 0.45) * bulge01(t, a.bias))
                  .clamp(0.0, 1.0);
          return y;
        }
      }
      return nodes.last.p.dy;
    }

    // Same smooth Bend sampling as state (duplicated here for painter)
    double sampleYBend(double x) {
      x = x.clamp(0.0, 1.0);

      double cubic1D(double p0, double p1, double p2, double p3, double t) {
        final u = 1.0 - t;
        return (u * u * u) * p0 +
            3.0 * (u * u) * t * p1 +
            3.0 * u * (t * t) * p2 +
            (t * t * t) * p3;
      }

      for (int seg = 0; seg < nodes.length - 1; seg++) {
        final a = nodes[seg];
        final b = nodes[seg + 1];
        if (x < a.p.dx || x > b.p.dx) continue;

        final bias = a.bias.clamp(0.05, 0.95);
        final xH = lerpDouble(a.p.dx, b.p.dx, bias)!;

        final aY = a.p.dy;
        final bY = b.p.dy;
        final minY = math.min(aY, bY);
        final maxY = math.max(aY, bY);
        final yH = a.bendY.clamp(minY, maxY);

        final pA = Offset(a.p.dx, aY);
        final pH = Offset(xH, yH);
        final pB = Offset(b.p.dx, bY);

        if (x <= xH) {
          final span = (pH.dx - pA.dx).abs();
          if (span <= 1e-9) return pH.dy;

          final c1 = Offset(lerpDouble(pA.dx, pH.dx, 0.33)!, pA.dy);
          final c2 = Offset(lerpDouble(pA.dx, pH.dx, 0.66)!, pH.dy);

          double lo = 0.0, hi = 1.0;
          for (int i = 0; i < 14; i++) {
            final mid = (lo + hi) * 0.5;
            final xm = cubic1D(pA.dx, c1.dx, c2.dx, pH.dx, mid);
            if (xm < x) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          final t = (lo + hi) * 0.5;
          return cubic1D(pA.dy, c1.dy, c2.dy, pH.dy, t).clamp(0.0, 1.0);
        } else {
          final span = (pB.dx - pH.dx).abs();
          if (span <= 1e-9) return pB.dy;

          final c1 = Offset(lerpDouble(pH.dx, pB.dx, 0.33)!, pH.dy);
          final c2 = Offset(lerpDouble(pH.dx, pB.dx, 0.66)!, pB.dy);

          double lo = 0.0, hi = 1.0;
          for (int i = 0; i < 14; i++) {
            final mid = (lo + hi) * 0.5;
            final xm = cubic1D(pH.dx, c1.dx, c2.dx, pB.dx, mid);
            if (xm < x) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          final t = (lo + hi) * 0.5;
          return cubic1D(pH.dy, c1.dy, c2.dy, pB.dy, t).clamp(0.0, 1.0);
        }
      }

      return nodes.last.p.dy;
    }

    double sampleY(double x) =>
        (mode == CurveMode.bulge) ? sampleYBulge(x) : sampleYBend(x);

    // Curve path (sampled)
    final curvePath = Path();
    for (int i = 0; i <= resolution; i++) {
      final x = i / resolution;
      final y = sampleY(x);
      final p = Offset(x * size.width, y * size.height);
      if (i == 0) {
        curvePath.moveTo(p.dx, p.dy);
      } else {
        curvePath.lineTo(p.dx, p.dy);
      }
    }

    // Fill under curve
    final fillPath = Path.from(curvePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0xFF66FFB3).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Curve stroke
    final curvePaint = Paint()
      ..color = const Color(0xFF66FFB3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(curvePath, curvePaint);

    // Handles (small dot on curve)
    for (int seg = 0; seg < nodes.length - 1; seg++) {
      final a = nodes[seg];
      final b = nodes[seg + 1];

      final bias = a.bias.clamp(0.05, 0.95);
      final xH = lerpDouble(a.p.dx, b.p.dx, bias)!;

      final yH = (mode == CurveMode.bend)
          ? a.bendY.clamp(math.min(a.p.dy, b.p.dy), math.max(a.p.dy, b.p.dy))
          : sampleY(xH);

      final hp = Offset(xH * size.width, yH * size.height);

      final handleOuter = Paint()
        ..color = const Color(0xFF66FFB3).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final handleInner = Paint()
        ..color = const Color(0xFF0F0F18)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(hp, 6.5, handleInner);
      canvas.drawCircle(hp, 6.5, handleOuter);
    }

    // Nodes
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i].p;
      final p = Offset(n.dx * size.width, n.dy * size.height);

      final isSelected = (selectedIndex != null && selectedIndex == i);

      final outer = Paint()
        ..color = const Color(0xFF66FFB3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 2;

      final inner = Paint()
        ..color = const Color(0xFF0F0F18)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p, isSelected ? 9 : 8, inner);
      canvas.drawCircle(p, isSelected ? 9 : 8, outer);

      if (isSelected) {
        final glow = Paint()
          ..color = const Color(0xFF66FFB3).withValues(alpha: 0.22)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, 14, glow);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LfoEditorPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.resolution != resolution ||
        oldDelegate.mode != mode;
  }
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
              painter: _SideSCurveIconPainter(
                // slight visual difference between modes
                isBend: mode == CurveMode.bend,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Placeholder buttons for later
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
                fontWeight: FontWeight.w600),
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
                color: Colors.white.withValues(alpha: selected ? 0.16 : 0.10)),
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

    // Draw an S-ish sideways curve with a simple cubic
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

    // a tiny dot to hint “handle”
    final dot = Paint()..color = Colors.white60;
    canvas.drawCircle(Offset(w * 0.53, h * 0.50), 2.2, dot);
  }

  @override
  bool shouldRepaint(covariant _SideSCurveIconPainter oldDelegate) {
    return oldDelegate.isBend != isBend;
  }
}
