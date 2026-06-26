import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../gemma_service.dart';
import '../skill_engine/skill_store.dart';
import 'workflow_model.dart';

class WorkflowGenerationService {
  WorkflowGenerationService._();
  static final WorkflowGenerationService instance =
      WorkflowGenerationService._();

  Future<void> init() async {}
  Future<void> dispose() async {}

  /// Overridable for testing — injects a custom generate function.
  @visibleForTesting
  Future<String> Function(String prompt)? generateOverride;

  /// Generates a WorkflowModel from a natural-language description.
  /// Returns null if no skills exist, Gemma fails, or JSON is invalid.
  /// Never throws.
  Future<WorkflowModel?> generate(String description) async {
    try {
      final skills = SkillStore.instance.getAll();
      if (skills.isEmpty) {
        debugPrint('🐾 WORKFLOW GEN: no skills available — cannot generate workflow');
        return null;
      }

      final skillList = skills
          .map((s) => '- id: ${s.id}  name: ${s.name}  description: ${s.description}')
          .join('\n');

      final prompt = '''
You are a workflow generator for PocketClaw, a private on-device Android assistant.

Available skills:
$skillList

Generate a workflow for: "$description"

A workflow is an ordered sequence of skill IDs to execute in order.
Use ONLY the skill IDs listed above — do not invent new ones.

Respond with ONLY valid JSON (no explanation, no markdown, no backticks):
{"name":"<short name>","description":"<one sentence>","stepSkillIds":["<id>","<id>",...],"triggerType":"manual"}''';

      final response = generateOverride != null
          ? await generateOverride!(prompt)
          : await GemmaService.instance.generate(prompt);

      return _parseWorkflowFromResponse(response);
    } catch (e) {
      debugPrint('🐾 WORKFLOW GEN: generation failed: $e');
      return null;
    }
  }

  WorkflowModel? _parseWorkflowFromResponse(String response) {
    try {
      final start = response.indexOf('{');
      final end = response.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;

      final jsonStr = response.substring(start, end + 1);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final name = json['name'] as String?;
      if (name == null || name.isEmpty) return null;

      final rawIds = json['stepSkillIds'] as List<dynamic>? ?? [];
      final stepSkillIds = rawIds.cast<String>();
      if (stepSkillIds.isEmpty) return null;

      // Validate: every stepSkillId must exist in SkillStore
      for (final id in stepSkillIds) {
        if (SkillStore.instance.get(id) == null) {
          debugPrint('🐾 WORKFLOW GEN: unknown skillId in steps: $id');
          return null;
        }
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      return WorkflowModel(
        id: 'wf-$ts',
        name: name,
        description: json['description'] as String? ?? '',
        triggerType: json['triggerType'] as String? ?? 'manual',
        stepSkillIds: stepSkillIds,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('🐾 WORKFLOW GEN: failed to parse workflow JSON: $e');
      return null;
    }
  }
}
