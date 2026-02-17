import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../../core/models/saved_document_info.dart';
import '../../../core/models/canvas_document_bundle.dart';
import '../../../core/models/canvas_doc.dart';
import '../../../core/models/stroke.dart';
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
  }

  void _refreshDocs() {
    setState(() {
      _docsFuture = _storage.listDocuments();
    });
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
                    if (bundle == null || bundle.strokes.isEmpty) {
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

class _StrokePreviewPainter extends CustomPainter {
  final CanvasDocumentBundle bundle;

  _StrokePreviewPainter(this.bundle);

  @override
  void paint(Canvas canvas, Size size) {
    final CanvasDoc doc = bundle.doc;
    final List<Stroke> strokes = bundle.strokes;

    if (doc.width <= 0 || doc.height <= 0 || strokes.isEmpty) {
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

    // Center horizontally
    final dx = (size.width - contentWidth) / 2.0;

    // Base vertical center
    double dy = (size.height - contentHeight) / 2.0;

    // If the content is taller than the card, bias the crop DOWN a bit
    // so we see more of the top and less of the bottom.
    final overflowY = contentHeight - size.height;
    if (overflowY > 0) {
      dy += overflowY * 0.55; // tweak 0.2 -> more/less bias if you like
    }

    for (final stroke in strokes) {
      final points = stroke.points;
      if (points.isEmpty) continue;

      final path = Path();
      final first = points.first;
      path.moveTo(
        dx + first.x * scale,
        dy + first.y * scale,
      );
      for (var i = 1; i < points.length; i++) {
        final p = points[i];
        path.lineTo(
          dx + p.x * scale,
          dy + p.y * scale,
        );
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke.size * scale
        ..color = Color(stroke.color);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter oldDelegate) {
    return oldDelegate.bundle != bundle;
  }
}
