import 'package:flutter/foundation.dart';

import '../primitive_engine/primitive_engine.dart';
import 'skill_generation_service.dart';
import 'skill_model.dart';
import 'skill_store.dart';

enum SkillEngineState { idle, generating, executing, error }

class SkillEngine {
  SkillEngine._();
  static final SkillEngine instance = SkillEngine._();

  final ValueNotifier<SkillEngineState> _state = ValueNotifier(
    SkillEngineState.idle,
  );
  ValueListenable<SkillEngineState> get state => _state;
  String? lastError;

  Future<void> init() async {}

  Future<void> dispose() async {
    _state.dispose();
  }

  List<SkillModel> list() => SkillStore.instance.getAll();

  SkillModel? get(String id) => SkillStore.instance.get(id);

  /// Execute a saved skill by ID. Returns a human-readable result summary.
  /// Never throws — errors update state to error and return an error string.
  Future<String> execute(String skillId) async {
    final skill = SkillStore.instance.get(skillId);
    if (skill == null) {
      lastError = "Skill not found: $skillId";
      _state.value = SkillEngineState.error;
      debugPrint('🐾 SKILL ENGINE: $lastError');
      return lastError!;
    }

    _state.value = SkillEngineState.executing;
    try {
      debugPrint(
        '🐾 SKILL ENGINE: executing "${skill.name}" (${skill.steps.length} steps)',
      );
      final result = await PrimitiveEngine.instance.execute(skill.steps);

      skill.useCount++;
      await SkillStore.instance.save(skill);

      _state.value = SkillEngineState.idle;

      if (result.ok) {
        return '✅ Skill "${skill.name}" completed (${skill.steps.length} steps)';
      } else {
        return '⚠️ Skill "${skill.name}" failed at step ${(result.failedAtStep ?? 0) + 1}: ${result.errorMessage ?? "unknown error"}';
      }
    } catch (e) {
      lastError = e.toString();
      _state.value = SkillEngineState.error;
      debugPrint('🐾 SKILL ENGINE: execute failed: $e');
      return '❌ Skill execution error: $e';
    }
  }

  /// Generate a new skill from natural language and save it.
  /// Returns the created SkillModel, or null on failure. Never throws.
  Future<SkillModel?> generate(String description) async {
    _state.value = SkillEngineState.generating;
    try {
      final skill = await SkillGenerationService.instance.generate(description);
      if (skill == null) {
        lastError = 'Could not generate skill from: "$description"';
        _state.value = SkillEngineState.error;
        debugPrint('🐾 SKILL ENGINE: $lastError');
        return null;
      }
      await SkillStore.instance.save(skill);
      _state.value = SkillEngineState.idle;
      debugPrint('🐾 SKILL ENGINE: generated and saved "${skill.name}"');
      return skill;
    } catch (e) {
      lastError = e.toString();
      _state.value = SkillEngineState.error;
      debugPrint('🐾 SKILL ENGINE: generate failed: $e');
      return null;
    }
  }

  Future<void> delete(String id) async {
    await SkillStore.instance.delete(id);
    debugPrint('🐾 SKILL ENGINE: deleted skill $id');
  }
}
