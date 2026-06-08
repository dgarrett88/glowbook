import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../../core/models/saved_document_info.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_doc.dart';
import '../../../core/models/stroke.dart';
import '../../../core/models/canvas_text_object.dart';
import '../../../core/models/canvas_layer.dart';
import '../../../core/services/document_storage.dart';
import '../../canvas/view/canvas_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final DocumentStorage _storage = DocumentStorage.instance;
  late Future<List<SavedDocumentInfo>> _docsFuture;

  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _docsFuture = _storage.listDocuments();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForRecovery();
    });
  }

  void _refreshDocs() {
    setState(() {
      _docsFuture = _storage.listDocuments();
    });
  }

  Future<void> _checkForRecovery() async {
    final hasRecovery = await _storage.hasRecoveryBundle();
    if (!mounted || !hasRecovery) return;

    final shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Restore unsaved work?'),
          content: const Text(
            'Animod found a recovery save from before an export or crash. '
            'Would you like to restore it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Discard'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (shouldRestore == true) {
      final bundle = await _storage.loadRecoveryBundle();

      if (!mounted) return;

      if (bundle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not restore recovery save.')),
        );
        await _storage.clearRecoveryBundle();
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CanvasScreen(initialDocument: bundle),
        ),
      );

      if (!mounted) return;

      // Clear only after the user has left the restored canvas.
      // If the app crashes while restoring/editing, recovery remains safer
      // if we later move this to an explicit save/clear flow.
      await _storage.clearRecoveryBundle();
      _refreshDocs();
      return;
    }

    await _storage.clearRecoveryBundle();
  }

  Future<void> _openNewCanvas() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CanvasScreen(),
      ),
    );

    if (mounted) {
      _refreshDocs();
    }
  }

  Future<void> _openDocument(SavedDocumentInfo info) async {
    final bundle = await _storage.loadDocument(info.id);
    if (bundle == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open drawing.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanvasScreen(initialDocument: bundle),
      ),
    );

    if (mounted) {
      _refreshDocs();
    }
  }

  // ===== MULTI-SELECT HELPERS =====

  void _enterSelection(SavedDocumentInfo info) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(info.id);
    });
  }

  void _toggleSelection(SavedDocumentInfo info) {
    setState(() {
      if (_selectedIds.contains(info.id)) {
        _selectedIds.remove(info.id);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedIds.add(info.id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmAndDeleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count drawing${count == 1 ? '' : 's'}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      for (final id in List<String>.from(_selectedIds)) {
        await _storage.deleteDocument(id);
      }
      _clearSelection();
      _refreshDocs();
    }
  }

  // ===== SINGLE DELETE / DUPLICATE / RENAME =====

  Future<void> _confirmAndDelete(SavedDocumentInfo info) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete drawing?'),
        content: Text('Are you sure you want to delete "${info.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _storage.deleteDocument(info.id);
      _refreshDocs();
    }
  }

  Future<void> _duplicateDocument(SavedDocumentInfo info) async {
    final bundle = await _storage.loadDocument(info.id);
    if (bundle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not duplicate drawing.')),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final newDoc = bundle.doc.copyWith(
      id: '${bundle.doc.id}_copy_$now',
      name: '${info.name} (copy)',
      createdAt: now,
      updatedAt: now,
    );

    final newBundle = CanvasDocumentBundle(
      doc: newDoc,
      strokes: List.of(bundle.strokes),
      textObjects: List.of(bundle.textObjects),

      // ✅ keep layered docs intact too
      layers: bundle.layers == null ? null : List.of(bundle.layers!),
      activeLayerId: bundle.activeLayerId,

      // ✅ keep LFO state
      lfos: bundle.lfos == null ? null : List.of(bundle.lfos!),
      lfoRoutes: bundle.lfoRoutes == null ? null : List.of(bundle.lfoRoutes!),
    );

    await _storage.saveBundle(newBundle);
    _refreshDocs();
  }

  Future<void> _renameDocument(SavedDocumentInfo info) async {
    final textController = TextEditingController(text: info.name);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename drawing'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final newName = result.trim();
    if (newName.isEmpty || newName == info.name) return;

    await _storage.renameDocument(info.id, newName);
    _refreshDocs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('GlowBook'),
        centerTitle: true,
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete selected',
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _confirmAndDeleteSelected(),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openNewCanvas,
                icon: const Icon(Icons.brush),
                label: const Text('Start new drawing'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<SavedDocumentInfo>>(
              future: _docsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Failed to load saved drawings.\nPull down to retry.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data ?? const <SavedDocumentInfo>[];

                if (docs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _refreshDocs(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              'No saved drawings yet.\nTap "Start new drawing" to begin.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final selectedCount = _selectedIds.length;

                return RefreshIndicator(
                  onRefresh: () async => _refreshDocs(),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12.0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.49, // was 0.8 – more height per tile
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final info = docs[index];
                      final isSelected = _selectedIds.contains(info.id);

                      final canShowRename =
                          _selectionMode && selectedCount == 1 && isSelected;

                      return _DocumentTile(
                        info: info,
                        storage: _storage,
                        selectionMode: _selectionMode,
                        isSelected: isSelected,
                        canShowRename: canShowRename,
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelection(info);
                          } else {
                            _openDocument(info);
                          }
                        },
                        onLongPress: () {
                          if (_selectionMode) {
                            _toggleSelection(info);
                          } else {
                            _enterSelection(info);
                          }
                        },
                        onDelete: () => _confirmAndDelete(info),
                        onDuplicate: () => _duplicateDocument(info),
                        onRename: () => _renameDocument(info),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final SavedDocumentInfo info;
  final DocumentStorage storage;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onRename;
  final bool selectionMode;
  final bool isSelected;
  final bool canShowRename;
  final VoidCallback? onLongPress;

  const _DocumentTile({
    super.key,
    required this.info,
    required this.storage,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
    required this.onRename,
    required this.selectionMode,
    required this.isSelected,
    required this.canShowRename,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final theme = Theme.of(context);

    final bool showHighlight = selectionMode && isSelected;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: showHighlight
              ? theme.colorScheme.primary.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail image
            Expanded(
              child: Card(
                clipBehavior: Clip.hardEdge,
                margin: EdgeInsets.zero,
                child: FutureBuilder<CanvasDocumentBundle?>(
                  future: storage.loadDocument(info.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }

                    final bundle = snapshot.data;
                    if (bundle == null || !_hasPreviewContent(bundle)) {
                      return const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                        ),
                      );
                    }

                    return CustomPaint(
                      painter: _StrokePreviewPainter(bundle),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Title directly under preview
            Text(
              info.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                fontSize: 18, // <--- adjust this
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 4),

            // Controls area
            if (selectionMode) ...[
              // Multiselect: highlight shows selection.
              // When exactly one is selected, show centred rename button.
              if (canShowRename)
                Center(
                  child: IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Rename',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onRename,
                  ),
                ),
            ] else ...[
              // Normal mode: centred duplicate + delete, shrink to content
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Duplicate',
                      onPressed: onDuplicate,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Delete',
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _hasPreviewContent(CanvasDocumentBundle bundle) {
  if (bundle.textObjects.any((t) => t.text.trim().isNotEmpty)) {
    return true;
  }

  final layers = bundle.layers;
  if (layers != null && layers.isNotEmpty) {
    for (final layer in layers) {
      if (!layer.visible) continue;
      for (final group in layer.groups) {
        if (group.strokes.isNotEmpty) return true;
      }
    }
  }

  return bundle.strokes.isNotEmpty;
}

class _StrokePreviewPainter extends CustomPainter {
  final CanvasDocumentBundle bundle;

  _StrokePreviewPainter(this.bundle);

  @override
  void paint(Canvas canvas, Size size) {
    final CanvasDoc doc = bundle.doc;

    if (doc.width <= 0 || doc.height <= 0) {
      return;
    }

    // Background (solid color)
    final params = doc.background.params;
    final colorValue = params['color'] as int?;
    if (colorValue != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color(colorValue),
      );
    }

    // COVER the thumbnail
    final sx = size.width / doc.width;
    final sy = size.height / doc.height;
    final scale = math.max(sx, sy);

    final contentWidth = doc.width * scale;
    final contentHeight = doc.height * scale;

    final dx = (size.width - contentWidth) / 2.0;
    double dy = (size.height - contentHeight) / 2.0;

    final overflowY = contentHeight - size.height;
    if (overflowY > 0) {
      dy += overflowY * 0.55;
    }

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final visibleLayerIds = <String>{};
    final layers = bundle.layers;

    if (layers != null && layers.isNotEmpty) {
      for (final layer in layers) {
        if (!layer.visible) continue;
        visibleLayerIds.add(layer.id);
        _paintLayerStrokes(canvas, layer);
      }
    } else {
      visibleLayerIds.addAll(bundle.textObjects.map((t) => t.layerId));
      for (final stroke in bundle.strokes) {
        _paintStroke(canvas, stroke);
      }
    }

    for (final text in bundle.textObjects) {
      if (text.text.trim().isEmpty) continue;
      if (visibleLayerIds.isNotEmpty && !visibleLayerIds.contains(text.layerId)) {
        continue;
      }

      LayerTransform? layerTransform;
      if (layers != null && layers.isNotEmpty) {
        for (final layer in layers) {
          if (layer.id == text.layerId) {
            layerTransform = layer.transform;
            break;
          }
        }
      }

      _paintTextObject(
        canvas,
        text,
        layerTransform: layerTransform,
      );
    }

    canvas.restore();
  }

  void _paintLayerStrokes(Canvas canvas, CanvasLayer layer) {
    if (!layer.visible) return;

    // Use the layer pivot when present; otherwise keep preview transform simple.
    final pivot = layer.transform.pivot ?? Offset.zero;
    canvas.save();
    _applyLayerTransform(canvas, layer.transform, pivot);

    for (final group in layer.groups) {
      canvas.save();
      canvas.translate(group.transform.position.dx, group.transform.position.dy);
      canvas.rotate(group.transform.rotation);
      canvas.scale(group.transform.scale, group.transform.scale);
      for (final stroke in group.strokes) {
        _paintStroke(
          canvas,
          stroke,
          opacity: (layer.transform.opacity * group.transform.opacity)
              .clamp(0.0, 1.0)
              .toDouble(),
        );
      }
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintStroke(Canvas canvas, Stroke stroke, {double opacity = 1.0}) {
    final points = stroke.points;
    if (points.isEmpty) return;

    final path = Path();
    final first = points.first;
    path.moveTo(first.x, first.y);
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      path.lineTo(p.x, p.y);
    }

    final color = Color(stroke.color).withOpacity(
      (Color(stroke.color).opacity * opacity).clamp(0.0, 1.0).toDouble(),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.size
      ..color = color;

    canvas.drawPath(path, paint);
  }

  void _paintTextObject(
    Canvas canvas,
    CanvasTextObject text, {
    LayerTransform? layerTransform,
  }) {
    final opacity = text.opacity.clamp(0.0, 1.0).toDouble();
    if (opacity <= 0.001) return;

    canvas.save();

    if (layerTransform != null) {
      final pivot = layerTransform.pivot ?? text.position;
      _applyLayerTransform(canvas, layerTransform, pivot);
    }

    canvas.translate(text.position.dx, text.position.dy);
    canvas.rotate(text.rotation);
    canvas.scale(text.scale, text.scale);

    final baseStyle = TextStyle(
      fontFamily: text.fontFamily,
      fontSize: text.fontSize,
      height: text.lineHeight,
      letterSpacing: text.letterSpacing,
    );

    TextPainter painterFor(Paint paint) {
      return TextPainter(
        text: TextSpan(
          text: text.text,
          style: baseStyle.copyWith(foreground: paint),
        ),
        textAlign: text.textAlign,
        textDirection: TextDirection.ltr,
      )..layout();
    }

    void paintText(Paint paint) {
      final tp = painterFor(paint);
      tp.paint(canvas, Offset(-tp.width / 2.0, -tp.height / 2.0));
    }

    if (text.glowEnabled && text.glowOpacity > 0.0 && text.glowRadius > 0.0) {
      final glowAlpha = (opacity * text.glowOpacity * 0.65)
          .clamp(0.0, 1.0)
          .toDouble();
      final glowColor = Color(text.glowColor).withOpacity(glowAlpha);
      final sigma = (text.glowRadius * 0.45).clamp(1.0, 40.0).toDouble();

      paintText(Paint()
        ..color = glowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma));
      paintText(Paint()
        ..color = glowColor.withOpacity((glowAlpha * 0.85).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * 0.45));
    }

    if (text.fillEnabled) {
      paintText(Paint()
        ..color = Color(text.fillColor).withOpacity(
          (Color(text.fillColor).opacity * opacity).clamp(0.0, 1.0).toDouble(),
        ));
    }

    if (text.outlineEnabled && text.outlineWidth > 0.0) {
      paintText(Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = text.outlineWidth
        ..color = Color(text.outlineColor).withOpacity(
          (Color(text.outlineColor).opacity * opacity * text.outlineOpacity)
              .clamp(0.0, 1.0)
              .toDouble(),
        ));
    }

    canvas.restore();
  }

  void _applyLayerTransform(
    Canvas canvas,
    LayerTransform transform,
    Offset pivot,
  ) {
    canvas.translate(
      pivot.dx + transform.position.dx,
      pivot.dy + transform.position.dy,
    );
    canvas.rotate(transform.rotation);
    canvas.scale(transform.scale, transform.scale);
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter oldDelegate) {
    return oldDelegate.bundle != bundle;
  }
}
