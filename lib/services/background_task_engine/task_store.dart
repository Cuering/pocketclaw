import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'background_task.dart';

class TaskStore {
  TaskStore._();
  static final TaskStore instance = TaskStore._();

  static const String _boxName = 'background_tasks';
  Box<String>? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    debugPrint('🐾 TASK STORE: opened box with ${_box!.length} tasks');
  }

  Future<void> dispose() async {}

  Box<String> get box {
    final b = _box;
    if (b == null) {
      throw StateError(
          'TaskStore not initialized. Call init() in main() first.');
    }
    return b;
  }

  Box<String> get _requireBox => box;

  Future<void> save(BackgroundTask task) async {
    await _requireBox.put(task.id, jsonEncode(task.toJson()));
    debugPrint('🐾 TASK STORE: saved task "${task.title}" (${task.id})');
  }

  BackgroundTask? get(String id) {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return BackgroundTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🐾 TASK STORE: failed to parse task $id: $e');
      return null;
    }
  }

  List<BackgroundTask> getAll() {
    final b = _requireBox;
    final results = <BackgroundTask>[];
    for (final key in b.keys) {
      final raw = b.get(key as String);
      if (raw == null) continue;
      try {
        results.add(
            BackgroundTask.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('🐾 TASK STORE: skipping unparseable task $key: $e');
      }
    }
    return results;
  }

  List<BackgroundTask> getByStatus(TaskStatus status) =>
      getAll().where((t) => t.status == status).toList();

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
    debugPrint('🐾 TASK STORE: deleted task $id');
  }
}
