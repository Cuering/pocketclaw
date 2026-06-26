import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'skill_model.dart';

class SkillStore {
  SkillStore._();
  static final SkillStore instance = SkillStore._();

  static const String _boxName = 'skills';
  Box<String>? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    debugPrint('🐾 SKILL STORE: opened box with ${_box!.length} skills');
  }

  Future<void> dispose() async {}

  Box<String> get box {
    final b = _box;
    if (b == null) {
      throw StateError('SkillStore not initialized. Call init() in main() first.');
    }
    return b;
  }

  Box<String> get _requireBox => box;

  Future<void> save(SkillModel skill) async {
    await _requireBox.put(skill.id, jsonEncode(skill.toJson()));
    debugPrint('🐾 SKILL STORE: saved skill "${skill.name}" (${skill.id})');
  }

  SkillModel? get(String id) {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return SkillModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🐾 SKILL STORE: failed to parse skill $id: $e');
      return null;
    }
  }

  List<SkillModel> getAll() {
    final box = _requireBox;
    final results = <SkillModel>[];
    for (final key in box.keys) {
      final raw = box.get(key as String);
      if (raw == null) continue;
      try {
        results.add(SkillModel.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('🐾 SKILL STORE: skipping unparseable skill $key: $e');
      }
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
    debugPrint('🐾 SKILL STORE: deleted skill $id');
  }
}
