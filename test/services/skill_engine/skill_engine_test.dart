import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/skill_engine/skill_store.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';
import 'package:pocketclaw/services/skill_engine/skill_engine.dart';
import 'package:pocketclaw/services/skill_engine/skill_generation_service.dart';

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
        const PrimitiveStep(
          primitive: 'open_app',
          args: {'package': 'com.swiggy.android'},
        ),
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

    SkillModel makeSkill(String id, String name, DateTime createdAt) =>
        SkillModel(id: id, name: name, steps: [], createdAt: createdAt);

    test('save and get round-trip', () async {
      final skill = makeSkill('s1', 'Skill One', DateTime(2026, 6, 1));
      await SkillStore.instance.save(skill);
      final retrieved = SkillStore.instance.get('s1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Skill One');
    });

    test('getAll returns all saved skills sorted newest first', () async {
      final older = makeSkill('s-old', 'Old Skill', DateTime(2026, 1, 1));
      final newer = makeSkill('s-new', 'New Skill', DateTime(2026, 6, 1));
      await SkillStore.instance.save(older);
      await SkillStore.instance.save(newer);
      final all = SkillStore.instance.getAll();
      expect(all.length, 2);
      expect(all[0].id, 's-new');
      expect(all[1].id, 's-old');
    });

    test('delete removes skill', () async {
      final skill = makeSkill('s2', 'To Delete', DateTime(2026, 6, 1));
      await SkillStore.instance.save(skill);
      await SkillStore.instance.delete('s2');
      expect(SkillStore.instance.get('s2'), isNull);
    });

    test('get returns null for unknown id', () {
      expect(SkillStore.instance.get('nonexistent'), isNull);
    });
  });

  // ── SkillGenerationService ─────────────────────────────────────────────────

  group('SkillGenerationService', () {
    // Use generateOverride to inject a mock response so tests don't need
    // a live Gemma model. The override is cleared in tearDown.
    tearDown(() {
      SkillGenerationService.instance.generateOverride = null;
    });

    test('generates SkillModel from valid JSON response', () async {
      const validJson =
          '{"name":"Open Maps","description":"Opens Google Maps","steps":[{"primitive":"open_app","args":{"package":"com.google.android.apps.maps"}}]}';
      SkillGenerationService.instance.generateOverride = (_) async => validJson;
      final skill = await SkillGenerationService.instance.generate(
        'open google maps',
      );
      expect(skill, isNotNull);
      expect(skill!.name, 'Open Maps');
      expect(skill.steps.length, 1);
      expect(skill.steps[0].primitive, 'open_app');
    });

    test('extracts JSON block from response with surrounding text', () async {
      const responseWithText =
          'Here is your skill: {"name":"Test","description":"test","steps":[{"primitive":"read_screen","args":{}}]} Done!';
      SkillGenerationService.instance.generateOverride = (_) async =>
          responseWithText;
      final skill = await SkillGenerationService.instance.generate('test');
      expect(skill, isNotNull);
      expect(skill!.name, 'Test');
    });

    test('returns null for invalid JSON response', () async {
      SkillGenerationService.instance.generateOverride = (_) async =>
          'I cannot generate that skill.';
      final skill = await SkillGenerationService.instance.generate(
        'something bad',
      );
      expect(skill, isNull);
    });

    test('returns null for JSON with unknown primitive', () async {
      const badPrimitive =
          '{"name":"Bad","description":"bad","steps":[{"primitive":"unknown_primitive","args":{}}]}';
      SkillGenerationService.instance.generateOverride = (_) async =>
          badPrimitive;
      final skill = await SkillGenerationService.instance.generate('bad skill');
      expect(skill, isNull);
    });
  });

  // ── SkillEngine ────────────────────────────────────────────────────────────

  group('SkillEngine', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await SkillStore.instance.init();
      await SkillEngine.instance.init();
    });

    tearDown(() async {
      await SkillStore.instance.box.clear();
    });

    test('execute returns error string for unknown skill id', () async {
      final result = await SkillEngine.instance.execute('nonexistent-id');
      expect(result.toLowerCase(), contains('not found'));
      expect(SkillEngine.instance.state.value, SkillEngineState.error);
    });

    test('execute surfaces render_component pcui output in the result', () async {
      // A render_component-only skill is local (no accessibility needed). Its
      // pcui fence must appear in the returned string so the chat bubble can
      // render the component (Source B end-to-end).
      final skill = SkillModel(
        id: 'eng-pcui',
        name: 'Show Card',
        steps: const [
          PrimitiveStep(
            primitive: 'render_component',
            args: {
              'spec': {'type': 'card', 'title': 'Hi', 'body': 'there'},
            },
          ),
        ],
        createdAt: DateTime(2026, 6, 1),
      );
      await SkillStore.instance.save(skill);

      final result = await SkillEngine.instance.execute('eng-pcui');
      expect(result, contains('```pcui'));
      expect(result, contains('"type":"card"'));
    });

    test('list returns all saved skills', () async {
      final skill = SkillModel(
        id: 'eng-1',
        name: 'Test Skill',
        steps: [],
        createdAt: DateTime(2026, 6, 1),
      );
      await SkillStore.instance.save(skill);
      final list = SkillEngine.instance.list();
      expect(list.any((s) => s.id == 'eng-1'), isTrue);
    });

    test('delete removes skill from store', () async {
      final skill = SkillModel(
        id: 'del-1',
        name: 'Delete Me',
        steps: [],
        createdAt: DateTime(2026, 6, 1),
      );
      await SkillStore.instance.save(skill);
      await SkillEngine.instance.delete('del-1');
      expect(SkillStore.instance.get('del-1'), isNull);
    });
  });
}
