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

  void _openNewCanvas() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CanvasScreen()))
        .then((_) => _refreshDocs());
  }

  Future<void> _openDocument(SavedDocumentInfo info) async {
    final bundle = await _storage.loadDocument(info.id);
    if (!mounted) return;

    if (bundle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open drawing. It may be corrupted.'),
        ),
      );
      _refreshDocs();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GlowBook'),
        centerTitle: true,
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

                return RefreshIndicator(
                  onRefresh: () async => _refreshDocs(),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12.0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final info = docs[index];
                      return _DocumentTile(
                        info: info,
                        storage: _storage,
                        onTap: () => _openDocument(info),
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

  const _DocumentTile({
    super.key,
    required this.info,
    required this.storage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail area takes whatever vertical space is available
          Expanded(
            child: Card(
              clipBehavior: Clip.hardEdge,
              child: FutureBuilder<CanvasDocumentBundle?>(
                future: storage.loadDocument(info.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  final bundle = snapshot.data;
                  if (bundle == null || bundle.strokes.isEmpty) {
                    return const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    );
                  }

                  return CustomPaint(
                    painter: _StrokePreviewPainter(bundle),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Fixed-height text area so it doesn't push past the cell
          SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                info.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall,
              ),
            ),
          ),
        ],
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
    final strokes = bundle.strokes;

    if (doc.width <= 0 || doc.height <= 0 || strokes.isEmpty) {
      return;
    }

    // Simple background support (solid color only for now).
    final params = doc.background.params;
    final colorValue = params['color'] as int?;
    if (colorValue != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color(colorValue),
      );
    }

    final sx = size.width / doc.width;
    final sy = size.height / doc.height;
    final scale = math.min(sx, sy);
    final dx = (size.width - doc.width * scale) / 2.0;
    final dy = (size.height - doc.height * scale) / 2.0;

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke.size * scale
        ..color = Color(stroke.color);

      final path = Path();
      final first = stroke.points.first;
      path.moveTo(
        dx + first.x * scale,
        dy + first.y * scale,
      );

      for (var i = 1; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        path.lineTo(
          dx + p.x * scale,
          dy + p.y * scale,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter oldDelegate) {
    return oldDelegate.bundle != bundle;
  }
}
