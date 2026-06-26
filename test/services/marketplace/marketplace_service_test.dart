// test/services/marketplace/marketplace_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketclaw/services/marketplace/marketplace_service.dart';
import 'package:pocketclaw/services/marketplace/pcskill_codec.dart';
import 'package:pocketclaw/services/skill_engine/skill_store.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_store.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarketplaceService.importFromString', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await SkillStore.instance.init();
      await WorkflowStore.instance.init();
    });

    tearDown(() async {
      await SkillStore.instance.box.clear();
      await WorkflowStore.instance.box.clear();
    });

    test(
      'imports skills and workflows from a bundle, re-minting ids',
      () async {
        final bundle = PcSkillCodec.encode(
          skills: [
            SkillModel(
              id: 'old-s',
              name: 'Imported Skill',
              steps: const [PrimitiveStep(primitive: 'back')],
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          exportedAtIso: '2026-06-26T00:00:00.000Z',
        );

        final result = await MarketplaceService.instance.importFromString(
          bundle,
        );

        expect(result.skillsAdded, 1);
        expect(result.workflowsAdded, 0);
        final saved = SkillStore.instance.getAll();
        expect(saved.length, 1);
        expect(saved.single.name, 'Imported Skill');
        expect(saved.single.id, isNot('old-s')); // re-minted
      },
    );

    test('throws/returns gracefully on a bad bundle', () async {
      expect(
        () => MarketplaceService.instance.importFromString('{"format":"x"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
