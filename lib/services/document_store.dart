import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/document.dart';

/// Hive-backed list of documents the user has indexed into RAG.
/// Singleton — one store per app. Mirrors ConversationStore's pattern.
///
/// Why a separate metadata store when the chunks are in flutter_gemma's
/// vector DB:
///   - The vector store is keyed by chunk id, not document. We need a
///     fast way to enumerate "what docs has the user added to this chat".
///   - Vector store doesn't track document-level fields (name, added time).
///   - Deletion needs to know how many chunks to remove (chunkCount).
class DocumentStore {
  DocumentStore._();
  static final DocumentStore instance = DocumentStore._();

  static const String _boxName = 'documents';
  Box<String>? _box;

  /// One-time init. Call from main() after Hive.initFlutter().
  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    debugPrint('🐾 DOCSTORE: opened box with ${_box!.length} documents');
  }

  Box<String> get _requireBox {
    final b = _box;
    if (b == null) {
      throw StateError(
        'DocumentStore not initialized. Call init() in main() first.',
      );
    }
    return b;
  }

  /// All documents for a given conversation, sorted by createdAt desc.
  Future<List<Document>> loadForConversation(String conversationId) async {
    final box = _requireBox;
    final results = <Document>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final doc = Document.fromJson(json);
        if (doc.conversationId == conversationId) results.add(doc);
      } catch (e) {
        debugPrint('🐾 DOCSTORE: skipping unparseable doc $key: $e');
      }
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<void> save(Document doc) async {
    await _requireBox.put(doc.id, jsonEncode(doc.toJson()));
  }

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
  }

  Future<Document?> getById(String id) async {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return Document.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
