import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_controller.dart' as canvas_state;
import '../../../core/services/gallery_saver.dart';
import '../../../core/services/video_export_service.dart';
import '../../../core/services/document_storage.dart';
import '../../../core/models/canvas_doc.dart' as doc_model;
import '../../../core/utils/uuid.dart';
import 'widgets/top_toolbar.dart';
import 'widgets/bottom_dock.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_text_object.dart';
import '../state/canvas_preview_quality.dart';
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

enum _ExportAction { image, video }

enum _CanvasToolMode { brush, select, text }

class _VideoExportSettingsResult {
  final VideoExportOptions resolution;
  final VideoExportAspectOption aspect;
  final VideoExportFpsOption fps;
  final double durationSec;

  const _VideoExportSettingsResult({
    required this.resolution,
    required this.aspect,
    required this.fps,
    required this.durationSec,
  });
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final GlobalKey _repaintKey = GlobalKey();

  String? _currentDocId;
  doc_model.CanvasDoc? _currentDoc;

  bool _showLayers = false;
  bool _showLfos = false;

  _CanvasToolMode _activeToolMode = _CanvasToolMode.brush;
  String? _editingTextObjectId;
  final TextEditingController _textEditController = TextEditingController();
  final FocusNode _textEditFocusNode = FocusNode();
  final Set<int> _textHandledPointers = <int>{};
  int? _pendingTextEditPointer;
  Offset? _pendingTextEditStart;
  String? _pendingTextEditObjectId;
  double? _editingTextOriginalOpacity;

  static const List<String?> _fontChoices = <String?>[
    null,
    'Roboto',
    'Arial',
    'Times New Roman',
    'Courier New',
    'Georgia',
  ];

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

  CanvasDocumentBundle _buildCurrentBundle(
    canvas_state.CanvasController controller,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final size = MediaQuery.of(context).size;
    final existing = _currentDoc;

    final doc = (existing ??
            doc_model.CanvasDoc(
              id: _currentDocId ?? simpleId(),
              name: 'Untitled',
              createdAt: now,
              updatedAt: now,
              width: size.width.toInt(),
              height: size.height.toInt(),
              background: doc_model.Background.solid(0xFF000000),
              symmetry: doc_model.SymmetryMode.off,
            ))
        .copyWith(
      updatedAt: now,
      blendModeKey: gb.glowBlendToKey(gb.GlowBlendState.I.mode),
      background: doc_model.Background.solid(controller.backgroundColor),
    );

    return CanvasDocumentBundle(
      doc: doc,
      strokes: List.of(controller.strokes),
      textObjects: List.of(controller.textObjects),
      layers: List.of(controller.layers),
      activeLayerId: controller.activeLayerId,
      lfos: List.of(controller.lfos),
      lfoRoutes: List.of(controller.lfoRoutes),
    );
  }

  Future<bool> _saveRecoverySnapshot(
    canvas_state.CanvasController controller,
  ) async {
    try {
      final bundle = _buildCurrentBundle(controller);
      await DocumentStorage.instance.saveRecoveryBundle(bundle);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create recovery save: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _saveCurrent(canvas_state.CanvasController controller) async {
    final bundle = _buildCurrentBundle(controller);

    final savedId = await DocumentStorage.instance.saveBundle(
      bundle,
      existingId: _currentDocId,
    );

    _currentDocId = savedId;
    _currentDoc = bundle.doc;

    controller.markSaved();

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Drawing saved')));
    }
  }

  @override
  void initState() {
    super.initState();
    _textEditController.addListener(_handleTextEditControllerChanged);

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

  @override
  void dispose() {
    _textEditController.removeListener(_handleTextEditControllerChanged);
    _textEditController.dispose();
    _textEditFocusNode.dispose();
    super.dispose();
  }

  void _handleTextEditControllerChanged() {
    // The editable TextField is the live source of truth while typing.
    // Rebuild the overlay from the controller value so the active edit box
    // width/outline updates immediately with each character, without waiting
    // for the canvas renderer/model to repaint.
    if (!mounted || _editingTextObjectId == null) return;
    setState(() {});
  }

  void _setActiveToolMode(_CanvasToolMode mode) {
    _commitActiveTextEdit();

    final controller = ref.read(canvas_state.canvasControllerProvider);
    controller.setSelectionMode(mode == _CanvasToolMode.select);

    setState(() {
      _activeToolMode = mode;
      if (mode != _CanvasToolMode.select) {
        _showLayers = false;
      }
      if (mode != _CanvasToolMode.text) {
        _showLfos = false;
      }
    });
  }

  void _activateBrushTool() {
    _setActiveToolMode(_CanvasToolMode.brush);
  }

  void _toggleTextTool() {
    _setActiveToolMode(
      _activeToolMode == _CanvasToolMode.text
          ? _CanvasToolMode.brush
          : _CanvasToolMode.text,
    );
  }

  void _toggleSelectTool() {
    _setActiveToolMode(
      _activeToolMode == _CanvasToolMode.select
          ? _CanvasToolMode.brush
          : _CanvasToolMode.select,
    );
  }

  CanvasTextObject? _editingTextObject(canvas_state.CanvasController controller) {
    final id = _editingTextObjectId;
    if (id == null) return null;
    for (final obj in controller.textObjects) {
      if (obj.id == id) return obj;
    }
    return null;
  }

  Size _measureTextObject(
    CanvasTextObject obj, {
    String? textOverride,
    bool tight = false,
  }) {
    final text = (textOverride ?? obj.text);
    final style = TextStyle(
      fontFamily: obj.fontFamily,
      fontSize: obj.fontSize,
      height: obj.lineHeight,
      letterSpacing: obj.letterSpacing,
    );
    final tp = TextPainter(
      text: TextSpan(
        // Do not measure the editor from placeholder text. Empty text objects
        // get a small starter box, and real text objects hug their glyph bounds.
        text: text,
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textAlign: obj.textAlign,
    )..layout();

    // Keep this linked to the renderer's selected-text bounds:
    // selected box = glyph bounds + 8px padding on each side.
    // The active editor uses the same tight sizing so it does not open as a
    // generic wide TextField and make the word jump around.
    final horizontalPad = tight ? 38.0 : 56.0;
    final verticalPad = tight ? 26.0 : 24.0;
    final emptyStarterWidth = math.max(64.0, obj.fontSize * 0.85);
    final emptyStarterHeight = math.max(obj.fontSize + 16.0, 32.0);
    final minWidth = tight ? emptyStarterWidth : 140.0;
    final minHeight = tight ? emptyStarterHeight : obj.fontSize + 32.0;

    return Size(
      math.max(tp.width + horizontalPad, text.isEmpty ? minWidth : 0.0),
      math.max(tp.height + verticalPad, text.isEmpty ? minHeight : 0.0),
    );
  }

  Rect _textEditRect(
    CanvasTextObject obj, {
    String? textOverride,
    bool tight = false,
  }) {
    final size = _measureTextObject(
      obj,
      textOverride: textOverride,
      tight: tight,
    );
    final safeScale = obj.scale.abs().clamp(0.05, 20.0).toDouble();

    return Rect.fromCenter(
      center: obj.position,
      width: size.width * safeScale,
      height: size.height * safeScale,
    );
  }

  Rect _rotatedBounds(Rect rect, double radians) {
    if (radians.abs() < 0.0001) return rect;

    final c = rect.center;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    Offset rotate(Offset p) {
      final d = p - c;
      return Offset(
        c.dx + d.dx * cosA - d.dy * sinA,
        c.dy + d.dx * sinA + d.dy * cosA,
      );
    }

    final points = <Offset>[
      rotate(rect.topLeft),
      rotate(rect.topRight),
      rotate(rect.bottomRight),
      rotate(rect.bottomLeft),
    ];

    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;
    for (final p in points.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _pointInTextEditBox(CanvasTextObject obj, Offset pos) {
    final rect = _textEditRect(
      obj,
      textOverride: _textEditController.text,
      tight: true,
    ).inflate(18.0);

    final center = rect.center;
    final d = pos - center;
    final cosA = math.cos(-obj.rotation);
    final sinA = math.sin(-obj.rotation);
    final local = Offset(
      d.dx * cosA - d.dy * sinA,
      d.dx * sinA + d.dy * cosA,
    );

    return local.dx.abs() <= rect.width / 2.0 &&
        local.dy.abs() <= rect.height / 2.0;
  }

  void _startEditingTextObject(
    canvas_state.CanvasController controller,
    CanvasTextObject obj,
  ) {
    final wasEditingDifferentObject = _editingTextObjectId != obj.id;

    controller.selectTextObjectRef(obj.id);
    if (_activeToolMode != _CanvasToolMode.select) {
      controller.setSelectionMode(false);
    }
    _textEditController.text = obj.text;
    _textEditController.selection = TextSelection.collapsed(
      offset: _textEditController.text.length,
    );

    if (wasEditingDifferentObject) {
      _editingTextOriginalOpacity = obj.opacity;
      // Hide the canvas-rendered copy while the real editable TextField is on top.
      // This prevents the double-text effect while typing/editing.
      controller.updateTextObject(obj.copyWith(opacity: 0.0));
    }

    setState(() {
      _editingTextObjectId = obj.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _textEditFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _commitActiveTextEdit() {
    final controller = ref.read(canvas_state.canvasControllerProvider);
    final obj = _editingTextObject(controller);
    if (obj != null) {
      final restoredOpacity = _editingTextOriginalOpacity ?? obj.opacity;
      final trimmed = _textEditController.text.trim();
      if (trimmed.isEmpty) {
        controller.deleteTextObject(obj.id);
      } else {
        controller.updateTextObject(
          obj.copyWith(
            text: _textEditController.text,
            opacity: restoredOpacity,
          ),
        );
      }
    }
    _editingTextOriginalOpacity = null;
    _textEditFocusNode.unfocus();
    if (mounted && _editingTextObjectId != null) {
      setState(() => _editingTextObjectId = null);
    } else {
      _editingTextObjectId = null;
    }
  }

  void _queueSelectedTextEditTap(
    canvas_state.CanvasController controller,
    int pointer,
    Offset pos,
  ) {
    if (_editingTextObjectId != null) return;
    if (_activeToolMode != _CanvasToolMode.select) return;
    if (!controller.selectionMode) return;

    final selected = controller.selectedTextObject;
    if (selected == null) return;

    final rect = _rotatedBounds(_textEditRect(selected), selected.rotation).inflate(16.0);
    if (!rect.contains(pos)) return;

    _pendingTextEditPointer = pointer;
    _pendingTextEditStart = pos;
    _pendingTextEditObjectId = selected.id;
  }

  void _cancelPendingTextEditTap() {
    _pendingTextEditPointer = null;
    _pendingTextEditStart = null;
    _pendingTextEditObjectId = null;
  }

  void _maybeStartPendingTextEditTap(
    canvas_state.CanvasController controller,
    int pointer,
    Offset pos,
  ) {
    if (_pendingTextEditPointer != pointer) return;

    final objectId = _pendingTextEditObjectId;
    final start = _pendingTextEditStart;
    _cancelPendingTextEditTap();

    if (objectId == null || start == null) return;
    if ((pos - start).distance > 8.0) return;
    if (controller.selectedTextObjectId != objectId) return;

    final selected = controller.selectedTextObject;
    if (selected == null || selected.id != objectId) return;
    _startEditingTextObject(controller, selected);
  }

  bool _handleTextCanvasTap(
    canvas_state.CanvasController controller,
    Offset pos,
  ) {
    final editing = _editingTextObject(controller);
    if (editing != null) {
      if (!_pointInTextEditBox(editing, pos)) {
        _commitActiveTextEdit();
        return true;
      }
      return false;
    }

    if (_activeToolMode != _CanvasToolMode.text) return false;

    controller.selectAtWorld(pos);
    final hitText = controller.selectedTextObject;
    if (hitText != null) {
      _startEditingTextObject(controller, hitText);
      return true;
    }

    final obj = controller.addTextObject(
      text: '',
      position: pos,
      fontSize: 72.0,
    );
    _startEditingTextObject(controller, obj);
    return true;
  }

  void _updateEditingText(CanvasTextObject obj, String value) {
    // The TextEditingController listener rebuilds the overlay live. Do not
    // change the TextField key or push model updates per keystroke here, or the
    // editable field can lose focus and close the keyboard while typing.
  }

  void _updateEditingFontSize(CanvasTextObject obj, double fontSize) {
    ref.read(canvas_state.canvasControllerProvider).updateTextObject(
          obj.copyWith(fontSize: fontSize.clamp(8.0, 260.0).toDouble()),
        );
  }

  void _updateEditingFontFamily(CanvasTextObject obj, String? fontFamily) {
    ref.read(canvas_state.canvasControllerProvider).updateTextObject(
          obj.copyWith(
            fontFamily: fontFamily,
            clearFontFamily: fontFamily == null,
          ),
        );
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

    final Color canvasBg = Color(controller.effectiveCanvasBackgroundColor);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: TopToolbar(
          controller: controller,
          onExport: () => _showExportMenu(controller),
          onNew: () => _handleNewDocument(controller),
          onExitToMenu: () => _handleExitToMainMenu(controller),
        ),
      ),
      bottomNavigationBar: BottomDock(
        controller: controller,
        showLayers: _showLayers,
        onToggleLayers: _toggleLayers,
        onBrushTool: _activateBrushTool,
        onTextTool: _toggleTextTool,
        onSelectTool: _toggleSelectTool,
        brushToolActive: _activeToolMode == _CanvasToolMode.brush,
        textToolActive: _activeToolMode == _CanvasToolMode.text,
        selectToolActive: _activeToolMode == _CanvasToolMode.select,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final fullSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          controller.setCanvasSize(fullSize);

          final dpr = MediaQuery.devicePixelRatioOf(context);

          final previewMetrics = computeCanvasPreviewMetrics(
            fullLogicalSize: fullSize,
            devicePixelRatio: dpr,
            quality: controller.previewQuality,
          );

          controller.setPreviewMetrics(previewMetrics);

          final previewScale = previewMetrics.logicalScale;

          final previewLogicalSize = Size(
            fullSize.width * previewScale,
            fullSize.height * previewScale,
          );

          return Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _queueSelectedTextEditTap(
                    controller,
                    e.pointer,
                    e.localPosition,
                  );
                  if (controller.selectionMode) {
                    _selectionPointerId ??= e.pointer;
                    if (_selectionPointerId == e.pointer) {
                      _selectionPointerPos = e.localPosition;
                    }
                  }
                  if (_handleTextCanvasTap(controller, e.localPosition)) {
                    _textHandledPointers.add(e.pointer);
                    return;
                  }
                  _routePointerDown(controller, e.pointer, e.localPosition);
                },
                onPointerMove: (e) {
                  if (_pendingTextEditPointer == e.pointer) {
                    final start = _pendingTextEditStart;
                    if (start != null &&
                        (e.localPosition - start).distance > 8.0) {
                      _cancelPendingTextEditTap();
                    }
                  }
                  if (_textHandledPointers.contains(e.pointer)) return;
                  if (controller.selectionMode &&
                      _selectionPointerId == e.pointer) {
                    _selectionPointerPos = e.localPosition;
                  }
                  if (controller.isSelectionGesturing) return;
                  _routePointerMove(controller, e.pointer, e.localPosition);
                },
                onPointerUp: (e) {
                  if (_textHandledPointers.remove(e.pointer)) return;
                  if (controller.selectionMode &&
                      _selectionPointerId == e.pointer) {
                    _selectionPointerPos = e.localPosition;
                    _selectionPointerId = null;
                  }
                  _routePointerUp(controller, e.pointer);
                  _maybeStartPendingTextEditTap(
                    controller,
                    e.pointer,
                    e.localPosition,
                  );
                },
                onPointerCancel: (e) {
                  if (_pendingTextEditPointer == e.pointer) {
                    _cancelPendingTextEditTap();
                  }
                  if (_textHandledPointers.remove(e.pointer)) return;
                  if (controller.selectionMode &&
                      _selectionPointerId == e.pointer) {
                    _selectionPointerId = null;
                    _selectionPointerPos = null;
                  }
                  controller.cancelPointer(e.pointer);
                },
                child: Container(
                  color: canvasBg,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Transform.scale(
                        alignment: Alignment.topLeft,
                        scale: previewScale <= 0 ? 1.0 : (1.0 / previewScale),
                        filterQuality: FilterQuality.medium,
                        child: RepaintBoundary(
                          key: _repaintKey,
                          child: SizedBox(
                            width: previewLogicalSize.width,
                            height: previewLogicalSize.height,
                            child: CustomPaint(
                              painter: controller.painter,
                              size: previewLogicalSize,
                            ),
                          ),
                        ),
                      ),
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
                        _selectionPointerId = null;
                        _selectionPointerPos = null;
                      }
                    },
                  ),
                ),

              if (_editingTextObject(controller) != null)
                _buildTextEditingOverlay(
                  context,
                  controller,
                  _editingTextObject(controller)!,
                  fullSize,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextEditingOverlay(
    BuildContext context,
    canvas_state.CanvasController controller,
    CanvasTextObject obj,
    Size fullSize,
  ) {
    final liveText = _textEditController.text;
    final baseSize = _measureTextObject(
      obj,
      textOverride: liveText,
      tight: true,
    );
    final safeScale = obj.scale.abs().clamp(0.05, 20.0).toDouble();
    final scaledRect = _textEditRect(
      obj,
      textOverride: liveText,
      tight: true,
    );
    final rotatedBounds = _rotatedBounds(scaledRect, obj.rotation);

    final toolbarWidth = math
        .max(250.0, math.min(math.max(scaledRect.width, 250.0), fullSize.width - 16.0))
        .toDouble();
    final toolbarLeft = (obj.position.dx - toolbarWidth / 2.0)
        .clamp(8.0, math.max(8.0, fullSize.width - toolbarWidth - 8.0))
        .toDouble();
    final toolbarTop = (rotatedBounds.top - 48.0)
        .clamp(8.0, math.max(8.0, fullSize.height - 56.0))
        .toDouble();

    final glowAlpha = (obj.glowOpacity * obj.glowBrightness)
        .clamp(0.0, 1.0)
        .toDouble();
    final glowBlur = math.max(6.0, obj.glowRadius * 0.35);

    return Stack(
      children: [
        Positioned(
          left: toolbarLeft,
          top: toolbarTop,
          width: toolbarWidth,
          child: Material(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: obj.fontFamily,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF111111),
                        isDense: true,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        items: [
                          for (final font in _fontChoices)
                            DropdownMenuItem<String?>(
                              value: font,
                              child: Text(font ?? 'Default'),
                            ),
                        ],
                        onChanged: (font) => _updateEditingFontFamily(obj, font),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) {
                      _updateEditingFontSize(
                        obj,
                        obj.fontSize - d.delta.dy * 0.65,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_vert, size: 15, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            obj.fontSize.round().toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Keep the editable field unconstrained. Using Positioned.fill here gives
        // the TextField full-screen tight constraints, which makes the active edit
        // box appear huge even when our measured word bounds are small.
        Positioned(
          left: obj.position.dx,
          top: obj.position.dy,
          child: Transform.rotate(
            angle: obj.rotation,
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: safeScale,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: Offset(-baseSize.width / 2.0, -baseSize.height / 2.0),
                child: SizedBox(
                  width: baseSize.width,
                  height: baseSize.height,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.9),
                          width: 1.4,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: EditableText(
                        key: ValueKey('text-edit-${obj.id}'),
                        controller: _textEditController,
                        focusNode: _textEditFocusNode,
                        autofocus: true,
                        maxLines: 1,
                        textAlign: obj.textAlign,
                        cursorColor: Colors.cyanAccent,
                        backgroundCursorColor: Colors.cyanAccent.withValues(alpha: 0.25),
                        style: TextStyle(
                          fontFamily: obj.fontFamily,
                          fontSize: obj.fontSize,
                          height: obj.lineHeight,
                          letterSpacing: obj.letterSpacing,
                          color: Color(obj.fillColor),
                          shadows: obj.glowEnabled
                              ? [
                                  Shadow(
                                    color: Color(obj.glowColor).withValues(
                                      alpha: (0.45 * glowAlpha).clamp(0.0, 1.0),
                                    ),
                                    blurRadius: glowBlur * 2.2,
                                  ),
                                  Shadow(
                                    color: Color(obj.glowColor).withValues(
                                      alpha: (0.70 * glowAlpha).clamp(0.0, 1.0),
                                    ),
                                    blurRadius: glowBlur,
                                  ),
                                  Shadow(
                                    color: Color(obj.glowColor).withValues(
                                      alpha: (0.85 * glowAlpha).clamp(0.0, 1.0),
                                    ),
                                    blurRadius: math.max(4.0, glowBlur * 0.35),
                                  ),
                                ]
                              : null,
                        ),
                        onChanged: (value) => _updateEditingText(obj, value),
                        onSubmitted: (_) => _commitActiveTextEdit(),
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showExportMenu(
    canvas_state.CanvasController controller,
  ) async {
    final action = await showModalBottomSheet<_ExportAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Export',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Save image to gallery'),
                subtitle: const Text('PNG snapshot'),
                onTap: () => Navigator.of(context).pop(_ExportAction.image),
              ),
              ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: const Text('Export video'),
                subtitle: const Text('MP4 animation'),
                onTap: () => Navigator.of(context).pop(_ExportAction.video),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _ExportAction.image:
        await _exportPng();
        break;

      case _ExportAction.video:
        final settings = await _showVideoExportSettingsSheet();
        if (!mounted || settings == null) return;

        await _exportVideo(
          controller,
          settings.resolution,
          settings.aspect,
          settings.fps,
          settings.durationSec,
        );
        break;
    }
  }

  Future<_VideoExportSettingsResult?> _showVideoExportSettingsSheet() async {
    return showModalBottomSheet<_VideoExportSettingsResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var selectedResolution = VideoExportOptions.p360;
        var selectedAspect = VideoExportAspectOption.current;
        var selectedFps = VideoExportFpsOption.fps30;
        var durationSec = 15.0;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final totalFrames = (durationSec * selectedFps.fps).round();

            String frameWarning() {
              if (totalFrames >= 1800) {
                return 'Large export: this may take a while.';
              }
              if (totalFrames >= 900) {
                return 'Medium-large export.';
              }
              return 'Good for quick exports.';
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.movie_outlined),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Export Video',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Resolution',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in VideoExportOptions.values)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: selectedResolution == option,
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedResolution = option;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Aspect Ratio',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in VideoExportAspectOption.values)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: selectedAspect == option,
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedAspect = option;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Frame Rate',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in VideoExportFpsOption.values)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: selectedFps == option,
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedFps = option;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Duration',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            '${durationSec.toStringAsFixed(1)} sec',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        min: 1.0,
                        max: 60.0,
                        divisions: 590,
                        value: durationSec,
                        label: '${durationSec.toStringAsFixed(1)} sec',
                        onChanged: (v) {
                          setSheetState(() {
                            durationSec = v.clamp(1.0, 60.0).toDouble();
                          });
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final quick in [
                            3.0,
                            5.0,
                            10.0,
                            15.0,
                            30.0,
                            60.0
                          ])
                            ActionChip(
                              label: Text('${quick.round()}s'),
                              onPressed: () {
                                setSheetState(() {
                                  durationSec = quick;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${selectedResolution.label} · ${selectedAspect.label} · ${selectedFps.label} · $totalFrames frames',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(frameWarning()),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Export Video'),
                          onPressed: () {
                            Navigator.of(context).pop(
                              _VideoExportSettingsResult(
                                resolution: selectedResolution,
                                aspect: selectedAspect,
                                fps: selectedFps,
                                durationSec: durationSec,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<VideoExportOptions?> _showVideoResolutionMenu() async {
    return showModalBottomSheet<VideoExportOptions>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Video resolution',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Uses the current canvas aspect ratio'),
              ),
              for (final option in VideoExportOptions.values)
                ListTile(
                  leading: const Icon(Icons.high_quality_outlined),
                  title: Text(option.label),
                  subtitle: Text('${option.longestSidePx}px longest side'),
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<VideoExportFpsOption?> _showVideoFpsMenu() async {
    return showModalBottomSheet<VideoExportFpsOption>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Frame rate',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('60 FPS is smoother but takes longer to export'),
              ),
              for (final option in VideoExportFpsOption.values)
                ListTile(
                  leading: const Icon(Icons.slow_motion_video_outlined),
                  title: Text(option.label),
                  subtitle: Text('${option.fps} frames per second'),
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportVideo(
    canvas_state.CanvasController controller,
    VideoExportOptions options,
    VideoExportAspectOption aspectOption,
    VideoExportFpsOption fpsOption,
    double durationSec,
  ) async {
    double progress = 0.0;
    String stage = 'Starting export';
    int completedFrames = 0;
    int totalFrames = (durationSec * fpsOption.fps).round();
    Duration elapsed = Duration.zero;
    Duration? eta;

    final cancelToken = VideoExportCancelToken();

    StateSetter? dialogSetState;
    bool dialogOpen = false;

    String formatDuration(Duration d) {
      final totalSeconds = d.inSeconds;
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;

      if (minutes > 0) {
        return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
      }

      return '${seconds}s';
    }

    void refreshDialog() {
      final setter = dialogSetState;
      if (setter == null || !dialogOpen) return;
      setter(() {});
    }

    final recoverySaved = await _saveRecoverySnapshot(controller);
    if (!recoverySaved) return;

    controller.beginExportPauseLiveAnimation();

    try {
      dialogOpen = true;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              dialogSetState = setDialogState;

              final pct = (progress * 100).clamp(0, 100).round();
              final etaText = elapsed.inSeconds >= 3 && eta != null
                  ? formatDuration(eta!)
                  : 'Calculating...';

              return AlertDialog(
                title: Text(
                  'Exporting ${options.label} ${aspectOption.label} ${fpsOption.label}',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    Text('$pct% · $stage'),
                    const SizedBox(height: 8),
                    Text('Frames: $completedFrames / $totalFrames'),
                    Text('Elapsed: ${formatDuration(elapsed)}'),
                    Text('Time left: $etaText'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelToken.cancel();
                      stage = 'Cancelling...';
                      refreshDialog();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );

      final uri = await VideoExportService.exportCurrentCanvasVideo(
        controller: controller,
        options: options,
        aspectOption: aspectOption,
        fpsOption: fpsOption,
        durationSec: durationSec,
        cancelToken: cancelToken,
        onProgress: (p) {
          progress = p.clamp(0.0, 1.0);
        },
        onProgressInfo: (info) {
          progress = info.progress;
          stage = info.stage;
          completedFrames = info.completedFrames;
          totalFrames = info.totalFrames;
          elapsed = info.elapsed;
          eta = info.eta;
          refreshDialog();
        },
      );

      if (mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video saved: ${uri ?? 'Gallery'}')),
        );
      }
    } on VideoExportCancelledException {
      if (mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video export cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video export failed: $e')),
        );
      }
    } finally {
      controller.endExportPauseLiveAnimation();

      // If the app fully crashed/killed during export, this line will never run,
      // so the recovery file remains available next launch.
      try {
        await DocumentStorage.instance.clearRecoveryBundle();
      } catch (_) {}
    }
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
