import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/conversation.dart';

/// Persists conversations as JSON strings keyed by conversation id in a
/// single Hive box. Singleton because there's one app-wide store.
///
/// Why JSON strings vs Hive TypeAdapters:
///   TypeAdapters need build_runner codegen. JSON-in-box is one more line
///   of overhead per read/write but zero build-tool setup.
///
/// All methods are async because Hive's open/get/put are async, even when
/// the underlying ops are fast (sub-millisecond for small docs).
class ConversationStore {
  ConversationStore._();
  static final ConversationStore instance = ConversationStore._();

  static const String _boxName = 'conversations';
  Box<String>? _box;

  /// One-time init. Called from main() before runApp. Idempotent.
  Future<void> init() async {
    if (_box != null) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    debugPrint(
      '🐾 STORE: opened box with ${_box!.length} conversations',
    );
  }

  Box<String> get _requireBox {
    final b = _box;
    if (b == null) {
      throw StateError(
        'ConversationStore not initialized. Call init() in main() first.',
      );
    }
    return b;
  }

  /// Load all conversations, sorted by updatedAt descending (newest first).
  /// O(N) — fine for thousands of conversations on a phone.
  Future<List<Conversation>> loadAll() async {
    final box = _requireBox;
    final results = <Conversation>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        results.add(Conversation.fromJson(json));
      } catch (e) {
        debugPrint('🐾 STORE: skipping unparseable conversation $key: $e');
      }
    }
    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }

  /// Insert or update. Uses conversation.id as the key.
  Future<void> save(Conversation conv) async {
    conv.updatedAt = DateTime.now();
    await _requireBox.put(conv.id, jsonEncode(conv.toJson()));
  }

  /// Delete a conversation by id. No-op if it doesn't exist.
  Future<void> delete(String id) async {
    await _requireBox.delete(id);
  }

  /// Fetch a single conversation by id, or null if missing/corrupt.
  Future<Conversation?> getById(String id) async {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return Conversation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Count of stored conversations. Cheap.
  int get count => _requireBox.length;
}
