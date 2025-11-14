import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/canvas_controller.dart';
import '../../../core/services/document_storage.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_doc.dart' as cdoc;
import '../../../core/services/gallery_saver.dart';
import 'widgets/top_toolbar.dart';
import 'widgets/bottom_dock.dart';

class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key});

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}


enum _NewDocChoice { saveAndContinueLater, continueWithoutSaving, cancel }

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final GlobalKey _repaintKey = GlobalKey();

  final DocumentStorage _storage = DocumentStorage.instance;

  Future<_NewDocChoice?> _showNewDocDialog() {
    return showDialog<_NewDocChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Start a new drawing?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('What would you like to do with your current drawing?'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop(_NewDocChoice.saveAndContinueLater);
                },
                child: const Text('Save and continue later'),
              ),
              SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(ctx).pop(_NewDocChoice.continueWithoutSaving);
                },
                child: const Text('Continue without saving'),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(_NewDocChoice.cancel);
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleNewPressed() async {
    final choice = await _showNewDocDialog();
    if (choice == null || choice == _NewDocChoice.cancel) return;

    final controller = ref.read(canvasControllerProvider);

    if (choice == _NewDocChoice.saveAndContinueLater) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final doc = cdoc.CanvasDoc(
        id: 'doc_$now',
        name: 'GlowBook $now',
        createdAt: now,
        updatedAt: now,
        width: 0,
        height: 0,
        background: cdoc.Background.solid(0xFF000000),
        symmetry: cdoc.SymmetryMode.off,
      );

      final bundle = CanvasDocumentBundle(
        doc: doc,
        strokes: controller.strokes,
      );

      await _storage.saveBundle(bundle);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drawing saved for later')),
        );
      }
    }

    controller.newDocument();
  }



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
        child: TopToolbar(
          controller: controller,
          onExport: _exportPng,
          onNew: _handleNewPressed,
        ),
      ),
      bottomNavigationBar: BottomDock(controller: controller),
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
