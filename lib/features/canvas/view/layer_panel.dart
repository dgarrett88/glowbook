import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_controller.dart' as canvas_state;
import '../../../core/models/canvas_layer.dart';

import 'widgets/synth_knob.dart';

class LayerPanel extends ConsumerStatefulWidget {
  const LayerPanel({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<LayerPanel> createState() => _LayerPanelState();
}

class _LayerPanelState extends ConsumerState<LayerPanel> {
  final Set<String> _expanded = <String>{};

  // ✅ locks list scroll + reorder while knobs are touched
  final ValueNotifier<bool> _knobIsActive = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _knobIsActive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);
    final layers = controller.layers;
    final activeId = controller.activeLayerId;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF101018).withOpacity(0.4),
            border: const Border(
              top: BorderSide(color: Color(0xFF303040)),
            ),
          ),
          child: Column(
            children: [
              _LayerPanelHeader(
                layerCount: layers.length,
                onAddLayer: controller.addLayer,
              ),
              const Divider(height: 1, color: Color(0xFF262636)),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _knobIsActive,
                  builder: (context, knobActive, _) {
                    return ReorderableListView.builder(
                      scrollController: widget.scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      buildDefaultDragHandles: false,
                      physics: knobActive
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: layers.length,
                      onReorder: (oldIndex, newIndex) {
                        // ✅ no reorder while interacting with knobs
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
                          reorderEnabled: !knobActive, // ✅
                          onAnyKnobInteraction: (active) {
                            _knobIsActive.value = active;
                          },
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
      rotationDegrees: t.rotation * 180.0 / 3.141592653589793,
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
        rotationDegrees: t.rotation * 180.0 / 3.141592653589793,
        scale: t.scale,
        opacity: t.opacity,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layer = widget.layer;

    final Color bgColor =
        widget.isActive ? const Color(0xFF1B2233) : Colors.transparent;
    final Color borderColor =
        widget.isActive ? cs.primary.withOpacity(0.4) : Colors.white10;
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
                fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );

      // ✅ Disable drag handle entirely while knobs are active
      if (!widget.reorderEnabled) return row;

      return ReorderableDragStartListener(
        index: widget.index,
        child: row,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  dragNameRow(),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$strokeCount',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onToggleVisible,
                    icon: Icon(
                      layer.visible ? Icons.visibility : Icons.visibility_off,
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
                      color:
                          layer.locked ? Colors.orangeAccent : Colors.white70,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename layer',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRename,
                    icon:
                        const Icon(Icons.edit, color: Colors.white70, size: 18),
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
          if (widget.isExpanded)
            _LayerTransformEditor(
              values: _values,
              onChanged: _updateAndSend,
              onAnyKnobInteraction: widget.onAnyKnobInteraction,
            ),
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
  });

  final _LayerTransformValues values;
  final ValueChanged<_LayerTransformValues> onChanged;
  final ValueChanged<bool> onAnyKnobInteraction;

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
                onChanged: (v) => onChanged(values.copyWith(x: v)),
              ),
              SynthKnob(
                label: 'Y',
                value: values.y.clamp(-500, 500),
                min: -500,
                max: 500,
                defaultValue: 0,
                valueFormatter: (v) => v.toStringAsFixed(0),
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) => onChanged(values.copyWith(y: v)),
              ),
              SynthKnob(
                label: 'Scale',
                value: values.scale.clamp(0.1, 5.0),
                min: 0.1,
                max: 5.0,
                defaultValue: 1.0,
                valueFormatter: (v) => v.toStringAsFixed(2),
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) => onChanged(values.copyWith(scale: v)),
              ),
              SynthKnob(
                label: 'Rot',
                value: values.rotationDegrees.clamp(-360, 360),
                min: -360,
                max: 360,
                defaultValue: 0.0,
                valueFormatter: (v) => '${v.toStringAsFixed(0)}°',
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) =>
                    onChanged(values.copyWith(rotationDegrees: v)),
              ),
              SynthKnob(
                label: 'Opacity',
                value: values.opacity.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                defaultValue: 1.0,
                valueFormatter: (v) => '${(v * 100).round()}%',
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) => onChanged(values.copyWith(opacity: v)),
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
