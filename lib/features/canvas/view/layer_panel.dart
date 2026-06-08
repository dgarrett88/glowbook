// lib/features/canvas/view/layer_panel.dart
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_controller.dart' as canvas_state;
import '../../../core/models/canvas_layer.dart';
import '../../../core/models/stroke.dart';
import '../../../core/models/lfo.dart';
import 'package:glowbook/core/models/lfo_route.dart';

import 'widgets/synth_knob.dart';
import 'text_panel.dart';

class LayerPanel extends ConsumerStatefulWidget {
  const LayerPanel({
    super.key,
    this.scrollController,
    this.showHeader = true,
  });

  final ScrollController? scrollController;

  /// ✅ When used inside the draggable sheet, BottomDock provides its own header.
  /// Set this false to avoid the double header.
  final bool showHeader;

  @override
  ConsumerState<LayerPanel> createState() => _LayerPanelState();
}

class _LayerPanelState extends ConsumerState<LayerPanel> {
  final Set<String> _expanded = <String>{};

  // ✅ locks list scroll + reorder while knobs are touched
  final ValueNotifier<bool> _knobIsActive = ValueNotifier<bool>(false);

  // ✅ fade only after a knob value changes (not on touch / double-tap reset)
  final ValueNotifier<bool> _fadeOut = ValueNotifier<bool>(false);

  bool _turnedSinceTouch = false;

  @override
  void initState() {
    super.initState();

    // Layer panel contains live LFO mod indicators/knob overlays.
    // While this panel is mounted/visible, keep the lightweight UI LFO ticker alive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(canvas_state.canvasControllerProvider)
          .setLfoEditorPreviewActive(true);
    });
  }

  void _onKnobInteraction(bool active) {
    _knobIsActive.value = active;

    if (active) {
      // New touch session: don't fade yet.
      _turnedSinceTouch = false;
      return;
    }

    // Touch ended: fade back in only if we ever faded out.
    if (_turnedSinceTouch) {
      _fadeOut.value = false;
    }

    _turnedSinceTouch = false;
  }

  void _onKnobValueChanged() {
    // Only fade for real drags. Double-tap reset / typed values shouldn't fade.
    if (!_knobIsActive.value) return;

    // First actual value change during this touch session triggers fade-out.
    if (_turnedSinceTouch) return;

    _turnedSinceTouch = true;
    _fadeOut.value = true;
  }

  @override
  void dispose() {
    ref
        .read(canvas_state.canvasControllerProvider)
        .setLfoEditorPreviewActive(false);

    _fadeOut.dispose();
    _knobIsActive.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    // Rebuild the visible layer panel on the lightweight LFO UI ticker so
    // mod lights and mod-ring overlays animate even when nothing else changes.
    return AnimatedBuilder(
      animation: controller.lfoPreviewRepaint,
      builder: (context, _) {
        final layers = controller.layers;
        final activeId = controller.activeLayerId;

        // Outer: controls scroll lock
        return ValueListenableBuilder<bool>(
          valueListenable: _knobIsActive,
          builder: (context, knobActive, _) {
            // Inner: controls fade visibility
            return ValueListenableBuilder<bool>(
              valueListenable: _fadeOut,
              builder: (context, fadeOut, __) {
                return AnimatedOpacity(
                  opacity: fadeOut ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF101018).withValues(alpha: 0.4),
                          border: const Border(
                            top: BorderSide(color: Color(0xFF303040)),
                          ),
                        ),
                        child: ReorderableListView.builder(
                          scrollController: widget.scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          buildDefaultDragHandles: false,
                          physics: knobActive
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          itemCount: layers.length,
                          header: widget.showHeader
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 10,
                                        bottom: 8,
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 44,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.25),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _LayerPanelHeader(
                                      layerCount: layers.length,
                                      onAddLayer: controller.addLayer,
                                    ),
                                    const Divider(
                                      height: 1,
                                      color: Color(0xFF262636),
                                    ),
                                  ],
                                )
                              : null,
                          onReorder: (oldIndex, newIndex) {
                            if (knobActive) return;
                            if (newIndex > oldIndex) newIndex -= 1;

                            final newOrder = List<CanvasLayer>.from(layers);
                            final moved = newOrder.removeAt(oldIndex);
                            newOrder.insert(newIndex, moved);

                            controller.reorderLayersByIds(
                              newOrder.map((l) => l.id).toList(),
                            );
                          },
                          itemBuilder: (context, index) {
                            final layer = layers[index];
                            final bool isActive = layer.id == activeId;
                            final bool isOnlyLayer = layers.length == 1;
                            final bool isExpanded =
                                _expanded.contains(layer.id);

                            return _LayerTile(
                              key: ValueKey(layer.id),
                              layer: layer,
                              isActive: isActive,
                              isOnlyLayer: isOnlyLayer,
                              isExpanded: isExpanded,
                              index: index,
                              reorderEnabled: !knobActive,
                              onAnyKnobInteraction: _onKnobInteraction,
                              onAnyKnobValueChanged: _onKnobValueChanged,
                              onSelect: () {
                                controller.setActiveLayer(layer.id);
                              },
                              onToggleVisible: () {
                                controller.setLayerVisibility(
                                  layer.id,
                                  !layer.visible,
                                );
                              },
                              onToggleLocked: () {
                                controller.setLayerLocked(
                                  layer.id,
                                  !layer.locked,
                                );
                              },
                              onDelete: isOnlyLayer
                                  ? null
                                  : () {
                                      controller.removeLayer(layer.id);
                                    },
                              onRename: () {
                                _promptRenameLayer(
                                  context,
                                  controller,
                                  layer,
                                );
                              },
                              onToggleExpanded: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expanded.remove(layer.id);
                                  } else {
                                    _expanded.add(layer.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LayerPanelHeader extends StatelessWidget {
  const _LayerPanelHeader({
    required this.layerCount,
    required this.onAddLayer,
  });

  final int layerCount;
  final String Function({String? name}) onAddLayer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(color: Color(0xFF11111C)),
      child: Row(
        children: [
          const Text(
            'Layer menu',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$layerCount',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Add layer',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, color: cs.primary),
            onPressed: () => onAddLayer(),
          ),
        ],
      ),
    );
  }
}

class _LayerTransformValues {
  final double x;
  final double y;
  final double rotationDegrees;
  final double scale;
  final double opacity;

  const _LayerTransformValues({
    required this.x,
    required this.y,
    required this.rotationDegrees,
    required this.scale,
    required this.opacity,
  });

  _LayerTransformValues copyWith({
    double? x,
    double? y,
    double? rotationDegrees,
    double? scale,
    double? opacity,
  }) {
    return _LayerTransformValues(
      x: x ?? this.x,
      y: y ?? this.y,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
    );
  }
}

class _LayerTile extends StatefulWidget {
  const _LayerTile({
    super.key,
    required this.layer,
    required this.isActive,
    required this.isOnlyLayer,
    required this.isExpanded,
    required this.index,
    required this.reorderEnabled,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
    required this.onSelect,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onDelete,
    required this.onRename,
    required this.onToggleExpanded,
  });

  final CanvasLayer layer;
  final bool isActive;
  final bool isOnlyLayer;
  final bool isExpanded;
  final int index;

  final bool reorderEnabled;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  final VoidCallback onSelect;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final VoidCallback? onDelete;
  final VoidCallback onRename;
  final VoidCallback onToggleExpanded;

  @override
  State<_LayerTile> createState() => _LayerTileState();
}

class _LayerTileState extends State<_LayerTile> {
  late _LayerTransformValues _values;

  @override
  void initState() {
    super.initState();
    final t = widget.layer.transform;
    _values = _LayerTransformValues(
      x: t.position.dx,
      y: -t.position.dy,
      rotationDegrees: t.rotation * 180.0 / math.pi,
      scale: t.scale,
      opacity: t.opacity,
    );
  }

  void _updateAndSend(_LayerTransformValues v) {
    setState(() => _values = v);
  }

  @override
  void didUpdateWidget(covariant _LayerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.transform != widget.layer.transform) {
      final t = widget.layer.transform;
      _values = _LayerTransformValues(
        x: t.position.dx,
        y: -t.position.dy,
        rotationDegrees: t.rotation * 180.0 / math.pi,
        scale: t.scale,
        opacity: t.opacity,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layer = widget.layer;

    // ✅ Always-solid tile background
    final Color baseBg = const Color(0xFF121220);

    // ✅ Selected highlight is done via border + subtle glow overlay
    final Color borderColor =
        widget.isActive ? cs.primary.withValues(alpha: 0.65) : Colors.white10;

    final Color textColor =
        layer.visible ? Colors.white : Colors.white.withValues(alpha: 0.5);

    final strokeCount = _strokeCount(layer);

    Widget dragNameRow() {
      final row = Row(
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: layer.locked
                  ? Colors.orange
                  : (layer.visible ? cs.primary : Colors.grey),
            ),
          ),
          Text(
            '#${widget.index + 1}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              layer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );

      if (!widget.reorderEnabled) return row;

      return ReorderableDragStartListener(
        index: widget.index,
        child: row,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: borderColor, width: widget.isActive ? 1.3 : 1),
        boxShadow: widget.isActive
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // ✅ Header stays solid always; active gets a subtle overlay
          Stack(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onSelect,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      dragNameRow(),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$strokeCount',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onToggleVisible,
                        icon: Icon(
                          layer.visible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                      ),
                      IconButton(
                        tooltip: layer.locked ? 'Unlock layer' : 'Lock layer',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onToggleLocked,
                        icon: Icon(
                          layer.locked ? Icons.lock : Icons.lock_open,
                          color: layer.locked
                              ? Colors.orangeAccent
                              : Colors.white70,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename layer',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onRename,
                        icon: const Icon(Icons.edit,
                            color: Colors.white70, size: 18),
                      ),
                      IconButton(
                        tooltip: widget.isOnlyLayer
                            ? 'Cannot delete last layer'
                            : 'Delete layer',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onDelete,
                        icon: Icon(
                          Icons.delete,
                          color: widget.isOnlyLayer
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.redAccent,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: widget.isExpanded
                            ? 'Hide transforms'
                            : 'Show transforms',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onToggleExpanded,
                        icon: Icon(
                          widget.isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.isActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: cs.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.isExpanded) ...[
            _LayerTransformEditor(
              layerId: layer.id,
              values: _values,
              onChanged: _updateAndSend,
              onAnyKnobInteraction: widget.onAnyKnobInteraction,
              onAnyKnobValueChanged: widget.onAnyKnobValueChanged,
            ),
            const SizedBox(height: 6),
            LayerTextSection(
              layerId: layer.id,
              onAnyKnobInteraction: widget.onAnyKnobInteraction,
              onAnyKnobValueChanged: widget.onAnyKnobValueChanged,
              buildTextModLight: (context, layerId, textObjectId, param) {
                return _TextModLight(
                  layerId: layerId,
                  textObjectId: textObjectId,
                  param: param,
                  onInteractionChanged: widget.onAnyKnobInteraction,
                );
              },
            ),
            const SizedBox(height: 6),
            _StrokeList(
              layer: layer,
              layerId: layer.id,
              onAnyKnobInteraction: widget.onAnyKnobInteraction,
              onAnyKnobValueChanged: widget.onAnyKnobValueChanged,
            ),
          ],
        ],
      ),
    );
  }

  int _strokeCount(CanvasLayer layer) {
    int count = 0;
    for (final g in layer.groups) {
      count += g.strokes.length;
    }
    return count;
  }
}

class _LayerTransformEditor extends ConsumerWidget {
  const _LayerTransformEditor({
    required this.layerId,
    required this.values,
    required this.onChanged,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final String layerId;
  final _LayerTransformValues values;
  final ValueChanged<_LayerTransformValues> onChanged;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(canvas_state.canvasControllerProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF151524),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              // X
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LayerModLight(
                    layerId: layerId,
                    param: LfoParam.layerX,
                    onInteractionChanged: onAnyKnobInteraction,
                  ),
                  const SizedBox(height: 6),
                  SynthKnob(
                    label: 'X',
                    value: values.x.clamp(-500, 500),
                    min: -500,
                    max: 500,
                    defaultValue: 0,
                    modMinValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerX,
                      );
                      if (route == null) return null;

                      final base = values.x.clamp(-500.0, 500.0).toDouble();
                      final depthPct =
                          (route.amount / 500.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct >= 0.0) {
                        return base;
                      }

                      final availableToMin = base - (-500.0);
                      final end = (base + (availableToMin * depthPct))
                          .clamp(-500.0, 500.0)
                          .toDouble();

                      return math.min(base, end).toDouble();
                    }(),
                    modMaxValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerX,
                      );
                      if (route == null) return null;

                      final base = values.x.clamp(-500.0, 500.0).toDouble();
                      final depthPct =
                          (route.amount / 500.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct <= 0.0) {
                        return base;
                      }

                      final availableToMax = 500.0 - base;
                      final end = (base + (availableToMax * depthPct))
                          .clamp(-500.0, 500.0)
                          .toDouble();

                      return math.max(base, end).toDouble();
                    }(),
                    modValue: controller.previewLayerParamValue(
                      layerId,
                      LfoParam.layerX,
                      values.x.clamp(-500.0, 500.0).toDouble(),
                    ),
                    modDirection: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerX,
                      );
                      if (route == null) return 0.0;
                      return route.amount;
                    }(),
                    valueFormatter: (v) => v.toStringAsFixed(0),
                    onInteractionChanged: onAnyKnobInteraction,
                    onChangeStart: () =>
                        controller.beginLayerKnob(layerId, label: 'Layer X'),
                    onChangeEnd: () => controller.endLayerKnob(layerId),
                    onChanged: (v) {
                      onAnyKnobValueChanged();
                      controller.setLayerXRef(layerId, v);
                      onChanged(values.copyWith(x: v));
                    },
                  ),
                ],
              ),

              // Y
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LayerModLight(
                    layerId: layerId,
                    param: LfoParam.layerY,
                    onInteractionChanged: onAnyKnobInteraction,
                  ),
                  const SizedBox(height: 6),
                  SynthKnob(
                    label: 'Y',
                    value: values.y.clamp(-500, 500),
                    min: -500,
                    max: 500,
                    defaultValue: 0,
                    modMinValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerY,
                      );
                      if (route == null) return null;

                      final base = values.y.clamp(-500.0, 500.0).toDouble();
                      final depthPct =
                          (route.amount / 500.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct >= 0.0) {
                        return base;
                      }

                      final availableToMin = base - (-500.0);
                      final end = (base + (availableToMin * depthPct))
                          .clamp(-500.0, 500.0)
                          .toDouble();

                      return math.min(base, end).toDouble();
                    }(),
                    modMaxValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerY,
                      );
                      if (route == null) return null;

                      final base = values.y.clamp(-500.0, 500.0).toDouble();
                      final depthPct =
                          (route.amount / 500.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct <= 0.0) {
                        return base;
                      }

                      final availableToMax = 500.0 - base;
                      final end = (base + (availableToMax * depthPct))
                          .clamp(-500.0, 500.0)
                          .toDouble();

                      return math.max(base, end).toDouble();
                    }(),
                    modValue: controller.previewLayerParamValue(
                      layerId,
                      LfoParam.layerY,
                      values.y.clamp(-500.0, 500.0).toDouble(),
                    ),
                    modDirection: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerY,
                      );
                      if (route == null) return 0.0;
                      return route.amount;
                    }(),
                    valueFormatter: (v) => v.toStringAsFixed(0),
                    onInteractionChanged: onAnyKnobInteraction,
                    onChangeStart: () =>
                        controller.beginLayerKnob(layerId, label: 'Layer Y'),
                    onChangeEnd: () => controller.endLayerKnob(layerId),
                    onChanged: (v) {
                      onAnyKnobValueChanged();
                      controller.setLayerYRef(layerId, v);
                      onChanged(values.copyWith(y: v));
                    },
                  ),
                ],
              ),

              // Scale
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LayerModLight(
                    layerId: layerId,
                    param: LfoParam.layerScale,
                    onInteractionChanged: onAnyKnobInteraction,
                  ),
                  const SizedBox(height: 6),
                  SynthKnob(
                    label: 'Scale',
                    value: values.scale.clamp(0.1, 5.0),
                    min: 0.1,
                    max: 5.0,
                    defaultValue: 1.0,
                    modMinValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerScale,
                      );
                      if (route == null) return null;

                      final base = values.scale.clamp(0.1, 5.0).toDouble();
                      final depthPct =
                          (route.amount / 3.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct >= 0.0) {
                        return base;
                      }

                      final availableToMin = base - 0.1;
                      final end = (base + (availableToMin * depthPct))
                          .clamp(0.1, 5.0)
                          .toDouble();

                      return math.min(base, end).toDouble();
                    }(),
                    modMaxValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerScale,
                      );
                      if (route == null) return null;

                      final base = values.scale.clamp(0.1, 5.0).toDouble();
                      final depthPct =
                          (route.amount / 3.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct <= 0.0) {
                        return base;
                      }

                      final availableToMax = 5.0 - base;
                      final end = (base + (availableToMax * depthPct))
                          .clamp(0.1, 5.0)
                          .toDouble();

                      return math.max(base, end).toDouble();
                    }(),
                    modValue: controller.previewLayerParamValue(
                      layerId,
                      LfoParam.layerScale,
                      values.scale.clamp(0.1, 5.0).toDouble(),
                    ),
                    modDirection: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerScale,
                      );
                      if (route == null) return 0.0;
                      return route.amount;
                    }(),
                    valueFormatter: (v) => v.toStringAsFixed(2),
                    onInteractionChanged: onAnyKnobInteraction,
                    onChangeStart: () => controller.beginLayerKnob(layerId,
                        label: 'Layer Scale'),
                    onChangeEnd: () => controller.endLayerKnob(layerId),
                    onChanged: (v) {
                      onAnyKnobValueChanged();
                      controller.setLayerScaleRef(layerId, v);
                      onChanged(values.copyWith(scale: v));
                    },
                  ),
                ],
              ),

              // Rot
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LayerModLight(
                    layerId: layerId,
                    param: LfoParam.layerRotationDeg,
                    onInteractionChanged: onAnyKnobInteraction,
                  ),
                  const SizedBox(height: 6),
                  SynthKnob(
                    label: 'Rot',
                    value: values.rotationDegrees.clamp(-360, 360),
                    min: -360,
                    max: 360,
                    defaultValue: 0.0,
                    modMinValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerRotationDeg,
                      );
                      if (route == null) return null;

                      final base = values.rotationDegrees
                          .clamp(-360.0, 360.0)
                          .toDouble();

                      // treat amount as signed depth % of available travel
                      final depthPct =
                          (route.amount / 360.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct >= 0.0) {
                        return base;
                      }

                      final availableToMin = base - (-360.0);
                      final end = (base + (availableToMin * depthPct))
                          .clamp(-360.0, 360.0)
                          .toDouble();

                      return math.min(base, end).toDouble();
                    }(),
                    modMaxValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerRotationDeg,
                      );
                      if (route == null) return null;

                      final base = values.rotationDegrees
                          .clamp(-360.0, 360.0)
                          .toDouble();

                      // treat amount as signed depth % of available travel
                      final depthPct =
                          (route.amount / 360.0).clamp(-1.0, 1.0).toDouble();

                      if (depthPct <= 0.0) {
                        return base;
                      }

                      final availableToMax = 360.0 - base;
                      final end = (base + (availableToMax * depthPct))
                          .clamp(-360.0, 360.0)
                          .toDouble();

                      return math.max(base, end).toDouble();
                    }(),
                    modValue: controller.previewLayerParamValue(
                      layerId,
                      LfoParam.layerRotationDeg,
                      values.rotationDegrees.clamp(-360.0, 360.0).toDouble(),
                    ),
                    modDirection: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerRotationDeg,
                      );
                      if (route == null) return 0.0;
                      return route.amount;
                    }(),
                    valueFormatter: (v) => '${v.toStringAsFixed(0)}°',
                    onInteractionChanged: onAnyKnobInteraction,
                    onChangeStart: () =>
                        controller.beginLayerKnob(layerId, label: 'Layer Rot'),
                    onChangeEnd: () => controller.endLayerKnob(layerId),
                    onChanged: (v) {
                      onAnyKnobValueChanged();
                      controller.setLayerRotationDegRef(layerId, v);
                      onChanged(values.copyWith(rotationDegrees: v));
                    },
                  ),
                ],
              ),

              // Opacity
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LayerModLight(
                    layerId: layerId,
                    param: LfoParam.layerOpacity,
                    onInteractionChanged: onAnyKnobInteraction,
                  ),
                  const SizedBox(height: 6),
                  SynthKnob(
                    label: 'Opacity',
                    value: values.opacity.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    defaultValue: 1.0,
                    modMinValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerOpacity,
                      );
                      if (route == null) return null;

                      final base = values.opacity.clamp(0.0, 1.0).toDouble();
                      final depthPct = route.amount.clamp(-1.0, 1.0).toDouble();

                      if (depthPct >= 0.0) {
                        return base;
                      }

                      final availableToMin = base - 0.0;
                      final end = (base + (availableToMin * depthPct))
                          .clamp(0.0, 1.0)
                          .toDouble();

                      return math.min(base, end).toDouble();
                    }(),
                    modMaxValue: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerOpacity,
                      );
                      if (route == null) return null;

                      final base = values.opacity.clamp(0.0, 1.0).toDouble();
                      final depthPct = route.amount.clamp(-1.0, 1.0).toDouble();

                      if (depthPct <= 0.0) {
                        return base;
                      }

                      final availableToMax = 1.0 - base;
                      final end = (base + (availableToMax * depthPct))
                          .clamp(0.0, 1.0)
                          .toDouble();

                      return math.max(base, end).toDouble();
                    }(),
                    modValue: controller.previewLayerParamValue(
                      layerId,
                      LfoParam.layerOpacity,
                      values.opacity.clamp(0.0, 1.0).toDouble(),
                    ),
                    modDirection: () {
                      final route = controller.findRouteForLayerParam(
                        layerId,
                        LfoParam.layerOpacity,
                      );
                      if (route == null) return 0.0;
                      return route.amount;
                    }(),
                    valueFormatter: (v) => '${(v * 100).round()}%',
                    onInteractionChanged: onAnyKnobInteraction,
                    onChangeStart: () => controller.beginLayerKnob(layerId,
                        label: 'Layer Opacity'),
                    onChangeEnd: () => controller.endLayerKnob(layerId),
                    onChanged: (v) {
                      onAnyKnobValueChanged();
                      controller.setLayerOpacityRef(layerId, v);
                      onChanged(values.copyWith(opacity: v));
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tip: long-press a knob to type an exact value • double-tap to reset',
            style: TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------------------
/// MOD LIGHTS
/// ----------------------------------------------------------------------------------

/// Shared light renderer (just visuals). Big hit area, tiny dot.
class _ModLightControl extends StatefulWidget {
  const _ModLightControl({
    required this.isOn,
    required this.value,
    required this.min,
    required this.max,
    required this.onTapLight,
    required this.onChanged,
    this.onInteractionChanged,
  });

  final bool isOn;
  final double value;
  final double min;
  final double max;
  final VoidCallback onTapLight;
  final ValueChanged<double> onChanged;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<_ModLightControl> createState() => _ModLightControlState();
}

class _ModLightControlState extends State<_ModLightControl> {
  double _startValue = 0.0;
  Offset? _dragStart;
  bool _active = false;
  bool _showBubble = false;

  void _setActive(bool v) {
    if (_active == v) return;
    _active = v;
    widget.onInteractionChanged?.call(v);
  }

  double _normBipolar(double v) {
    if (widget.max <= widget.min) return 0.5;
    final t = ((v - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    return t;
  }

  double _denorm(double t) {
    return widget.min + ((widget.max - widget.min) * t.clamp(0.0, 1.0));
  }

  double _percentValue() {
    final maxAbs = math.max(widget.min.abs(), widget.max.abs());
    if (maxAbs <= 0.000001) return 0.0;
    return ((widget.value / maxAbs) * 100.0).clamp(-100.0, 100.0).toDouble();
  }

  Future<void> _promptExactPercent() async {
    final ctrl = TextEditingController(
      text: _percentValue().toStringAsFixed(0),
    );

    final res = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171720),
        title: const Text(
          'Set modulation depth',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter percent (-100 to 100)',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (res == null) return;

    final clampedPct = res.clamp(-100.0, 100.0).toDouble();
    final maxAbs = math.max(widget.min.abs(), widget.max.abs());
    final newValue = (clampedPct / 100.0) * maxAbs;

    widget.onChanged(newValue.clamp(widget.min, widget.max).toDouble());
  }

  @override
  void dispose() {
    if (_active) {
      widget.onInteractionChanged?.call(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _normBipolar(widget.value);
    final signedT = ((t - 0.5) * 2.0).clamp(-1.0, 1.0).toDouble();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _setActive(true),
      onPointerUp: (_) => _setActive(false),
      onPointerCancel: (_) => _setActive(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapLight,
        onLongPress: _promptExactPercent,
        onPanStart: widget.isOn
            ? (d) {
                _setActive(true);
                setState(() => _showBubble = true);
                _startValue = widget.value.clamp(widget.min, widget.max);
                _dragStart = d.localPosition;
              }
            : null,
        onPanUpdate: widget.isOn
            ? (d) {
                final start = _dragStart;
                if (start == null) return;

                final dy = d.localPosition.dy - start.dy;

                // drag up = positive, drag down = negative
                const sensitivity = 0.008;
                final deltaNorm = (-dy) * sensitivity;

                final newNorm = (_normBipolar(_startValue) + deltaNorm)
                    .clamp(0.0, 1.0)
                    .toDouble();

                final newValue = _denorm(newNorm);
                widget.onChanged(newValue);
              }
            : null,
        onPanEnd: (_) {
          _setActive(false);
          if (mounted) {
            setState(() => _showBubble = false);
          }
        },
        onPanCancel: () {
          _setActive(false);
          if (mounted) {
            setState(() => _showBubble = false);
          }
        },
        child: SizedBox(
          width: 40,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: 0,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CustomPaint(
                    painter: _ModLightPainter(
                      isOn: widget.isOn,
                      signedT: signedT,
                    ),
                  ),
                ),
              ),
              if (_showBubble)
                Positioned(
                  top: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11111C),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${_percentValue() >= 0 ? '+' : ''}${_percentValue().toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _percentValue() > 0
                            ? const Color(0xFF69F0AE)
                            : _percentValue() < 0
                                ? const Color(0xFFF60F66)
                                : Colors.white70,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModLightPainter extends CustomPainter {
  _ModLightPainter({
    required this.isOn,
    required this.signedT,
  });

  final bool isOn;
  final double signedT; // -1..1

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    // top-center zero point
    const startAngle = -math.pi / 2.0;

    final ringRect = Rect.fromCircle(center: c, radius: 11.0);

    // full faint track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: isOn ? 0.16 : 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      ringRect,
      startAngle,
      math.pi * 2.0,
      false,
      trackPaint,
    );

    // signed active arc
    if (isOn && signedT.abs() > 0.0001) {
      final bool positive = signedT > 0.0;
      final double mag = signedT.abs().clamp(0.0, 1.0);
      final double sweep = (math.pi * 2.0) * mag;

      final valuePaint = Paint()
        ..color = positive
            ? const Color(0xFF69F0AE).withValues(alpha: 0.95)
            : const Color(0xFFF60F66).withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        ringRect,
        startAngle,
        positive ? sweep : -sweep,
        false,
        valuePaint,
      );
    }

    // center light
    final dotPaint = Paint()
      ..color = isOn ? Colors.greenAccent : Colors.white24
      ..style = PaintingStyle.fill;

    canvas.drawCircle(c, 5.0, dotPaint);

    if (isOn) {
      final glowPaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(c, 7.5, glowPaint);
      canvas.drawCircle(c, 5.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ModLightPainter oldDelegate) {
    return oldDelegate.isOn != isOn || oldDelegate.signedT != signedT;
  }
}

const String _assignNoneKey = '__none__';
const String _assignPresetPrefix = '__preset__:';

String _presetChoiceKey(canvas_state.LfoQuickPreset preset) {
  return '$_assignPresetPrefix${preset.name}';
}

canvas_state.LfoQuickPreset? _presetFromChoiceKey(String key) {
  if (!key.startsWith(_assignPresetPrefix)) return null;

  final name = key.substring(_assignPresetPrefix.length);

  for (final p in canvas_state.LfoQuickPreset.values) {
    if (p.name == name) return p;
  }

  return null;
}

IconData _presetIcon(canvas_state.LfoQuickPreset preset) {
  switch (preset) {
    case canvas_state.LfoQuickPreset.smoothLoop:
      return Icons.waves;
    case canvas_state.LfoQuickPreset.sharpLoop:
      return Icons.change_history;
    case canvas_state.LfoQuickPreset.linearRise:
      return Icons.trending_up;
    case canvas_state.LfoQuickPreset.smoothRise:
      return Icons.swipe_up_alt;
    case canvas_state.LfoQuickPreset.suddenRise:
      return Icons.swap_vert;
  }
}

Widget _assignSectionHeader({
  required String label,
  required bool open,
  required VoidCallback onTap,
}) {
  return ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    contentPadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
    title: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 0.2,
      ),
    ),
    trailing: Icon(
      open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
      color: Colors.white70,
      size: 20,
    ),
    onTap: onTap,
  );
}

Widget _assignDivider() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12),
    child: Divider(
      height: 8,
      thickness: 1,
      color: Colors.white12,
    ),
  );
}

Future<String?> _showAssignLfoPopup({
  required BuildContext context,
  required List<Lfo> lfos,
  required String? currentLfoId,
}) {
  bool showPresets = true;
  bool showCustom = true;

  const selectedColor = Color(0xFF69F0AE);

  return showDialog<String?>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C24),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            title: const Text(
              'Assign LFO',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minLeadingWidth: 26,
                    contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    leading: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                    title: const Text(
                      'None',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => Navigator.of(ctx).pop(_assignNoneKey),
                  ),
                  _assignDivider(),
                  _assignSectionHeader(
                    label: 'Presets',
                    open: showPresets,
                    onTap: () {
                      setDialogState(() {
                        showPresets = !showPresets;
                      });
                    },
                  ),
                  if (showPresets)
                    for (final preset in canvas_state.LfoQuickPreset.values)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        minLeadingWidth: 28,
                        contentPadding: const EdgeInsets.fromLTRB(24, 2, 16, 2),
                        leading: Icon(
                          _presetIcon(preset),
                          color: Colors.cyanAccent.withValues(alpha: 0.85),
                          size: 18,
                        ),
                        title: Text(
                          preset.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            preset.subtitle,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              height: 1.05,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop(_presetChoiceKey(preset));
                        },
                      ),
                  _assignDivider(),
                  _assignSectionHeader(
                    label: 'Custom',
                    open: showCustom,
                    onTap: () {
                      setDialogState(() {
                        showCustom = !showCustom;
                      });
                    },
                  ),
                  if (showCustom) ...[
                    if (lfos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 6, 16, 8),
                        child: Text(
                          'No custom LFOs yet',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      for (final l in lfos)
                        Builder(
                          builder: (_) {
                            final selected = l.id == currentLfoId;
                            final textColor =
                                selected ? selectedColor : Colors.white;
                            final subColor = selected
                                ? selectedColor.withValues(alpha: 0.78)
                                : Colors.white54;

                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              minLeadingWidth: 28,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(24, 2, 16, 2),
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color:
                                    selected ? selectedColor : Colors.white38,
                                size: 18,
                              ),
                              title: Text(
                                l.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  '${l.wave.label} • ${l.rateHz.toStringAsFixed(2)} Hz',
                                  style: TextStyle(
                                    color: subColor,
                                    fontSize: 11,
                                    height: 1.05,
                                  ),
                                ),
                              ),
                              onTap: () => Navigator.of(ctx).pop(l.id),
                            );
                          },
                        ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Layer mod light (same behaviour as your layer rotation one)
class _LayerModLight extends ConsumerWidget {
  const _LayerModLight({
    required this.layerId,
    required this.param,
    this.onInteractionChanged,
  });

  final String layerId;
  final LfoParam param;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    // ✅ These must exist in your controller:
    //   - findRouteForLayerParam(layerId, param)
    //   - clearRouteForLayerParam(layerId, param)
    //   - upsertRouteForLayerParam(layerId:..., param:..., lfoId:...)
    final route = controller.findRouteForLayerParam(layerId, param);
    final isOn = route != null;
    final spec = _lfoAmountSpec(param);

    return _ModLightControl(
      isOn: isOn,
      value: route?.amount ?? 0.0,
      min: spec.min,
      max: spec.max,
      onInteractionChanged: onInteractionChanged,
      onTapLight: () async {
        final lfos = controller.lfos;

        final String? chosen = await _showAssignLfoPopup(
          context: context,
          lfos: controller.lfos,
          currentLfoId: route?.lfoId,
        );

        // Dismissed dialog = do nothing.
        if (chosen == null) return;

        // None = clear current route, then delete old auto preset if unused.
        if (chosen == _assignNoneKey) {
          final oldLfoId = route?.lfoId;

          controller.clearRouteForLayerParam(layerId, param);

          if (oldLfoId != null) {
            controller.deleteAutoPresetLfoIfUnused(oldLfoId);
          }

          return;
        }

        // Preset = create/update a REAL LFO, then assign that real LFO id.
        final preset = _presetFromChoiceKey(chosen);

        if (preset != null) {
          final existingRoute =
              controller.findRouteForLayerParam(layerId, param);

          if (existingRoute != null &&
              controller.isAutoPresetManagedLfo(existingRoute.lfoId)) {
            // Already using an unedited auto preset:
            // update that same LFO instead of creating another one.
            controller.applyQuickPresetToLfo(
              existingRoute.lfoId,
              preset,
              autoPresetManaged: true,
            );
          } else {
            // No route, or current route uses a custom/user-edited LFO:
            // create a new auto preset LFO and assign it.
            final oldLfoId = existingRoute?.lfoId;
            final newLfoId = controller.createQuickPresetLfo(preset);

            controller.upsertRouteForLayerParam(
              layerId: layerId,
              param: param,
              lfoId: newLfoId,
            );

            // If old LFO was an unused auto preset, clean it up.
            if (oldLfoId != null && oldLfoId != newLfoId) {
              controller.deleteAutoPresetLfoIfUnused(oldLfoId);
            }
          }

          return;
        }

        // Otherwise chosen is an existing real custom/preset LFO id.
        final oldLfoId = route?.lfoId;

        controller.upsertRouteForLayerParam(
          layerId: layerId,
          param: param,
          lfoId: chosen,
        );

        // If switching away from an unused auto preset, remove it.
        if (oldLfoId != null && oldLfoId != chosen) {
          controller.deleteAutoPresetLfoIfUnused(oldLfoId);
        }
      },
      onChanged: (v) {
        final r = route;
        if (r == null) return;
        controller.setRouteAmount(r.id, v);
      },
    );
  }
}


/// Text mod light.
///
/// This intentionally reuses the exact same private light control and assign
/// popup used by layer/stroke params. Text only supplies different route
/// lookup/upsert/clear controller calls.
class _TextModLight extends ConsumerWidget {
  const _TextModLight({
    required this.layerId,
    required this.textObjectId,
    required this.param,
    this.onInteractionChanged,
  });

  final String layerId;
  final String textObjectId;
  final LfoParam param;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);
    final route = controller.findRouteForTextParam(
      layerId,
      textObjectId,
      param,
    );
    final isOn = route != null;
    final spec = _lfoAmountSpec(param);

    return _ModLightControl(
      isOn: isOn,
      value: route?.amount ?? 0.0,
      min: spec.min,
      max: spec.max,
      onInteractionChanged: onInteractionChanged,
      onTapLight: () async {
        final String? chosen = await _showAssignLfoPopup(
          context: context,
          lfos: controller.lfos,
          currentLfoId: route?.lfoId,
        );

        if (chosen == null) return;

        if (chosen == _assignNoneKey) {
          final oldLfoId = route?.lfoId;

          controller.clearRouteForTextParam(
            layerId,
            textObjectId,
            param,
          );

          if (oldLfoId != null) {
            controller.deleteAutoPresetLfoIfUnused(oldLfoId);
          }
          return;
        }

        final preset = _presetFromChoiceKey(chosen);

        if (preset != null) {
          final existingRoute = controller.findRouteForTextParam(
            layerId,
            textObjectId,
            param,
          );

          if (existingRoute != null &&
              controller.isAutoPresetManagedLfo(existingRoute.lfoId)) {
            controller.applyQuickPresetToLfo(
              existingRoute.lfoId,
              preset,
              autoPresetManaged: true,
            );
          } else {
            final oldLfoId = existingRoute?.lfoId;
            final newLfoId = controller.createQuickPresetLfo(preset);

            controller.upsertRouteForTextParam(
              layerId: layerId,
              textObjectId: textObjectId,
              param: param,
              lfoId: newLfoId,
            );

            if (oldLfoId != null && oldLfoId != newLfoId) {
              controller.deleteAutoPresetLfoIfUnused(oldLfoId);
            }
          }
          return;
        }

        final oldLfoId = route?.lfoId;

        controller.upsertRouteForTextParam(
          layerId: layerId,
          textObjectId: textObjectId,
          param: param,
          lfoId: chosen,
        );

        if (oldLfoId != null && oldLfoId != chosen) {
          controller.deleteAutoPresetLfoIfUnused(oldLfoId);
        }
      },
      onChanged: (v) {
        final r = route;
        if (r == null) return;
        controller.setRouteAmount(r.id, v);
      },
    );
  }
}

/// Stroke mod light (same UX, same LFO list, but targets a stroke param).
///
/// ✅ Expects these controller functions to exist:
///   - findRouteForStrokeParam(layerId, groupIndex, strokeId, param)
///   - clearRouteForStrokeParam(layerId, groupIndex, strokeId, param)
///   - upsertRouteForStrokeParam(layerId:..., groupIndex:..., strokeId:..., param:..., lfoId:...)
class _StrokeModLight extends ConsumerWidget {
  const _StrokeModLight({
    required this.layerId,
    required this.groupIndex,
    required this.strokeId,
    required this.param,
    this.onInteractionChanged,
  });

  final String layerId;
  final int groupIndex;
  final String strokeId;
  final LfoParam param;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    final route = controller.findRouteForStrokeParam(
      layerId,
      groupIndex,
      strokeId,
      param,
    );
    final isOn = route != null;
    final spec = _lfoAmountSpec(param);

    return _ModLightControl(
      isOn: isOn,
      value: route?.amount ?? 0.0,
      min: spec.min,
      max: spec.max,
      onInteractionChanged: onInteractionChanged,
      onTapLight: () async {
        final lfos = controller.lfos;

        final String? chosen = await _showAssignLfoPopup(
          context: context,
          lfos: controller.lfos,
          currentLfoId: route?.lfoId,
        );

// Dismissed dialog = do nothing.
        if (chosen == null) return;

        if (chosen == _assignNoneKey) {
          final oldLfoId = route?.lfoId;

          controller.clearRouteForStrokeParam(
            layerId,
            groupIndex,
            strokeId,
            param,
          );

          if (oldLfoId != null) {
            controller.deleteAutoPresetLfoIfUnused(oldLfoId);
          }

          return;
        }

        final preset = _presetFromChoiceKey(chosen);

        if (preset != null) {
          final existingRoute = controller.findRouteForStrokeParam(
            layerId,
            groupIndex,
            strokeId,
            param,
          );

          if (existingRoute != null &&
              controller.isAutoPresetManagedLfo(existingRoute.lfoId)) {
            controller.applyQuickPresetToLfo(
              existingRoute.lfoId,
              preset,
              autoPresetManaged: true,
            );
          } else {
            final newLfoId = controller.createQuickPresetLfo(preset);

            final oldLfoId = route?.lfoId;

            controller.upsertRouteForStrokeParam(
              layerId: layerId,
              strokeId: strokeId,
              groupIndex: groupIndex,
              param: param,
              lfoId: chosen,
            );

            if (oldLfoId != null && oldLfoId != chosen) {
              controller.deleteAutoPresetLfoIfUnused(oldLfoId);
            }
          }

          return;
        }

        controller.upsertRouteForStrokeParam(
          layerId: layerId,
          strokeId: strokeId,
          groupIndex: groupIndex,
          param: param,
          lfoId: chosen,
        );
      },
      onChanged: (v) {
        final r = route;
        if (r == null) return;
        controller.setRouteAmount(r.id, v);
      },
    );
  }
}

Future<void> _promptRenameLayer(
  BuildContext context,
  canvas_state.CanvasController controller,
  CanvasLayer layer,
) async {
  final textController = TextEditingController(text: layer.name);

  final String? result = await showDialog<String?>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1C1C24),
        title:
            const Text('Rename layer', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Layer name',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  if (result?.isNotEmpty == true) {
    controller.renameLayer(layer.id, result!);
  }
}

Future<void> _promptRenameStroke(
  BuildContext context, {
  required canvas_state.CanvasController controller,
  required String layerId,
  required int groupIndex,
  required Stroke stroke,
}) async {
  final textController = TextEditingController(text: stroke.name);

  final String? result = await showDialog<String?>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1C1C24),
        title:
            const Text('Rename stroke', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Stroke name',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  if (result?.isNotEmpty == true) {
    controller.renameStrokeRef(layerId, groupIndex, stroke.id, result!);
  }
}

class _StrokeList extends ConsumerWidget {
  const _StrokeList({
    required this.layer,
    required this.layerId,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final CanvasLayer layer;
  final String layerId;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    final int gi = 0;
    if (layer.groups.isEmpty) return const SizedBox.shrink();
    if (gi >= layer.groups.length) return const SizedBox.shrink();

    final group = layer.groups[gi];
    final strokes = group.strokes;

    if (strokes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'No strokes yet',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
        ),
      );
    }

    // UI order: top-most first (latest stroke first)
    final uiList = strokes.reversed.toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Strokes (${strokes.length})',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: uiList.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;

              final newUi = List<Stroke>.from(uiList);
              final moved = newUi.removeAt(oldIndex);
              newUi.insert(newIndex, moved);

              // Convert UI order back to underlying order (oldest->newest)
              final orderedIdsUnderlying =
                  newUi.reversed.map((s) => s.id).toList();

              controller.reorderStrokesRef(layerId, gi, orderedIdsUnderlying);
            },
            itemBuilder: (context, index) {
              final s = uiList[index];

              final isSelected = controller.selectedStrokeId == s.id &&
                  controller.selectedLayerId == layerId &&
                  controller.selectedGroupIndex == gi;

              return _StrokeTile(
                key: ValueKey(s.id),
                index: index,
                controller: controller,
                layerTransform: layer.transform,
                groupTransform: group.transform,
                layerId: layerId,
                groupIndex: gi,
                stroke: s,
                isSelected: isSelected,
                onAnyKnobInteraction: onAnyKnobInteraction,
                onAnyKnobValueChanged: onAnyKnobValueChanged,
                onSelect: () => controller.selectStrokeRef(layerId, gi, s.id),
                onRename: () => _promptRenameStroke(
                  context,
                  controller: controller,
                  layerId: layerId,
                  groupIndex: gi,
                  stroke: s,
                ),
                onToggleVisible: () => controller.setStrokeVisibilityRef(
                  layerId,
                  gi,
                  s.id,
                  !s.visible,
                ),
                onDelete: () => controller.deleteStrokeRef(layerId, gi, s.id),
                onSizeChanged: (v) =>
                    controller.setStrokeSizeRef(layerId, gi, s.id, v),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StrokeTile extends StatefulWidget {
  const _StrokeTile({
    super.key,
    required this.index,
    required this.controller,
    required this.layerTransform,
    required this.groupTransform,
    required this.layerId,
    required this.groupIndex,
    required this.stroke,
    required this.isSelected,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
    required this.onSelect,
    required this.onRename,
    required this.onToggleVisible,
    required this.onDelete,
    required this.onSizeChanged,
  });

  final int index;

  final canvas_state.CanvasController controller;
  final LayerTransform layerTransform;
  final GroupTransform groupTransform;

  final String layerId;
  final int groupIndex;
  final Stroke stroke;

  final bool isSelected;

  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onToggleVisible;
  final VoidCallback onDelete;
  final ValueChanged<double> onSizeChanged;

  @override
  State<_StrokeTile> createState() => _StrokeTileState();
}

class _StrokeTileState extends State<_StrokeTile> {
  bool _expanded = false;

  double _tx = 0.0;
  double _ty = 0.0;
  double _rotDeg = 0.0;

  List<PointSample>? _basePts;
  Offset _pivot = Offset.zero;

  void _captureBaseline() {
    final pts = widget.stroke.points;
    _basePts = List<PointSample>.from(pts);
    _pivot = _boundsCenterOfPoints(pts);

    _tx = 0.0;
    _ty = 0.0;
    _rotDeg = 0.0;
  }

  Offset _boundsCenterOfPoints(List<PointSample> pts) {
    if (pts.isEmpty) return Offset.zero;

    double minX = pts.first.x, maxX = pts.first.x;
    double minY = pts.first.y, maxY = pts.first.y;

    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return Offset((minX + maxX) * 0.5, (minY + maxY) * 0.5);
  }

  Offset _worldToLocalDelta(Offset worldDelta) {
    final double rot =
        widget.layerTransform.rotation + widget.groupTransform.rotation;
    final double scale =
        widget.layerTransform.scale * widget.groupTransform.scale;

    final double c = math.cos(rot);
    final double s = math.sin(rot);

    double lx = c * worldDelta.dx + s * worldDelta.dy;
    double ly = -s * worldDelta.dx + c * worldDelta.dy;

    final double safeScale = (scale.abs() < 1e-9) ? 1e-9 : scale;
    lx /= safeScale;
    ly /= safeScale;

    return Offset(lx, ly);
  }

  List<PointSample> _applyTxRot({
    required List<PointSample> base,
    required Offset pivot,
    required double tx,
    required double ty,
    required double rotDeg,
  }) {
    final ang = rotDeg * math.pi / 180.0;
    final cosA = math.cos(ang);
    final sinA = math.sin(ang);

    final out = <PointSample>[];
    for (final p in base) {
      final vx = p.x - pivot.dx;
      final vy = p.y - pivot.dy;

      final rx = vx * cosA - vy * sinA;
      final ry = vx * sinA + vy * cosA;

      final nx = pivot.dx + rx + tx;
      final ny = pivot.dy + ry + ty;

      out.add(PointSample(nx, ny, p.t));
    }
    return out;
  }

  @override
  void didUpdateWidget(covariant _StrokeTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_expanded && oldWidget.stroke.points != widget.stroke.points) {
      _basePts = null;
    }

    if (oldWidget.stroke.id != widget.stroke.id) {
      _expanded = false;
      _basePts = null;
      _tx = 0.0;
      _ty = 0.0;
      _rotDeg = 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.stroke;

    final coreUi = (s.coreOpacity.clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);
    final radiusUi = (s.glowRadius.clamp(0.0, 1.0) * 300.0).clamp(0.0, 300.0);
    final glowOpUi = (s.glowOpacity.clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);
    final brightUi =
        (s.glowBrightness.clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);

    final baseBg = const Color(0xFF151524);
    final borderColor =
        widget.isSelected ? cs.primary.withValues(alpha: 0.70) : Colors.white10;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: borderColor, width: widget.isSelected ? 1.25 : 1),
        boxShadow: widget.isSelected
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          Stack(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onSelect,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ReorderableDragStartListener(
                          index: widget.index,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Color(s.color),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white24),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: s.visible
                                        ? Colors.white70
                                        : Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12,
                                    fontWeight: widget.isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: s.visible ? 'Hide stroke' : 'Show stroke',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onToggleVisible,
                        icon: Icon(
                          s.visible ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename stroke',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onRename,
                        icon: const Icon(Icons.edit, color: Colors.white70),
                      ),
                      IconButton(
                        tooltip: 'Delete stroke',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                      ),
                      IconButton(
                        tooltip: _expanded ? 'Hide' : 'Edit',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _expanded = !_expanded;
                            if (_expanded) {
                              _captureBaseline();
                            } else {
                              _basePts = null;
                            }
                          });
                        },
                        icon: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.isSelected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: cs.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      // Size
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeSize,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'Size',
                            value: s.size.clamp(0.5, 200.0),
                            min: 0.5,
                            max: 200.0,
                            defaultValue: 10.0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeSize,
                              );
                              if (route == null) return null;

                              final base = s.size.clamp(0.5, 200.0).toDouble();
                              final depthPct = (route.amount / 100.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct >= 0.0) return base;

                              final availableToMin = base - 0.5;
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(0.5, 200.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeSize,
                              );
                              if (route == null) return null;

                              final base = s.size.clamp(0.5, 200.0).toDouble();
                              final depthPct = (route.amount / 100.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct <= 0.0) return base;

                              final availableToMax = 200.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(0.5, 200.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: widget.controller.previewStrokeParamValue(
                              widget.layerId,
                              s.id,
                              LfoParam.strokeSize,
                              s.size.clamp(0.5, 200.0).toDouble(),
                            ),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeSize,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => v.toStringAsFixed(1),
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                widget.controller.beginStrokeSizeKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                            ),
                            onChangeEnd: () =>
                                widget.controller.endStrokeSizeKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                            ),
                            onChanged: (v) {
                              widget.onAnyKnobValueChanged();
                              widget.onSizeChanged(v);
                            },
                          ),
                        ],
                      ),

                      // X
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeX,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'X',
                            value: _tx.clamp(-500, 500),
                            min: -500,
                            max: 500,
                            defaultValue: 0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeX,
                              );
                              if (route == null) return null;

                              final base = _tx.clamp(-500.0, 500.0).toDouble();
                              final depthPct = (route.amount / 500.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - (-500.0);
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(-500.0, 500.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeX,
                              );
                              if (route == null) return null;

                              final base = _tx.clamp(-500.0, 500.0).toDouble();
                              final depthPct = (route.amount / 500.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 500.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(-500.0, 500.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: widget.controller.previewStrokeParamValue(
                              widget.layerId,
                              s.id,
                              LfoParam.strokeX,
                              _tx.clamp(-500.0, 500.0).toDouble(),
                            ),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeX,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => v.toStringAsFixed(0),
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                _beginStrokeTransformKnob('Stroke X'),
                            onChangeEnd: _endStrokeTransformKnob,
                            onChanged: (v) {
                              widget.onAnyKnobValueChanged();
                              setState(() => _tx = v);
                              _previewStrokeTransformNoHistory();
                            },
                          ),
                        ],
                      ),

                      // Y
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeY,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'Y',
                            value: _ty.clamp(-500, 500),
                            min: -500,
                            max: 500,
                            defaultValue: 0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeY,
                              );
                              if (route == null) return null;

                              final base = _ty.clamp(-500.0, 500.0).toDouble();
                              final depthPct = (route.amount / 500.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - (-500.0);
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(-500.0, 500.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeY,
                              );
                              if (route == null) return null;

                              final base = _ty.clamp(-500.0, 500.0).toDouble();
                              final depthPct = (route.amount / 500.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 500.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(-500.0, 500.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: widget.controller.previewStrokeParamValue(
                              widget.layerId,
                              s.id,
                              LfoParam.strokeY,
                              _ty.clamp(-500.0, 500.0).toDouble(),
                            ),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeY,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => v.toStringAsFixed(0),
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                _beginStrokeTransformKnob('Stroke Y'),
                            onChangeEnd: _endStrokeTransformKnob,
                            onChanged: (v) {
                              widget.onAnyKnobValueChanged();
                              setState(() => _ty = v);
                              _previewStrokeTransformNoHistory();
                            },
                          ),
                        ],
                      ),

                      // Rotation
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeRotationDeg,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'Rot',
                            value: _rotDeg.clamp(-360, 360),
                            min: -360,
                            max: 360,
                            defaultValue: 0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeRotationDeg,
                              );
                              if (route == null) return null;

                              final base =
                                  _rotDeg.clamp(-360.0, 360.0).toDouble();
                              final depthPct = (route.amount / 360.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - (-360.0);
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(-360.0, 360.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeRotationDeg,
                              );
                              if (route == null) return null;

                              final base =
                                  _rotDeg.clamp(-360.0, 360.0).toDouble();
                              final depthPct = (route.amount / 360.0)
                                  .clamp(-1.0, 1.0)
                                  .toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 360.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(-360.0, 360.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: widget.controller.previewStrokeParamValue(
                              widget.layerId,
                              s.id,
                              LfoParam.strokeRotationDeg,
                              _rotDeg.clamp(-360.0, 360.0).toDouble(),
                            ),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeRotationDeg,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => '${v.toStringAsFixed(0)}°',
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                _beginStrokeTransformKnob('Stroke Rot'),
                            onChangeEnd: _endStrokeTransformKnob,
                            onChanged: (v) {
                              widget.onAnyKnobValueChanged();
                              setState(() => _rotDeg = v);
                              _previewStrokeTransformNoHistory();
                            },
                          ),
                        ],
                      ),

                      // Core
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeCoreOpacity,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'Core',
                            value: coreUi,
                            min: 0.0,
                            max: 100.0,
                            defaultValue: 86.0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeCoreOpacity,
                              );
                              if (route == null) return null;

                              final base = coreUi.clamp(0.0, 100.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - 0.0;
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(0.0, 100.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeCoreOpacity,
                              );
                              if (route == null) return null;

                              final base = coreUi.clamp(0.0, 100.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 100.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(0.0, 100.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: () {
                              final v =
                                  widget.controller.previewStrokeParamValue(
                                widget.layerId,
                                s.id,
                                LfoParam.strokeCoreOpacity,
                                s.coreOpacity.clamp(0.0, 1.0).toDouble(),
                              );
                              if (v == null) return null;
                              return (v * 100.0).clamp(0.0, 100.0).toDouble();
                            }(),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeCoreOpacity,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                widget.controller.beginStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              label: 'Stroke Core',
                              paramKey: 'core',
                            ),
                            onChangeEnd: () =>
                                widget.controller.endStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              paramKey: 'core',
                            ),
                            onChanged: (ui) {
                              widget.onAnyKnobValueChanged();
                              final nv = (ui / 100.0).clamp(0.0, 1.0);
                              widget.controller.setStrokeCoreOpacityRef(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                nv,
                              );
                            },
                          ),
                        ],
                      ),

                      // Radius
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeGlowRadius,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'Radius',
                            value: radiusUi,
                            min: 0.0,
                            max: 300.0,
                            defaultValue: 15.0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowRadius,
                              );
                              if (route == null) return null;

                              final base =
                                  radiusUi.clamp(0.0, 300.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - 0.0;
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(0.0, 300.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowRadius,
                              );
                              if (route == null) return null;

                              final base =
                                  radiusUi.clamp(0.0, 300.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 300.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(0.0, 300.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: () {
                              final v =
                                  widget.controller.previewStrokeParamValue(
                                widget.layerId,
                                s.id,
                                LfoParam.strokeGlowRadius,
                                s.glowRadius.clamp(0.0, 1.0).toDouble(),
                              );
                              if (v == null) return null;
                              return (v * 300.0).clamp(0.0, 300.0).toDouble();
                            }(),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowRadius,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => v.toStringAsFixed(0),
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                widget.controller.beginStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              label: 'Stroke Radius',
                              paramKey: 'radius',
                            ),
                            onChangeEnd: () =>
                                widget.controller.endStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              paramKey: 'radius',
                            ),
                            onChanged: (ui) {
                              widget.onAnyKnobValueChanged();
                              final nv = (ui / 300.0).clamp(0.0, 1.0);
                              widget.controller.setStrokeGlowRadiusRef(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                nv,
                              );
                            },
                          ),
                        ],
                      ),

                      // Glow Opacity
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeGlowOpacity,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'G Op',
                            value: glowOpUi,
                            min: 0.0,
                            max: 100.0,
                            defaultValue: 100.0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowOpacity,
                              );
                              if (route == null) return null;

                              final base =
                                  glowOpUi.clamp(0.0, 100.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - 0.0;
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(0.0, 100.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowOpacity,
                              );
                              if (route == null) return null;

                              final base =
                                  glowOpUi.clamp(0.0, 100.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 100.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(0.0, 100.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: () {
                              final v =
                                  widget.controller.previewStrokeParamValue(
                                widget.layerId,
                                s.id,
                                LfoParam.strokeGlowOpacity,
                                s.glowOpacity.clamp(0.0, 1.0).toDouble(),
                              );
                              if (v == null) return null;
                              return (v * 100.0).clamp(0.0, 100.0).toDouble();
                            }(),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowOpacity,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                widget.controller.beginStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              label: 'Glow Opacity',
                              paramKey: 'glowOp',
                            ),
                            onChangeEnd: () =>
                                widget.controller.endStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              paramKey: 'glowOp',
                            ),
                            onChanged: (ui) {
                              widget.onAnyKnobValueChanged();
                              final nv = (ui / 100.0).clamp(0.0, 1.0);
                              widget.controller.setStrokeGlowOpacityRef(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                nv,
                              );
                            },
                          ),
                        ],
                      ),

                      // Brightness
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StrokeModLight(
                            layerId: widget.layerId,
                            groupIndex: widget.groupIndex,
                            strokeId: s.id,
                            param: LfoParam.strokeGlowBrightness,
                            onInteractionChanged: widget.onAnyKnobInteraction,
                          ),
                          SynthKnob(
                            label: 'Bright',
                            value: brightUi,
                            min: 0.0,
                            max: 100.0,
                            defaultValue: 50.0,
                            modMinValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowBrightness,
                              );
                              if (route == null) return null;

                              final base =
                                  brightUi.clamp(0.0, 100.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct >= 0.0) {
                                return base;
                              }

                              final availableToMin = base - 0.0;
                              final end = (base + (availableToMin * depthPct))
                                  .clamp(0.0, 100.0)
                                  .toDouble();

                              return math.min(base, end).toDouble();
                            }(),
                            modMaxValue: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowBrightness,
                              );
                              if (route == null) return null;

                              final base =
                                  brightUi.clamp(0.0, 100.0).toDouble();
                              final depthPct =
                                  route.amount.clamp(-1.0, 1.0).toDouble();

                              if (depthPct <= 0.0) {
                                return base;
                              }

                              final availableToMax = 100.0 - base;
                              final end = (base + (availableToMax * depthPct))
                                  .clamp(0.0, 100.0)
                                  .toDouble();

                              return math.max(base, end).toDouble();
                            }(),
                            modValue: () {
                              final v =
                                  widget.controller.previewStrokeParamValue(
                                widget.layerId,
                                s.id,
                                LfoParam.strokeGlowBrightness,
                                s.glowBrightness.clamp(0.0, 1.0).toDouble(),
                              );
                              if (v == null) return null;
                              return (v * 100.0).clamp(0.0, 100.0).toDouble();
                            }(),
                            modDirection: () {
                              final route =
                                  widget.controller.findRouteForStrokeParam(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                LfoParam.strokeGlowBrightness,
                              );
                              if (route == null) return 0.0;
                              return route.amount;
                            }(),
                            valueFormatter: (v) => v.toStringAsFixed(0),
                            onInteractionChanged: widget.onAnyKnobInteraction,
                            onChangeStart: () =>
                                widget.controller.beginStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              label: 'Glow Brightness',
                              paramKey: 'bright',
                            ),
                            onChangeEnd: () =>
                                widget.controller.endStrokeParamKnob(
                              widget.layerId,
                              widget.groupIndex,
                              s.id,
                              paramKey: 'bright',
                            ),
                            onChanged: (ui) {
                              widget.onAnyKnobValueChanged();
                              final nv = (ui / 100.0).clamp(0.0, 1.0);
                              widget.controller.setStrokeGlowBrightnessRef(
                                widget.layerId,
                                widget.groupIndex,
                                s.id,
                                nv,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _beginStrokeTransformKnob(String label) {
    // Make sure baseline exists and matches current stroke points
    _captureBaseline();

    widget.controller.beginStrokeTransformKnob(
      widget.layerId,
      widget.groupIndex,
      widget.stroke.id,
      label: label,
      beforePoints: List<PointSample>.from(_basePts ?? const []),
    );
  }

  void _previewStrokeTransformNoHistory() {
    final base = _basePts;
    if (base == null) return;

    final localDelta = _worldToLocalDelta(Offset(_tx, -_ty));

    final newPts = _applyTxRot(
      base: base,
      pivot: _pivot,
      tx: localDelta.dx,
      ty: localDelta.dy,
      rotDeg: _rotDeg,
    );

    // ✅ live preview, but MUST NOT push history
    widget.controller.setStrokePointsPreviewRef(
      widget.layerId,
      widget.groupIndex,
      widget.stroke.id,
      newPts,
    );
  }

  void _endStrokeTransformKnob() {
    final base = _basePts;
    if (base == null) return;

    final localDelta = _worldToLocalDelta(Offset(_tx, -_ty));

    final afterPts = _applyTxRot(
      base: base,
      pivot: _pivot,
      tx: localDelta.dx,
      ty: localDelta.dy,
      rotDeg: _rotDeg,
    );

    widget.controller.endStrokeTransformKnob(
      widget.layerId,
      widget.groupIndex,
      widget.stroke.id,
      afterPoints: afterPts,
    );
  }
}

// ----------------------------------------------------------------------------------
// LFO panel + route UI (unchanged structurally, but param labels expanded)
// ----------------------------------------------------------------------------------

class _LfoPanel extends StatefulWidget {
  const _LfoPanel({
    required this.controller,
    required this.layers,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final canvas_state.CanvasController controller;
  final List<CanvasLayer> layers;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  State<_LfoPanel> createState() => _LfoPanelState();
}

class _LfoPanelState extends State<_LfoPanel> {
  final Set<String> _expandedLfos = <String>{};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lfos = widget.controller.lfos;
    final routes = widget.controller.lfoRoutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: const BoxDecoration(color: Color(0xFF11111C)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'LFOs',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${lfos.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add LFO',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add, color: cs.primary),
                onPressed: () => widget.controller.addLfo(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (lfos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No LFOs yet',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
              ),
            )
          else
            Column(
              children: [
                for (final lfo in lfos)
                  _LfoCard(
                    key: ValueKey(lfo.id),
                    lfoId: lfo.id,
                    isExpanded: _expandedLfos.contains(lfo.id),
                    lfoName: lfo.name,
                    enabled: lfo.enabled,
                    wave: lfo.wave,
                    rateHz: lfo.rateHz,
                    phase: lfo.phase,
                    offset: lfo.offset,
                    routes: routes.where((r) => r.lfoId == lfo.id).toList(),
                    layers: widget.layers,
                    activeLayerId: widget.controller.activeLayerId,
                    onToggleExpanded: () {
                      setState(() {
                        if (_expandedLfos.contains(lfo.id)) {
                          _expandedLfos.remove(lfo.id);
                        } else {
                          _expandedLfos.add(lfo.id);
                        }
                      });
                    },
                    controller: widget.controller,
                    onAnyKnobInteraction: widget.onAnyKnobInteraction,
                    onAnyKnobValueChanged: widget.onAnyKnobValueChanged,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LfoCard extends StatelessWidget {
  const _LfoCard({
    super.key,
    required this.lfoId,
    required this.isExpanded,
    required this.lfoName,
    required this.enabled,
    required this.wave,
    required this.rateHz,
    required this.phase,
    required this.offset,
    required this.routes,
    required this.layers,
    required this.activeLayerId,
    required this.controller,
    required this.onToggleExpanded,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final String lfoId;
  final bool isExpanded;

  final String lfoName;
  final bool enabled;
  final LfoWave wave;
  final double rateHz;
  final double phase;
  final double offset;

  final List<LfoRoute> routes;
  final List<CanvasLayer> layers;
  final String activeLayerId;

  final canvas_state.CanvasController controller;

  final VoidCallback onToggleExpanded;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151524),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Switch(
                value: enabled,
                onChanged: (v) => controller.setLfoEnabled(lfoId, v),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lfoName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              DropdownButton<LfoWave>(
                value: wave,
                dropdownColor: const Color(0xFF1C1C24),
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white),
                items: LfoWave.values
                    .map((w) => DropdownMenuItem(
                          value: w,
                          child: Text(w.label),
                        ))
                    .toList(),
                onChanged: (w) {
                  if (w == null) return;
                  controller.setLfoWave(lfoId, w);
                },
              ),
              IconButton(
                tooltip: 'Rename LFO',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit, color: Colors.white70),
                onPressed: () =>
                    _promptRenameLfo(context, controller, lfoId, lfoName),
              ),
              IconButton(
                tooltip: 'Delete LFO',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                onPressed: () => controller.removeLfo(lfoId),
              ),
              IconButton(
                tooltip: isExpanded ? 'Hide' : 'Edit',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white70,
                ),
                onPressed: onToggleExpanded,
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                SynthKnob(
                  label: 'Rate',
                  value: rateHz.clamp(0.01, 20.0),
                  min: 0.01,
                  max: 20.0,
                  defaultValue: 0.25,
                  valueFormatter: (v) => '${v.toStringAsFixed(2)} Hz',
                  onInteractionChanged: onAnyKnobInteraction,
                  onChanged: (v) {
                    onAnyKnobValueChanged();
                    controller.setLfoRate(lfoId, v);
                  },
                ),
                SynthKnob(
                  label: 'Phase',
                  value: (phase.clamp(0.0, 1.0) * 100.0),
                  min: 0.0,
                  max: 100.0,
                  defaultValue: 0.0,
                  valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                  onInteractionChanged: onAnyKnobInteraction,
                  onChanged: (ui) {
                    onAnyKnobValueChanged();
                    controller.setLfoPhase(lfoId, (ui / 100.0).clamp(0.0, 1.0));
                  },
                ),
                SynthKnob(
                  label: 'Offset',
                  value: offset.clamp(-1.0, 1.0),
                  min: -1.0,
                  max: 1.0,
                  defaultValue: 0.0,
                  valueFormatter: (v) => v.toStringAsFixed(2),
                  onInteractionChanged: onAnyKnobInteraction,
                  onChanged: (v) {
                    onAnyKnobValueChanged();
                    controller.setLfoOffset(lfoId, v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Routes',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: layers.isEmpty
                      ? null
                      : () => controller.addRouteToLayer(lfoId, activeLayerId),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('To active layer'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (routes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'No routes yet',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11),
                ),
              )
            else
              Column(
                children: [
                  for (final r in routes)
                    _RouteTile(
                      key: ValueKey(r.id),
                      route: r,
                      layers: layers,
                      controller: controller,
                      onAnyKnobInteraction: onAnyKnobInteraction,
                      onAnyKnobValueChanged: onAnyKnobValueChanged,
                    )
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    super.key,
    required this.route,
    required this.layers,
    required this.controller,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final LfoRoute route;
  final List<CanvasLayer> layers;
  final canvas_state.CanvasController controller;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final spec = _lfoAmountSpec(route.param);
    final double uiValue = route.amount.clamp(spec.min, spec.max);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Switch(
                value: route.enabled,
                onChanged: (v) => controller.setRouteEnabled(route.id, v),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButton<String>(
                  value: layers.any((l) => l.id == route.layerId)
                      ? route.layerId
                      : layers.first.id,
                  dropdownColor: const Color(0xFF1C1C24),
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: Colors.white),
                  items: layers
                      .map((l) => DropdownMenuItem(
                            value: l.id,
                            child:
                                Text(l.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    controller.setRouteLayer(route.id, id);
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<LfoParam>(
                value: route.param,
                dropdownColor: const Color(0xFF1C1C24),
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white),
                items: LfoParam.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(_lfoParamLabel(p)),
                        ))
                    .toList(),
                onChanged: (p) {
                  if (p == null) return;
                  controller.setRouteParam(route.id, p);

                  // Optional: if you want to “snap” amount into a sane range when param changes
                  final ns = _lfoAmountSpec(p);
                  final snapped = route.amount.clamp(ns.min, ns.max);
                  if (snapped != route.amount) {
                    controller.setRouteAmount(route.id, snapped);
                  }
                },
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: route.bipolar ? 'Bipolar (-1..1)' : 'Unipolar (0..1)',
                child: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      controller.setRouteBipolar(route.id, !route.bipolar),
                  icon: Icon(
                    route.bipolar ? Icons.swap_horiz : Icons.trending_up,
                    color: route.bipolar ? cs.primary : Colors.white70,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Delete route',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => controller.removeRoute(route.id),
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.center,
            child: SynthKnob(
              label: spec.label,
              value: uiValue,
              min: spec.min,
              max: spec.max,
              defaultValue: spec.def,
              valueFormatter: spec.formatter,
              onInteractionChanged: onAnyKnobInteraction,
              onChanged: (v) {
                onAnyKnobValueChanged();
                controller.setRouteAmount(route.id, v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _lfoParamLabel(LfoParam p) {
  switch (p) {
    // Layer
    case LfoParam.layerX:
      return 'Layer X';
    case LfoParam.layerY:
      return 'Layer Y';
    case LfoParam.layerScale:
      return 'Layer Scale';
    case LfoParam.layerRotationDeg:
      return 'Layer Rot';
    case LfoParam.layerOpacity:
      return 'Layer Opacity';

    // Stroke
    case LfoParam.strokeSize:
      return 'Stroke Size';
    case LfoParam.strokeX:
      return 'Stroke X';
    case LfoParam.strokeY:
      return 'Stroke Y';
    case LfoParam.strokeRotationDeg:
      return 'Stroke Rot';
    case LfoParam.strokeCoreOpacity:
      return 'Stroke Core';
    case LfoParam.strokeGlowRadius:
      return 'Stroke Radius';
    case LfoParam.strokeGlowOpacity:
      return 'Stroke Glow Op';
    case LfoParam.strokeGlowBrightness:
      return 'Stroke Bright';

    // Text
    case LfoParam.textX:
      return 'Text X';
    case LfoParam.textY:
      return 'Text Y';
    case LfoParam.textFontSize:
      return 'Text Font';
    case LfoParam.textScale:
      return 'Text Scale';
    case LfoParam.textRotationDeg:
      return 'Text Rot';
    case LfoParam.textOpacity:
      return 'Text Opacity';
    case LfoParam.textGlowRadius:
      return 'Text Glow Size';
    case LfoParam.textGlowOpacity:
      return 'Text Glow Op';
    case LfoParam.textGlowBrightness:
      return 'Text Bright';
    case LfoParam.textEdgeGlowWidth:
      return 'Text Edge W';
    case LfoParam.textEdgeGlowStrength:
      return 'Text Edge';
    case LfoParam.textLetterPhaseOffset:
      return 'Text Letter Off';
  }
}

_AmtSpec _lfoAmountSpec(LfoParam p) {
  switch (p) {
    // Positions in px
    case LfoParam.layerX:
    case LfoParam.layerY:
    case LfoParam.strokeX:
    case LfoParam.strokeY:
    case LfoParam.textX:
    case LfoParam.textY:
      return _AmtSpec(
        label: 'Amt',
        min: -500,
        max: 500,
        def: 50,
        formatter: (v) => v.toStringAsFixed(0),
      );

    // Rotation in degrees
    case LfoParam.layerRotationDeg:
    case LfoParam.strokeRotationDeg:
    case LfoParam.textRotationDeg:
      return _AmtSpec(
        label: 'Amt',
        min: -360,
        max: 360,
        def: 25,
        formatter: (v) => '${v.toStringAsFixed(0)}°',
      );

    // Scale
    case LfoParam.layerScale:
    case LfoParam.textScale:
      return _AmtSpec(
        label: 'Amt',
        min: -3.0,
        max: 3.0,
        def: 0.25,
        formatter: (v) => v.toStringAsFixed(2),
      );

    // Stroke / text size
    case LfoParam.strokeSize:
      return _AmtSpec(
        label: 'Amt',
        min: -100.0,
        max: 100.0,
        def: 10.0,
        formatter: (v) => v.toStringAsFixed(1),
      );

    case LfoParam.textFontSize:
      return _AmtSpec(
        label: 'Amt',
        min: -160.0,
        max: 160.0,
        def: 28.0,
        formatter: (v) => v.toStringAsFixed(0),
      );

    // Vital-style bounded params
    case LfoParam.layerOpacity:
    case LfoParam.strokeCoreOpacity:
    case LfoParam.strokeGlowOpacity:
    case LfoParam.strokeGlowBrightness:
    case LfoParam.textOpacity:
    case LfoParam.textGlowRadius:
    case LfoParam.textGlowOpacity:
    case LfoParam.textGlowBrightness:
    case LfoParam.textEdgeGlowWidth:
    case LfoParam.textEdgeGlowStrength:
    case LfoParam.textLetterPhaseOffset:
      return _AmtSpec(
        label: 'Amt',
        min: -1.0,
        max: 1.0,
        def: 0.25,
        formatter: (v) => v.toStringAsFixed(2),
      );

    case LfoParam.strokeGlowRadius:
      return _AmtSpec(
        label: 'Amt',
        min: -1.0,
        max: 1.0,
        def: 0.25,
        formatter: (v) => v.toStringAsFixed(2),
      );
  }
}

class _AmtSpec {
  final String label;
  final double min;
  final double max;
  final double def;
  final String Function(double) formatter;

  const _AmtSpec({
    required this.label,
    required this.min,
    required this.max,
    required this.def,
    required this.formatter,
  });
}

Future<void> _promptRenameLfo(
  BuildContext context,
  canvas_state.CanvasController controller,
  String lfoId,
  String currentName,
) async {
  final textController = TextEditingController(text: currentName);

  final String? result = await showDialog<String?>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1C1C24),
        title: const Text('Rename LFO', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'LFO name',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  if (result?.isNotEmpty == true) {
    controller.renameLfo(lfoId, result!);
  }
}
