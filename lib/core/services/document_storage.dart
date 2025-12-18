import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/canvas_document_bundle.dart';
import '../models/saved_document_info.dart';

/// Persists editable drawings as JSON files in the app's document directory.
/// Layout:
///   /documents/index.json
///   /documents/doc_<id>.json
class DocumentStorage {
  DocumentStorage._();
  static final DocumentStorage instance = DocumentStorage._();

  Future<Directory> _documentsRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}${Platform.pathSeparator}documents');
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    return docsDir;
  }

  Future<File> _indexFile() async {
    final root = await _documentsRoot();
    return File('${root.path}${Platform.pathSeparator}index.json');
  }

  Future<File> _docFile(String id) async {
    final root = await _documentsRoot();
    return File('${root.path}${Platform.pathSeparator}doc_$id.json');
  }

  Future<List<SavedDocumentInfo>> loadIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) {
      return <SavedDocumentInfo>[];
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return <SavedDocumentInfo>[];
    }
    final decoded = json.decode(raw);
    if (decoded is! List) {
      return <SavedDocumentInfo>[];
    }
    return decoded
        .whereType<Map>()
        .map((e) => SavedDocumentInfo.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> _writeIndex(List<SavedDocumentInfo> items) async {
    final file = await _indexFile();
    final encoded = json.encode(items.map((e) => e.toJson()).toList());
    await file.writeAsString(encoded, flush: true);
  }

  int _strokeCountFromBundle(CanvasDocumentBundle bundle) {
    final layers = bundle.layers;
    if (layers != null && layers.isNotEmpty) {
      int count = 0;
      for (final layer in layers) {
        for (final g in layer.groups) {
          count += g.strokes.length;
        }
      }
      return count;
    }
    return bundle.strokes.length;
  }

  Future<String> saveBundle(
    CanvasDocumentBundle bundle, {
    String? existingId,
  }) async {
    final id = existingId ?? bundle.doc.id;
    final file = await _docFile(id);
    final payload = bundle.toJson();
    await file.writeAsString(json.encode(payload), flush: true);

    final index = await loadIndex();

    final meta = SavedDocumentInfo(
      id: id,
      name: bundle.doc.name,
      createdAt: bundle.doc.createdAt,
      updatedAt: bundle.doc.updatedAt,
      strokeCount: _strokeCountFromBundle(bundle),
      width: bundle.doc.width,
      height: bundle.doc.height,
    );

    final existingIdx = index.indexWhere((e) => e.id == id);
    if (existingIdx == -1) {
      index.add(meta);
    } else {
      index[existingIdx] = meta;
    }
    await _writeIndex(index);
    return id;
  }

  Future<CanvasDocumentBundle?> loadBundle(String id) async {
    final file = await _docFile(id);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = json.decode(raw) as Map;
    return CanvasDocumentBundle.fromJson(decoded.cast<String, dynamic>());
  }

  Future<void> renameDocument(String id, String newName) async {
    final bundle = await loadBundle(id);
    if (bundle == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedBundle = bundle.copyWith(
      doc: bundle.doc.copyWith(
        name: newName,
        updatedAt: now,
      ),
    );

    await saveBundle(updatedBundle, existingId: id);
  }

  Future<void> deleteDocument(String id) async {
    final file = await _docFile(id);
    if (await file.exists()) {
      await file.delete();
    }
    final index = await loadIndex();
    final next = index.where((e) => e.id != id).toList();
    await _writeIndex(next);
  }

  Future<void> deleteAllDocuments() async {
    final root = await _documentsRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  Future<List<SavedDocumentInfo>> listDocuments() {
    return loadIndex();
  }

  Future<CanvasDocumentBundle?> loadDocument(String id) {
    return loadBundle(id);
  }
}
