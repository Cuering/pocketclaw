import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/skill_engine/skill_store.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── SkillModel ─────────────────────────────────────────────────────────────

  group('SkillModel', () {
    final sampleSkill = SkillModel(
      id: 'test-id-1',
      name: 'Order Coffee',
      description: 'Opens Swiggy and searches coffee',
      version: '1.0',
      steps: [
        const PrimitiveStep(primitive: 'open_app', args: {'package': 'com.swiggy.android'}),
        const PrimitiveStep(primitive: 'tap', args: {'selector': 'Search bar'}),
      ],
      createdAt: DateTime(2026, 6, 26, 10, 0),
      useCount: 3,
    );

    test('toJson / fromJson round-trip preserves all fields', () {
      final json = sampleSkill.toJson();
      final restored = SkillModel.fromJson(json);
      expect(restored.id, 'test-id-1');
      expect(restored.name, 'Order Coffee');
      expect(restored.description, 'Opens Swiggy and searches coffee');
      expect(restored.version, '1.0');
      expect(restored.steps.length, 2);
      expect(restored.steps[0].primitive, 'open_app');
      expect(restored.steps[0].args['package'], 'com.swiggy.android');
      expect(restored.steps[1].primitive, 'tap');
      expect(restored.createdAt, DateTime(2026, 6, 26, 10, 0));
      expect(restored.useCount, 3);
    });

    test('fromJson uses defaults for optional fields', () {
      final json = {
        'id': 'x',
        'name': 'Test',
        'steps': [],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final skill = SkillModel.fromJson(json);
      expect(skill.description, '');
      expect(skill.version, '1.0');
      expect(skill.useCount, 0);
    });

    test('toJson steps include primitive and args', () {
      final json = sampleSkill.toJson();
      final steps = json['steps'] as List<dynamic>;
      expect(steps[0]['primitive'], 'open_app');
      expect((steps[0]['args'] as Map)['package'], 'com.swiggy.android');
    });
  });

  // ── SkillStore ─────────────────────────────────────────────────────────────

  group('SkillStore', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await SkillStore.instance.init();
    });

    tearDown(() async {
      final box = SkillStore.instance.box;
      await box.clear();
    });

    SkillModel _makeSkill(String id, String name, DateTime createdAt) =>
        SkillModel(
          id: id,
          name: name,
          steps: [],
          createdAt: createdAt,
        );

    test('save and get round-trip', () async {
      final skill = _makeSkill('s1', 'Skill One', DateTime(2026, 6, 1));
      await SkillStore.instance.save(skill);
      final retrieved = SkillStore.instance.get('s1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Skill One');
    });

    test('getAll returns all saved skills sorted newest first', () async {
      final older = _makeSkill('s-old', 'Old Skill', DateTime(2026, 1, 1));
      final newer = _makeSkill('s-new', 'New Skill', DateTime(2026, 6, 1));
      await SkillStore.instance.save(older);
      await SkillStore.instance.save(newer);
      final all = SkillStore.instance.getAll();
      expect(all.length, 2);
      expect(all[0].id, 's-new');
      expect(all[1].id, 's-old');
    });

    test('delete removes skill', () async {
      final skill = _makeSkill('s2', 'To Delete', DateTime(2026, 6, 1));
      await SkillStore.instance.save(skill);
      await SkillStore.instance.delete('s2');
      expect(SkillStore.instance.get('s2'), isNull);
    });

    test('get returns null for unknown id', () {
      expect(SkillStore.instance.get('nonexistent'), isNull);
    });
  });
}
