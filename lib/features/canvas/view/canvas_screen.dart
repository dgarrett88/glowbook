import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/canvas_controller.dart';
import '../../../core/services/gallery_saver.dart';
import 'widgets/top_toolbar.dart';

class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key});

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final GlobalKey _repaintKey = GlobalKey();

  Future<void> _exportPng() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: boundary not found')),
          );
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: empty bytes')),
          );
        }
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final ts = DateTime.now().toIso8601String().replaceAll(':','-').split('.').first;
      final name = 'GlowBook_$ts.png';
      await GallerySaverService.savePngToGallery(bytes, filename: name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Gallery: $name')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvasControllerProvider);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: TopToolbar(controller: controller, onExport: _exportPng),
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => controller.pointerDown(event.pointer, event.localPosition),
        onPointerMove: (event) => controller.pointerMove(event.pointer, event.localPosition),
        onPointerUp: (event) => controller.pointerUp(event.pointer),
        child: RepaintBoundary(
          key: _repaintKey,
          child: CustomPaint(
            painter: controller.painter,
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}
