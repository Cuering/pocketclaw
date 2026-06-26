import 'dart:convert';

import '../skill_engine/skill_model.dart';
import '../workflow_engine/workflow_model.dart';

/// Re-minted, ready-to-save models produced by [PcSkillCodec.decode].
class ImportPlan {
  final List<SkillModel> skills;
  final List<WorkflowModel> workflows;
  final List<String> warnings;
  const ImportPlan({
    required this.skills,
    required this.workflows,
    required this.warnings,
  });
}

/// Summary returned by MarketplaceService.importFromFile (Task 7).
class ImportResult {
  final int skillsAdded;
  final int workflowsAdded;
  final List<String> warnings;
  const ImportResult({
    required this.skillsAdded,
    required this.workflowsAdded,
    required this.warnings,
  });
}

/// Encodes/decodes the `pcskill/1` bundle format. Pure — ID generators are
/// injected so there is no DateTime.now()/randomness inside (testable).
class PcSkillCodec {
  static const formatTag = 'pcskill/1';

  static String encode({
    required List<SkillModel> skills,
    List<WorkflowModel> workflows = const [],
    required String exportedAtIso,
  }) {
    return jsonEncode({
      'format': formatTag,
      'exportedAt': exportedAtIso,
      'skills': skills.map((s) => s.toJson()).toList(),
      'workflows': workflows.map((w) => w.toJson()).toList(),
    });
  }

  /// Decodes a bundle, re-minting all IDs and rewiring workflow step refs.
  /// Throws [FormatException] on malformed JSON or unknown format.
  static ImportPlan decode(
    String jsonStr, {
    required String Function() newSkillId,
    required String Function() newWorkflowId,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (e) {
      throw const FormatException('Not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a pcskill bundle');
    }
    if (decoded['format'] != formatTag) {
      throw FormatException('Unsupported format: ${decoded['format']}');
    }

    final warnings = <String>[];
    final idMap = <String, String>{}; // oldSkillId -> newSkillId

    final rawSkills = (decoded['skills'] as List<dynamic>? ?? []);
    final skills = <SkillModel>[];
    for (final raw in rawSkills) {
      final original = SkillModel.fromJson(raw as Map<String, dynamic>);
      final newId = newSkillId();
      idMap[original.id] = newId;
      skills.add(SkillModel(
        id: newId,
        name: original.name,
        description: original.description,
        version: original.version,
        steps: original.steps,
        createdAt: original.createdAt,
        useCount: 0,
      ));
    }

    final rawWorkflows = (decoded['workflows'] as List<dynamic>? ?? []);
    final workflows = <WorkflowModel>[];
    for (final raw in rawWorkflows) {
      final original = WorkflowModel.fromJson(raw as Map<String, dynamic>);
      final rewired = <String>[];
      for (final oldStepId in original.stepSkillIds) {
        final mapped = idMap[oldStepId];
        if (mapped == null) {
          warnings.add(
            'Workflow "${original.name}" references missing skill '
            '$oldStepId — step dropped.',
          );
        } else {
          rewired.add(mapped);
        }
      }
      workflows.add(WorkflowModel(
        id: newWorkflowId(),
        name: original.name,
        description: original.description,
        triggerType: original.triggerType,
        stepSkillIds: rewired,
        createdAt: original.createdAt,
      ));
    }

    return ImportPlan(skills: skills, workflows: workflows, warnings: warnings);
  }
}
