import 'dart:ui';
import 'dart:math' as math;
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
import 'lfo_panel.dart';

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
  bool _showLfos = false;

  // Track finger-1 in selection mode so we can resume grab after pinch ends.
  int? _selectionPointerId;
  Offset? _selectionPointerPos;

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

  void _toggleLayers() => setState(() => _showLayers = !_showLayers);
  void _toggleLfos() => setState(() => _showLfos = !_showLfos);

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
      blendModeKey: gb.glowBlendToKey(gb.GlowBlendState.I.mode),
      background: doc_model.Background.solid(controller.backgroundColor),
    );

    final bundle = CanvasDocumentBundle(
      doc: doc,
      strokes: List.of(controller.strokes),
      layers: List.of(controller.layers),
      activeLayerId: controller.activeLayerId,
      // LFO persistence not added yet (v1 session-only).
    );

    final savedId = await DocumentStorage.instance.saveBundle(
      bundle,
      existingId: _currentDocId,
    );

    _currentDocId = savedId;
    _currentDoc = doc;

    controller.markSaved();

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Drawing saved')));
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
      controller.newDocument();
    }
  }

  void _routePointerDown(
      canvas_state.CanvasController controller, int pointer, Offset pos) {
    if (controller.isSelectionGesturing) return;

    if (controller.selectionMode) {
      controller.selectionPointerDown(pointer, pos);
    } else {
      controller.pointerDown(pointer, pos);
    }
  }

  void _routePointerMove(
      canvas_state.CanvasController controller, int pointer, Offset pos) {
    if (controller.isSelectionGesturing) return;

    if (controller.selectionMode) {
      controller.selectionPointerMove(pointer, pos);
    } else {
      controller.pointerMove(pointer, pos);
    }
  }

  void _routePointerUp(canvas_state.CanvasController controller, int pointer) {
    if (controller.selectionMode) {
      controller.selectionPointerUp(pointer);
    } else {
      controller.pointerUp(pointer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvas_state.canvasControllerProvider);

    final mode = gb.GlowBlendState.I.mode;
    final bool isMultiply = mode == gb.GlowBlend.multiply;

    final int bgArgb = (isMultiply && !controller.hasCustomBackground)
        ? 0xFFFFFFFF
        : controller.backgroundColor;

    final Color canvasBg = Color(bgArgb);

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          controller
              .setCanvasSize(Size(constraints.maxWidth, constraints.maxHeight));

          return Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  if (controller.selectionMode) {
                    _selectionPointerId ??= e.pointer;
                    if (_selectionPointerId == e.pointer) {
                      _selectionPointerPos = e.localPosition;
                    }
                  }
                  _routePointerDown(controller, e.pointer, e.localPosition);
                },
                onPointerMove: (e) {
                  if (controller.selectionMode &&
                      _selectionPointerId == e.pointer) {
                    _selectionPointerPos = e.localPosition;
                  }
                  if (controller.isSelectionGesturing) return;
                  _routePointerMove(controller, e.pointer, e.localPosition);
                },
                onPointerUp: (e) {
                  if (controller.selectionMode &&
                      _selectionPointerId == e.pointer) {
                    _selectionPointerPos = e.localPosition;
                    _selectionPointerId = null;
                  }
                  _routePointerUp(controller, e.pointer);
                },
                onPointerCancel: (e) {
                  if (controller.selectionMode &&
                      _selectionPointerId == e.pointer) {
                    _selectionPointerId = null;
                    _selectionPointerPos = null;
                  }
                  controller.cancelPointer(e.pointer);
                },
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

              if (_showLayers)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.30,
                    widthFactor: 1.0,
                    child: const LayerPanel(),
                  ),
                ),

              if (_showLfos)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.30,
                    widthFactor: 1.0,
                    child: const LfoPanel(),
                  ),
                ),

              // Always present in selection mode so gesture arena is reliable.
              if (controller.selectionMode)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onScaleStart: (d) {
                      if (!controller.hasSelection) return;
                      if (d.pointerCount < 2) return;

                      controller.selectionGestureStart(
                        focalWorld: d.localFocalPoint,
                        scale: 1.0,
                        rotation: 0.0,
                      );
                    },
                    onScaleUpdate: (d) {
                      if (!controller.hasSelection) return;

                      if (!controller.isSelectionGesturing &&
                          d.pointerCount < 2) return;

                      if (!controller.isSelectionGesturing &&
                          d.pointerCount >= 2) {
                        controller.selectionGestureStart(
                          focalWorld: d.localFocalPoint,
                          scale: 1.0,
                          rotation: 0.0,
                        );
                      }

                      controller.selectionGestureUpdate(
                        focalWorld: d.localFocalPoint,
                        scale: d.scale,
                        rotation: d.rotation,
                      );
                    },
                    onScaleEnd: (_) {
                      if (controller.isSelectionGesturing) {
                        controller.selectionGestureEnd();

                        final p = _selectionPointerPos;
                        if (p != null) {
                          controller.selectionResumeDragAt(p);
                        }
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportPng() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final name = 'GlowBook_${DateTime.now().millisecondsSinceEpoch}.png';

      await GallerySaverService.savePngToGallery(bytes, filename: name);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved: $name')));
      }
    } catch (_) {}
  }

  Future<void> _handleNewDocument(
      canvas_state.CanvasController controller) async {
    if (!controller.hasUnsavedChanges) {
      controller.newDocument();
      return;
    }

    final action = await _showSaveOrDiscardDialog();
    if (!mounted || action == null) return;

    if (action == _NewPageAction.saveAndNew) {
      await _saveCurrent(controller);
    }

    controller.newDocument();
  }

  Future<void> _handleExitToMainMenu(
      canvas_state.CanvasController controller) async {
    if (!controller.hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final action = await _showSaveOrDiscardDialog();
    if (!mounted || action == null) return;

    if (action == _NewPageAction.saveAndNew) {
      await _saveCurrent(controller);
    }

    if (mounted) Navigator.of(context).pop();
  }
}
