import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/canvas_controller.dart' as canvas_state;
import '../../../core/services/gallery_saver.dart';
import '../../../core/services/document_storage.dart';
import '../../../core/models/canvas_doc.dart' as doc_model;
import '../../../core/utils/uuid.dart';
import 'widgets/top_toolbar.dart';
import 'widgets/bottom_dock.dart';
import '../../../core/models/canvas_document_bundle.dart';

class CanvasScreen extends ConsumerStatefulWidget {
  final CanvasDocumentBundle? initialDocument;

  const CanvasScreen({
    super.key,
    this.initialDocument,
  });

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

enum _NewPageAction { saveAndNew, discardAndNew, cancel }

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final GlobalKey _repaintKey = GlobalKey();

  String? _currentDocId;
  doc_model.CanvasDoc? _currentDoc;

  @override
  void initState() {
    super.initState();
    final bundle = widget.initialDocument;
    if (bundle != null) {
      _currentDocId = bundle.doc.id;
      _currentDoc = bundle.doc;
      final controller = ref.read(canvas_state.canvasControllerProvider);
      controller.loadFromBundle(bundle);
    }
  }

  Future<void> _exportPng() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
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
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
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


  Future<void> _handleNewDocument(canvas_state.CanvasController controller) async {
    final action = await showDialog<_NewPageAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Start a new page?'),
          content: const Text(
            'What would you like to do with your current drawing?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_NewPageAction.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_NewPageAction.discardAndNew),
              child: const Text('Continue without saving'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(_NewPageAction.saveAndNew),
              child: const Text('Save to continue later'),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null || action == _NewPageAction.cancel) {
      return;
    }

    if (action == _NewPageAction.saveAndNew) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final size = MediaQuery.of(context).size;
      final existing = _currentDoc;

      final doc = (existing ?? doc_model.CanvasDoc(
        id: _currentDocId ?? simpleId(),
        name: existing?.name ?? 'Untitled',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        width: existing?.width ?? size.width.toInt(),
        height: existing?.height ?? size.height.toInt(),
        background:
            existing?.background ?? doc_model.Background.solid(0xFF000000),
        symmetry: existing?.symmetry ?? doc_model.SymmetryMode.off,
      )).copyWith(
        updatedAt: now,
      );

      final bundle = CanvasDocumentBundle(
        doc: doc,
        strokes: List.of(controller.strokes),
      );

      final storage = DocumentStorage.instance;
      final savedId = await storage.saveBundle(
        bundle,
        existingId: _currentDocId,
      );

      _currentDocId = savedId;
      _currentDoc = doc;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drawing saved to main menu')),
        );
      }
    } else if (action == _NewPageAction.discardAndNew) {
      final docId = _currentDocId;
      if (docId != null) {
        DocumentStorage.instance.deleteDocument(docId);
      }
    }

    _currentDocId = null;
    _currentDoc = null;
    controller.newDocument();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: TopToolbar(
          controller: controller,
          onExport: _exportPng,
          onNew: () => _handleNewDocument(controller),
        ),
      ),
      bottomNavigationBar: BottomDock(controller: controller),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) =>
            controller.pointerDown(event.pointer, event.localPosition),
        onPointerMove: (event) =>
            controller.pointerMove(event.pointer, event.localPosition),
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
