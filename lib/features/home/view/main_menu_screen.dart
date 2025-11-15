import 'package:flutter/material.dart';

import '../../../core/models/saved_document_info.dart';
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
        const SnackBar(content: Text('Could not open drawing. It may be corrupted.')),
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
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final d = docs[index];
                      final updated =
                          DateTime.fromMillisecondsSinceEpoch(d.updatedAt)
                              .toLocal();
                      final updatedStr =
                          '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')} '
                          '${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}';

                      return ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: Text(d.name),
                        subtitle: Text(
                          'Updated $updatedStr • ${d.strokeCount} strokes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDocument(d),
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
