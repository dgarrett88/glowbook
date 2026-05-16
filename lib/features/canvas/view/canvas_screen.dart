import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    final Color canvasBg = Color(controller.effectiveCanvasBackgroundColor);

    return Scaffold(
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
