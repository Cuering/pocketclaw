import 'package:flutter/foundation.dart';

import '../skill_engine/skill_engine.dart';
import 'workflow_generation_service.dart';
import 'workflow_model.dart';
import 'workflow_store.dart';

enum WorkflowEngineState { idle, generating, executing, error }

class WorkflowEngine {
  WorkflowEngine._();
  static final WorkflowEngine instance = WorkflowEngine._();

  final ValueNotifier<WorkflowEngineState> _state =
      ValueNotifier(WorkflowEngineState.idle);
  ValueListenable<WorkflowEngineState> get state => _state;
  String? lastError;

  /// Overridable for tests — bypasses SkillEngine (which needs MethodChannel).
  @visibleForTesting
  Future<String> Function(String skillId)? skillExecuteOverride;

  Future<void> init() async {}

  Future<void> dispose() async {
    _state.dispose();
  }

  List<WorkflowModel> list() => WorkflowStore.instance.getAll();

  WorkflowModel? get(String id) => WorkflowStore.instance.get(id);

  /// Execute all steps of a workflow sequentially.
  /// Returns a multi-line human-readable summary string.
  /// Never throws.
  Future<String> execute(String workflowId) async {
    final workflow = WorkflowStore.instance.get(workflowId);
    if (workflow == null) {
      lastError = 'Workflow not found: $workflowId';
      _state.value = WorkflowEngineState.error;
      debugPrint('🐾 WORKFLOW ENGINE: $lastError');
      return '❌ Workflow not found: $workflowId';
    }

    _state.value = WorkflowEngineState.executing;
    final stepCount = workflow.stepSkillIds.length;
    debugPrint(
        '🐾 WORKFLOW ENGINE: executing "${workflow.name}" ($stepCount steps)');

    final stepResults = <String>[];
    for (var i = 0; i < workflow.stepSkillIds.length; i++) {
      final skillId = workflow.stepSkillIds[i];
      try {
        final result = skillExecuteOverride != null
            ? await skillExecuteOverride!(skillId)
            : await SkillEngine.instance.execute(skillId);
        stepResults.add('Step ${i + 1}: $result');
        debugPrint('🐾 WORKFLOW ENGINE: step ${i + 1} result: $result');
      } catch (e) {
        final note = 'Step ${i + 1}: ⚠️ Skill $skillId error: $e';
        stepResults.add(note);
        debugPrint('🐾 WORKFLOW ENGINE: $note');
      }
    }

    workflow.runCount++;
    workflow.lastRunAt = DateTime.now();
    await WorkflowStore.instance.save(workflow);

    _state.value = WorkflowEngineState.idle;

    final summary =
        '✅ Workflow "${workflow.name}" — $stepCount step${stepCount == 1 ? '' : 's'}\n'
        '${stepResults.join('\n')}';
    return summary;
  }

  /// Generate a new workflow from natural language and save it.
  /// Returns null if generation fails. Never throws.
  Future<WorkflowModel?> generate(String description) async {
    _state.value = WorkflowEngineState.generating;
    try {
      final workflow =
          await WorkflowGenerationService.instance.generate(description);
      if (workflow == null) {
        lastError = 'Could not generate workflow from: "$description"';
        _state.value = WorkflowEngineState.error;
        debugPrint('🐾 WORKFLOW ENGINE: $lastError');
        return null;
      }
      await WorkflowStore.instance.save(workflow);
      _state.value = WorkflowEngineState.idle;
      debugPrint(
          '🐾 WORKFLOW ENGINE: generated and saved "${workflow.name}"');
      return workflow;
    } catch (e) {
      lastError = e.toString();
      _state.value = WorkflowEngineState.error;
      debugPrint('🐾 WORKFLOW ENGINE: generate failed: $e');
      return null;
    }
  }

  Future<void> delete(String id) async {
    await WorkflowStore.instance.delete(id);
    debugPrint('🐾 WORKFLOW ENGINE: deleted workflow $id');
  }
}
