import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'workflow_model.dart';

class WorkflowStore {
  WorkflowStore._();
  static final WorkflowStore instance = WorkflowStore._();

  static const String _boxName = 'workflows';
  Box<String>? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    debugPrint('🐾 WORKFLOW STORE: opened box with ${_box!.length} workflows');
  }

  Future<void> dispose() async {}

  Box<String> get box {
    final b = _box;
    if (b == null) {
      throw StateError(
          'WorkflowStore not initialized. Call init() in main() first.');
    }
    return b;
  }

  Box<String> get _requireBox => box;

  Future<void> save(WorkflowModel workflow) async {
    await _requireBox.put(workflow.id, jsonEncode(workflow.toJson()));
    debugPrint('🐾 WORKFLOW STORE: saved "${workflow.name}" (${workflow.id})');
  }

  WorkflowModel? get(String id) {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return WorkflowModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🐾 WORKFLOW STORE: failed to parse workflow $id: $e');
      return null;
    }
  }

  List<WorkflowModel> getAll() {
    final b = _requireBox;
    final results = <WorkflowModel>[];
    for (final key in b.keys) {
      final raw = b.get(key as String);
      if (raw == null) continue;
      try {
        results.add(
            WorkflowModel.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('🐾 WORKFLOW STORE: skipping unparseable workflow $key: $e');
      }
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
    debugPrint('🐾 WORKFLOW STORE: deleted workflow $id');
  }
}
