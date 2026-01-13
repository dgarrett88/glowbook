// lib/features/canvas/view/layer_panel.dart
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_controller.dart' as canvas_state;
import '../../../core/models/canvas_layer.dart';
import '../../../core/models/stroke.dart';

import 'widgets/synth_knob.dart';

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
    _fadeOut.dispose();
    _knobIsActive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101018).withOpacity(0.4),
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
                                  padding:
                                      const EdgeInsets.only(top: 10, bottom: 8),
                                  child: Center(
                                    child: Container(
                                      width: 44,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.25),
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
                                    height: 1, color: Color(0xFF262636)),
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
                        final bool isExpanded = _expanded.contains(layer.id);

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
                          onSelect: () => controller.setActiveLayer(layer.id),
                          onToggleVisible: () => controller.setLayerVisibility(
                              layer.id, !layer.visible),
                          onToggleLocked: () => controller.setLayerLocked(
                              layer.id, !layer.locked),
                          onDelete: isOnlyLayer
                              ? null
                              : () => controller.removeLayer(layer.id),
                          onRename: () =>
                              _promptRenameLayer(context, controller, layer),
                          onToggleExpanded: () {
                            setState(() {
                              if (isExpanded) {
                                _expanded.remove(layer.id);
                              } else {
                                _expanded.add(layer.id);
                              }
                            });
                          },
                          onTransformChanged: (tx) {
                            controller.setLayerPosition(layer.id, tx.x, tx.y);
                            controller.setLayerRotationDegrees(
                                layer.id, tx.rotationDegrees);
                            controller.setLayerScale(layer.id, tx.scale);
                            controller.setLayerOpacity(layer.id, tx.opacity);
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
    required this.onTransformChanged,
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
  final ValueChanged<_LayerTransformValues> onTransformChanged;

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
      y: t.position.dy,
      rotationDegrees: t.rotation * 180.0 / math.pi,
      scale: t.scale,
      opacity: t.opacity,
    );
  }

  void _updateAndSend(_LayerTransformValues v) {
    setState(() => _values = v);
    widget.onTransformChanged(v);
  }

  @override
  void didUpdateWidget(covariant _LayerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.transform != widget.layer.transform) {
      final t = widget.layer.transform;
      _values = _LayerTransformValues(
        x: t.position.dx,
        y: t.position.dy,
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
        widget.isActive ? cs.primary.withOpacity(0.65) : Colors.white10;

    final Color textColor =
        layer.visible ? Colors.white : Colors.white.withOpacity(0.5);

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
                  color: cs.primary.withOpacity(0.18),
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
                              ? Colors.white.withOpacity(0.25)
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
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
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
                        color: cs.primary.withOpacity(0.08),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.isExpanded) ...[
            _LayerTransformEditor(
              values: _values,
              onChanged: _updateAndSend,
              onAnyKnobInteraction: widget.onAnyKnobInteraction,
              onAnyKnobValueChanged: widget.onAnyKnobValueChanged,
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

class _LayerTransformEditor extends StatelessWidget {
  const _LayerTransformEditor({
    required this.values,
    required this.onChanged,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final _LayerTransformValues values;
  final ValueChanged<_LayerTransformValues> onChanged;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context) {
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
              SynthKnob(
                label: 'X',
                value: values.x.clamp(-500, 500),
                min: -500,
                max: 500,
                defaultValue: 0,
                valueFormatter: (v) => v.toStringAsFixed(0),
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) {
                  onAnyKnobValueChanged();
                  onChanged(values.copyWith(x: v));
                },
              ),
              SynthKnob(
                label: 'Y',
                value: values.y.clamp(-500, 500),
                min: -500,
                max: 500,
                defaultValue: 0,
                valueFormatter: (v) => v.toStringAsFixed(0),
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) {
                  onAnyKnobValueChanged();
                  onChanged(values.copyWith(y: v));
                },
              ),
              SynthKnob(
                label: 'Scale',
                value: values.scale.clamp(0.1, 5.0),
                min: 0.1,
                max: 5.0,
                defaultValue: 1.0,
                valueFormatter: (v) => v.toStringAsFixed(2),
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) {
                  onAnyKnobValueChanged();
                  onChanged(values.copyWith(scale: v));
                },
              ),
              SynthKnob(
                label: 'Rot',
                value: values.rotationDegrees.clamp(-360, 360),
                min: -360,
                max: 360,
                defaultValue: 0.0,
                valueFormatter: (v) => '${v.toStringAsFixed(0)}°',
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) {
                  onAnyKnobValueChanged();
                  onChanged(values.copyWith(rotationDegrees: v));
                },
              ),
              SynthKnob(
                label: 'Opacity',
                value: values.opacity.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                defaultValue: 1.0,
                valueFormatter: (v) => '${(v * 100).round()}%',
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) {
                  onAnyKnobValueChanged();
                  onChanged(values.copyWith(opacity: v));
                },
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

Future<void> _promptRenameLayer(
  BuildContext context,
  canvas_state.CanvasController controller,
  CanvasLayer layer,
) async {
  final textController = TextEditingController(text: layer.name);

  final result = await showDialog<String>(
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

  if (result != null && result.isNotEmpty) {
    controller.renameLayer(layer.id, result);
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

  final result = await showDialog<String>(
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

  if (result != null && result.isNotEmpty) {
    controller.renameStrokeRef(layerId, groupIndex, stroke.id, result);
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
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
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

          // ✅ Reorderable stroke list (no handles; long-press name area)
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

  void _commitTransform() {
    final base = _basePts;
    if (base == null) return;

    final localDelta = _worldToLocalDelta(Offset(_tx, _ty));

    final newPts = _applyTxRot(
      base: base,
      pivot: _pivot,
      tx: localDelta.dx,
      ty: localDelta.dy,
      rotDeg: _rotDeg,
    );

    widget.controller.updateStrokeById(
      widget.layerId,
      widget.groupIndex,
      widget.stroke.id,
      (s) => s.copyWith(points: newPts),
    );
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
        widget.isSelected ? cs.primary.withOpacity(0.70) : Colors.white10;

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
                  color: cs.primary.withOpacity(0.18),
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
                onTap: widget.onSelect, // ✅ just select/highlight (no fade)
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      // ✅ Big reorder grab area: long-press chip+name
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
                                        : Colors.white.withOpacity(0.45),
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

                      // ✅ Visibility toggle
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

                      // ✅ Rename
                      IconButton(
                        tooltip: 'Rename stroke',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onRename,
                        icon: const Icon(Icons.edit, color: Colors.white70),
                      ),

                      // Delete
                      IconButton(
                        tooltip: 'Delete stroke',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                      ),

                      // Expand/collapse
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
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // subtle overlay when selected (keeps tile solid but “lit”)
              if (widget.isSelected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: cs.primary.withOpacity(0.08),
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
                  SynthKnob(
                    label: 'Size',
                    value: s.size.clamp(0.5, 200.0),
                    min: 0.5,
                    max: 200.0,
                    defaultValue: 10.0,
                    valueFormatter: (v) => v.toStringAsFixed(1),
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (v) {
                      widget.onAnyKnobValueChanged();
                      widget.onSizeChanged(v);
                    },
                  ),
                  SynthKnob(
                    label: 'X',
                    value: _tx.clamp(-500, 500),
                    min: -500,
                    max: 500,
                    defaultValue: 0,
                    valueFormatter: (v) => v.toStringAsFixed(0),
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (v) {
                      widget.onAnyKnobValueChanged();
                      setState(() => _tx = v);
                      _commitTransform();
                    },
                  ),
                  SynthKnob(
                    label: 'Y',
                    value: _ty.clamp(-500, 500),
                    min: -500,
                    max: 500,
                    defaultValue: 0,
                    valueFormatter: (v) => v.toStringAsFixed(0),
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (v) {
                      widget.onAnyKnobValueChanged();
                      setState(() => _ty = v);
                      _commitTransform();
                    },
                  ),
                  SynthKnob(
                    label: 'Rot',
                    value: _rotDeg.clamp(-360, 360),
                    min: -360,
                    max: 360,
                    defaultValue: 0,
                    valueFormatter: (v) => '${v.toStringAsFixed(0)}°',
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (v) {
                      widget.onAnyKnobValueChanged();
                      setState(() => _rotDeg = v);
                      _commitTransform();
                    },
                  ),
                  SynthKnob(
                    label: 'Core',
                    value: coreUi,
                    min: 0.0,
                    max: 100.0,
                    defaultValue: 86.0,
                    valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (ui) {
                      widget.onAnyKnobValueChanged();
                      final nv = (ui / 100.0).clamp(0.0, 1.0);
                      widget.controller.updateStrokeById(
                        widget.layerId,
                        widget.groupIndex,
                        s.id,
                        (st) => st.copyWith(coreOpacity: nv),
                      );
                    },
                  ),
                  SynthKnob(
                    label: 'Radius',
                    value: radiusUi,
                    min: 0.0,
                    max: 300.0,
                    defaultValue: 15.0,
                    valueFormatter: (v) => v.toStringAsFixed(0),
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (ui) {
                      widget.onAnyKnobValueChanged();
                      final nv = (ui / 300.0).clamp(0.0, 1.0);
                      widget.controller.updateStrokeById(
                        widget.layerId,
                        widget.groupIndex,
                        s.id,
                        (st) => st.copyWith(glowRadius: nv),
                      );
                    },
                  ),
                  SynthKnob(
                    label: 'G Op',
                    value: glowOpUi,
                    min: 0.0,
                    max: 100.0,
                    defaultValue: 100.0,
                    valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (ui) {
                      widget.onAnyKnobValueChanged();
                      final nv = (ui / 100.0).clamp(0.0, 1.0);
                      widget.controller.updateStrokeById(
                        widget.layerId,
                        widget.groupIndex,
                        s.id,
                        (st) => st.copyWith(glowOpacity: nv),
                      );
                    },
                  ),
                  SynthKnob(
                    label: 'Bright',
                    value: brightUi,
                    min: 0.0,
                    max: 100.0,
                    defaultValue: 50.0,
                    valueFormatter: (v) => v.toStringAsFixed(0),
                    onInteractionChanged: widget.onAnyKnobInteraction,
                    onChanged: (ui) {
                      widget.onAnyKnobValueChanged();
                      final nv = (ui / 100.0).clamp(0.0, 1.0);
                      widget.controller.updateStrokeById(
                        widget.layerId,
                        widget.groupIndex,
                        s.id,
                        (st) => st.copyWith(glowBrightness: nv),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
