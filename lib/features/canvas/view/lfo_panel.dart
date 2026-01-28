// lib/features/canvas/view/lfo_panel.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_controller.dart' as canvas_state;
import '../../../core/models/canvas_layer.dart';
import '../../../core/models/lfo.dart';
import 'widgets/synth_knob.dart';

class LfoPanel extends ConsumerStatefulWidget {
  const LfoPanel({
    super.key,
    this.scrollController,
    this.showHeader = true,
  });

  final ScrollController? scrollController;
  final bool showHeader;

  @override
  ConsumerState<LfoPanel> createState() => _LfoPanelState();
}

class _LfoPanelState extends ConsumerState<LfoPanel> {
  final Set<String> _expanded = <String>{};

  final ValueNotifier<bool> _knobIsActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _fadeOut = ValueNotifier<bool>(false);
  bool _turnedSinceTouch = false;

  void _onKnobInteraction(bool active) {
    _knobIsActive.value = active;
    if (active) {
      _turnedSinceTouch = false;
      return;
    }
    if (_turnedSinceTouch) _fadeOut.value = false;
    _turnedSinceTouch = false;
  }

  void _onKnobValueChanged() {
    if (!_knobIsActive.value) return;
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
    final lfos = controller.lfos;
    final layers = controller.layers;

    return ValueListenableBuilder<bool>(
      valueListenable: _knobIsActive,
      builder: (context, knobActive, _) {
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
                      itemCount: lfos.length,
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
                                _LfoHeader(
                                  count: lfos.length,
                                  onAdd: () => controller.addLfo(),
                                ),
                                const Divider(
                                    height: 1, color: Color(0xFF262636)),
                              ],
                            )
                          : null,
                      onReorder: (oldIndex, newIndex) {
                        if (knobActive) return;
                        if (newIndex > oldIndex) newIndex -= 1;
                        controller.reorderLfos(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final lfo = lfos[index];
                        final isExpanded = _expanded.contains(lfo.id);

                        return _LfoTile(
                          key: ValueKey(lfo.id),
                          lfo: lfo,
                          index: index,
                          layers: layers,
                          reorderEnabled: !knobActive,
                          isExpanded: isExpanded,
                          onToggleExpanded: () {
                            setState(() {
                              if (isExpanded) {
                                _expanded.remove(lfo.id);
                              } else {
                                _expanded.add(lfo.id);
                              }
                            });
                          },
                          onAnyKnobInteraction: _onKnobInteraction,
                          onAnyKnobValueChanged: _onKnobValueChanged,
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

class _LfoHeader extends StatelessWidget {
  const _LfoHeader({required this.count, required this.onAdd});
  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(color: Color(0xFF11111C)),
      child: Row(
        children: [
          const Text(
            'LFO menu',
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
              '$count',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Add LFO',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, color: cs.primary),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _LfoTile extends ConsumerWidget {
  const _LfoTile({
    super.key,
    required this.lfo,
    required this.index,
    required this.layers,
    required this.reorderEnabled,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final Lfo lfo;
  final int index;
  final List<CanvasLayer> layers;

  final bool reorderEnabled;
  final bool isExpanded;

  final VoidCallback onToggleExpanded;
  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);
    final cs = Theme.of(context).colorScheme;

    final routes = controller.routesForLfo(lfo.id);

    Widget dragRow() {
      final row = Row(
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: lfo.enabled ? cs.primary : Colors.white24,
            ),
          ),
          Text(
            '#${index + 1}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              lfo.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: lfo.enabled ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
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
              lfo.wave.label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      );

      if (!reorderEnabled) return row;

      return ReorderableDragStartListener(
        index: index,
        child: row,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF121220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: lfo.enabled ? cs.primary.withOpacity(0.40) : Colors.white10,
          width: lfo.enabled ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      dragRow(),
                      const Spacer(),
                      IconButton(
                        tooltip: lfo.enabled ? 'Disable LFO' : 'Enable LFO',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            controller.setLfoEnabled(lfo.id, !lfo.enabled),
                        icon: Icon(
                          lfo.enabled ? Icons.toggle_on : Icons.toggle_off,
                          color: lfo.enabled ? cs.primary : Colors.white54,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename LFO',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _promptRenameLfo(context, controller, lfo),
                        icon: const Icon(Icons.edit,
                            color: Colors.white70, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Delete LFO',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => controller.removeLfo(lfo.id),
                        icon: const Icon(Icons.delete,
                            color: Colors.redAccent, size: 18),
                      ),
                      IconButton(
                        tooltip: isExpanded ? 'Hide' : 'Edit',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: onToggleExpanded,
                        icon: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (lfo.enabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: cs.primary.withOpacity(0.06),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  const SizedBox(height: 6),

                  // Wave selector row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Wave',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(width: 10),
                      _WavePicker(
                        value: lfo.wave,
                        onChanged: (w) => controller.setLfoWave(lfo.id, w),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SynthKnob(
                        label: 'Rate',
                        value: lfo.rateHz.clamp(0.01, 20.0),
                        min: 0.01,
                        max: 20.0,
                        defaultValue: 0.25,
                        valueFormatter: (v) =>
                            v < 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(1),
                        onInteractionChanged: onAnyKnobInteraction,
                        onChanged: (v) {
                          onAnyKnobValueChanged();
                          controller.setLfoRate(lfo.id, v);
                        },
                      ),
                      SynthKnob(
                        label: 'Phase',
                        value: (lfo.phase * 100.0).clamp(0.0, 100.0),
                        min: 0.0,
                        max: 100.0,
                        defaultValue: 0.0,
                        valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                        onInteractionChanged: onAnyKnobInteraction,
                        onChanged: (v) {
                          onAnyKnobValueChanged();
                          controller.setLfoPhase(
                              lfo.id, (v / 100.0).clamp(0.0, 1.0));
                        },
                      ),
                      SynthKnob(
                        label: 'Offset',
                        value: (lfo.offset * 100.0).clamp(-100.0, 100.0),
                        min: -100.0,
                        max: 100.0,
                        defaultValue: 0.0,
                        valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
                        onInteractionChanged: onAnyKnobInteraction,
                        onChanged: (v) {
                          onAnyKnobValueChanged();
                          controller.setLfoOffset(
                              lfo.id, (v / 100.0).clamp(-1.0, 1.0));
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Routes
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Routes (${routes.length})',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Add route to a layer',
                              iconSize: 18,
                              visualDensity: VisualDensity.compact,
                              onPressed: layers.isEmpty
                                  ? null
                                  : () => controller.addRouteToLayer(
                                        lfo.id,
                                        layers.last.id,
                                      ),
                              icon:
                                  const Icon(Icons.add, color: Colors.white70),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (routes.isEmpty)
                          Text(
                            'No routes yet',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 11),
                          )
                        else
                          ...routes.map((r) => _RouteRow(
                                lfo: lfo,
                                route: r,
                                layers: layers,
                                onAnyKnobInteraction: onAnyKnobInteraction,
                                onAnyKnobValueChanged: onAnyKnobValueChanged,
                              )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WavePicker extends StatelessWidget {
  const _WavePicker({required this.value, required this.onChanged});
  final LfoWave value;
  final ValueChanged<LfoWave> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LfoWave>(
      tooltip: 'Waveform',
      color: const Color(0xFF1C1C24),
      onSelected: onChanged,
      itemBuilder: (ctx) => [
        for (final w in LfoWave.values)
          PopupMenuItem<LfoWave>(
            value: w,
            child: Text(w.label, style: const TextStyle(color: Colors.white)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          value.label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ),
    );
  }
}

class _RouteRow extends ConsumerWidget {
  const _RouteRow({
    required this.lfo,
    required this.route,
    required this.layers,
    required this.onAnyKnobInteraction,
    required this.onAnyKnobValueChanged,
  });

  final Lfo lfo;
  final LfoRoute route;
  final List<CanvasLayer> layers;

  final ValueChanged<bool> onAnyKnobInteraction;
  final VoidCallback onAnyKnobValueChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    final layerName = layers
        .firstWhere(
          (l) => l.id == route.layerId,
          orElse: () => const CanvasLayer(
            id: 'missing',
            name: 'Missing layer',
            visible: true,
            locked: false,
            transform: LayerTransform(),
            groups: [],
          ),
        )
        .name;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151524),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: route.enabled ? 'Disable route' : 'Enable route',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    controller.setRouteEnabled(route.id, !route.enabled),
                icon: Icon(
                  route.enabled ? Icons.check_circle : Icons.circle_outlined,
                  color: route.enabled ? Colors.white70 : Colors.white24,
                ),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFF1C1C24),
                    value: route.layerId,
                    items: [
                      for (final l in layers)
                        DropdownMenuItem<String>(
                          value: l.id,
                          child: Text(l.name,
                              style: const TextStyle(color: Colors.white70)),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      controller.setRouteLayer(route.id, id);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                layerName,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              IconButton(
                tooltip: 'Remove route',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => controller.removeRoute(route.id),
                icon: const Icon(Icons.close, color: Colors.redAccent),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              SynthKnob(
                label: 'Depth',
                value: route.amount.clamp(0.0, 360.0),
                min: 0.0,
                max: 360.0,
                defaultValue: 25.0,
                valueFormatter: (v) => '${v.toStringAsFixed(0)}°',
                onInteractionChanged: onAnyKnobInteraction,
                onChanged: (v) {
                  onAnyKnobValueChanged();
                  controller.setRouteAmount(route.id, v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _promptRenameLfo(
  BuildContext context,
  canvas_state.CanvasController controller,
  Lfo lfo,
) async {
  final textController = TextEditingController(text: lfo.name);

  final result = await showDialog<String>(
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

  if (result != null && result.isNotEmpty) {
    controller.renameLfo(lfo.id, result);
  }
}
