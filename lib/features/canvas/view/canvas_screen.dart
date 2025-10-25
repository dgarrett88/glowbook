import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../canvas/state/canvas_controller.dart';
import 'widgets/top_toolbar.dart';
import 'widgets/bottom_dock.dart';

class CanvasScreen extends ConsumerWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvasControllerProvider);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: TopToolbar(controller: controller),
      ),
      body: Stack(
        children: [
          // Low-level pointer events to avoid multi-touch line-connecting
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => controller.pointerDown(e.pointer, e.localPosition),
            onPointerMove: (e) => controller.pointerMove(e.pointer, e.localPosition),
            onPointerUp:   (e) => controller.pointerUp(e.pointer),
            onPointerCancel: (e) => controller.pointerUp(e.pointer),
            child: CustomPaint(
              painter: controller.painter,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomDock(controller: controller),
          ),
        ],
      ),
    );
  }
}
