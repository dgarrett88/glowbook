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
import '../state/glow_blend.dart' as gb;
import 'layer_panel.dart';

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

  bool _showLayers = false;

  Future<_NewPageAction?> _showSaveOrDiscardDialog() {
    return showDialog<_NewPageAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('What would you like to do?'),
          content: const Text(
            'Save this drawing to continue later, or continue without saving?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_NewPageAction.cancel),
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
              child: const Text('Save and continue later'),
            ),
          ],
        );
      },
    );
  }

  void _toggleLayers() {
    setState(() {
      _showLayers = !_showLayers;
    });
  }

  Future<void> _saveCurrent(canvas_state.CanvasController controller) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final size = MediaQuery.of(context).size;
    final existing = _currentDoc;

    final doc = (existing ??
            doc_model.CanvasDoc(
              id: _currentDocId ?? simpleId(),
              name: existing?.name ?? 'Untitled',
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              width: existing?.width ?? size.width.toInt(),
              height: existing?.height ?? size.height.toInt(),
              background: existing?.background ??
                  doc_model.Background.solid(0xFF000000),
              symmetry: existing?.symmetry ?? doc_model.SymmetryMode.off,
            ))
        .copyWith(
      updatedAt: now,
      // Save current blend mode with this document.
      blendModeKey: gb.glowBlendToKey(gb.GlowBlendState.I.mode),
      // Save current background colour with this document.
      background: doc_model.Background.solid(controller.backgroundColor),
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

    controller.markSaved();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final controller = ref.read(canvas_state.canvasControllerProvider);
    final bundle = widget.initialDocument;
    if (bundle != null) {
      _currentDocId = bundle.doc.id;
      _currentDoc = bundle.doc;
      controller.loadFromBundle(bundle);
    } else {
      _currentDocId = null;
      _currentDoc = null;
      controller.newDocument();
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

  Future<void> _handleNewDocument(
      canvas_state.CanvasController controller) async {
    // If there are no unsaved changes, just start a fresh canvas.
    if (!controller.hasUnsavedChanges) {
      _currentDocId = null;
      _currentDoc = null;
      controller.newDocument();
      return;
    }

    final action = await _showSaveOrDiscardDialog();

    if (!mounted || action == null || action == _NewPageAction.cancel) {
      return;
    }

    if (action == _NewPageAction.saveAndNew) {
      await _saveCurrent(controller);
    }

    // For both saveAndNew and discardAndNew we do NOT delete any saved file.
    _currentDocId = null;
    _currentDoc = null;
    controller.newDocument();
  }

  Future<void> _handleExitToMainMenu(
      canvas_state.CanvasController controller) async {
    // If there are no unsaved changes, just go back to the menu.
    if (!controller.hasUnsavedChanges) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final action = await _showSaveOrDiscardDialog();

    if (!mounted || action == null || action == _NewPageAction.cancel) {
      return;
    }

    if (action == _NewPageAction.saveAndNew) {
      await _saveCurrent(controller);
    }
    // We never delete any saved document here.
    // "Continue without saving" means leave without saving current changes.

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    // ✅ Always use the controller's background colour.
    final Color canvasBg = Color(controller.backgroundColor);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: TopToolbar(
          controller: controller,
          onExport: _exportPng,
          onNew: () => _handleNewDocument(controller),
          onExitToMenu: () => _handleExitToMainMenu(controller),
        ),
      ),
      bottomNavigationBar: BottomDock(
        controller: controller,
        showLayers: _showLayers,
        onToggleLayers: _toggleLayers,
      ),
      body: Stack(
        children: [
          // 🎨 Main canvas
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => controller.pointerDown(
              event.pointer,
              event.localPosition,
            ),
            onPointerMove: (event) =>
                controller.pointerMove(event.pointer, event.localPosition),
            onPointerUp: (event) => controller.pointerUp(event.pointer),
            child: RepaintBoundary(
              key: _repaintKey,
              child: Container(
                color: canvasBg,
                child: CustomPaint(
                  painter: controller.painter,
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // 📚 Bottom layer panel
          if (_showLayers)
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.30, // 30% screen height
                widthFactor: 1.0, // full width
                child: const LayerPanel(),
              ),
            ),
        ],
      ),
    );
  }
}
