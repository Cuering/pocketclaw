import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/marketplace/pcskill_codec.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_model.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  SkillModel skill(String id, String name) => SkillModel(
        id: id,
        name: name,
        steps: const [PrimitiveStep(primitive: 'back')],
        createdAt: DateTime(2026, 1, 1),
      );

  WorkflowModel workflow(String id, List<String> stepIds) => WorkflowModel(
        id: id,
        name: 'WF',
        stepSkillIds: stepIds,
        createdAt: DateTime(2026, 1, 1),
      );

  group('encode', () {
    test('produces pcskill/1 with skills and workflows', () {
      final json = PcSkillCodec.encode(
        skills: [skill('s1', 'A')],
        workflows: [workflow('w1', ['s1'])],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['format'], 'pcskill/1');
      expect((decoded['skills'] as List).length, 1);
      expect((decoded['workflows'] as List).length, 1);
    });
  });

  group('decode', () {
    test('rejects unknown format', () {
      expect(
        () => PcSkillCodec.decode(
          jsonEncode({'format': 'pcskill/99', 'skills': []}),
          newSkillId: () => 'new',
          newWorkflowId: () => 'neww',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-pcskill json', () {
      expect(
        () => PcSkillCodec.decode(
          '{"foo":1}',
          newSkillId: () => 'new',
          newWorkflowId: () => 'neww',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('re-mints skill ids', () {
      final json = PcSkillCodec.encode(
        skills: [skill('old-id', 'A')],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );
      var n = 0;
      final plan = PcSkillCodec.decode(
        json,
        newSkillId: () => 'skill-new-${n++}',
        newWorkflowId: () => 'wf-new',
      );
      expect(plan.skills.single.id, 'skill-new-0');
      expect(plan.skills.single.name, 'A');
    });

    test('rewires workflow stepSkillIds through the id map', () {
      final json = PcSkillCodec.encode(
        skills: [skill('old-s', 'A')],
        workflows: [workflow('old-w', ['old-s'])],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );
      final plan = PcSkillCodec.decode(
        json,
        newSkillId: () => 'skill-X',
        newWorkflowId: () => 'wf-Y',
      );
      expect(plan.skills.single.id, 'skill-X');
      expect(plan.workflows.single.id, 'wf-Y');
      expect(plan.workflows.single.stepSkillIds, ['skill-X']);
      expect(plan.warnings, isEmpty);
    });

    test('drops missing skill refs from a workflow and warns', () {
      final json = jsonEncode({
        'format': 'pcskill/1',
        'skills': <Map<String, dynamic>>[],
        'workflows': [workflow('old-w', ['ghost']).toJson()],
      });
      final plan = PcSkillCodec.decode(
        json,
        newSkillId: () => 'skill-X',
        newWorkflowId: () => 'wf-Y',
      );
      expect(plan.workflows.single.stepSkillIds, isEmpty);
      expect(plan.warnings.length, 1);
    });
  });
}
