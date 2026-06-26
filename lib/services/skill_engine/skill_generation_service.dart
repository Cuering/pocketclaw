import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../gemma_service.dart';
import '../primitive_engine/primitive_models.dart';
import 'skill_model.dart';

class SkillGenerationService {
  SkillGenerationService._();
  static final SkillGenerationService instance = SkillGenerationService._();

  Future<void> init() async {}
  Future<void> dispose() async {}

  /// Overridable for testing — injects a custom generate function.
  /// In production this is null, and the real GemmaService is used.
  @visibleForTesting
  Future<String> Function(String prompt)? generateOverride;

  /// Generates a SkillModel from a natural-language description using Gemma.
  /// Returns null on any failure — never throws.
  Future<SkillModel?> generate(String description) async {
    try {
      final prompt =
          '''
You are a skill generator for PocketClaw, a private on-device Android assistant.

Available primitives (use ONLY these):
- open_app: args {"package": "com.example.app"}
- tap: args {"selector": "element description"}
- type: args {"text": "text to type"}
- scroll: args {"direction": "up|down|left|right"}
- back: args {}
- read_screen: args {}
- read_clipboard: args {}

Generate a skill for: "$description"

Respond with ONLY valid JSON (no explanation, no markdown, no backticks):
{"name":"<short name>","description":"<one sentence>","steps":[{"primitive":"<name>","args":{...}},...]}''';

      final response = generateOverride != null
          ? await generateOverride!(prompt)
          : await GemmaService.instance.generate(prompt);
      return _parseSkillFromResponse(response);
    } catch (e) {
      debugPrint('🐾 SKILL GEN: generation failed: $e');
      return null;
    }
  }

  SkillModel? _parseSkillFromResponse(String response) {
    try {
      // Extract the first { ... } JSON block from the response
      final start = response.indexOf('{');
      final end = response.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;

      final jsonStr = response.substring(start, end + 1);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final name = json['name'] as String?;
      if (name == null || name.isEmpty) return null;

      // Validate each step via PrimitiveStep.fromJson (throws on unknown primitives)
      final rawSteps = json['steps'] as List<dynamic>? ?? [];
      final steps = rawSteps
          .map((s) => PrimitiveStep.fromJson(s as Map<String, dynamic>))
          .toList();

      return SkillModel(
        id: _generateId(),
        name: name,
        description: json['description'] as String? ?? '',
        version: '1.0',
        steps: steps,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('🐾 SKILL GEN: failed to parse skill JSON: $e');
      return null;
    }
  }

  String _generateId() {
    // Simple UUID-like ID: timestamp + random suffix
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = (ts % 99999).toString().padLeft(5, '0');
    return 'skill-$ts-$suffix';
  }
}
