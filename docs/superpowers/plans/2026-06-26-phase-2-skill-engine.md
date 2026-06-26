# Phase 2 — Skill Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Skill DSL (SkillModel), Hive-backed registry (SkillStore), Gemma-powered generator (SkillGenerationService), and orchestrating SkillEngine singleton. Wire skill commands into ChatCommandService and surface a SkillsScreen for manual management.

**Architecture:** Skills are named, versioned sequences of `PrimitiveStep`s stored as JSON strings in Hive `Box<String>` (same pattern as ConversationStore). `SkillEngine` orchestrates generate/execute/delete. `ChatCommandService` detects "run X" and "create skill: X" commands via regex before the Gemma JSON extraction call. `SkillGenerationService` prompts Gemma and extracts a JSON block.

**Tech Stack:** Flutter/Dart, Hive `Box<String>`, `PrimitiveEngine` (Phase 1a, already built), `GemmaService` (existing singleton), `ChatCommandService` (existing singleton to modify)

## Global Constraints

- Flutter/Dart, Android only — no iOS
- Singleton pattern: `static final XxxService instance = XxxService._();`
- `ValueListenable<T>` state — never Riverpod, Provider, or BLoC
- Colors/typography from `PocketClawTheme` tokens only — never `Color(0xFF...)` inline
- `flutter test` must pass before every commit
- Android package name: `com.pocketclaw.pocketclaw`
- Services catch their own exceptions — widgets react to state, never try/catch service calls
- `SkillEngine.execute()` and `SkillEngine.generate()` must never throw — errors update state
- `SkillGenerationService.generate()` returns `null` on any parse/validation failure — never throws
- Hive box name: `'skills'`
- No TypeAdapters — store JSON strings in `Box<String>` (same as ConversationStore)

---

### Task 1: SkillModel + SkillStore + unit tests

**Files:**
- Create: `lib/services/skill_engine/skill_model.dart`
- Create: `lib/services/skill_engine/skill_store.dart`
- Create: `test/services/skill_engine/skill_engine_test.dart` (partial — SkillModel + SkillStore tests only)

**Interfaces:**
- Produces (consumed by Task 2): `SkillModel(id, name, description, version, steps, createdAt, useCount)` with `toJson()` / `fromJson()`
- Produces (consumed by Task 2): `SkillStore.instance.init()`, `save(skill)`, `get(id)`, `getAll()`, `delete(id)`, `box` getter
- Consumes (already built): `PrimitiveStep` from `lib/services/primitive_engine/primitive_models.dart`

- [ ] **Step 1: Write failing tests**

Create `test/services/skill_engine/skill_engine_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests — expect failure**

```bash
flutter test test/services/skill_engine/skill_engine_test.dart
```

Expected: FAIL — files not found.

- [ ] **Step 3: Create SkillModel**

Create `lib/services/skill_engine/skill_model.dart`:

```dart
import 'dart:convert';

import '../primitive_engine/primitive_models.dart';

class SkillModel {
  final String id;
  final String name;
  final String description;
  final String version;
  final List<PrimitiveStep> steps;
  final DateTime createdAt;
  int useCount;

  SkillModel({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0',
    required this.steps,
    required this.createdAt,
    this.useCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'steps': steps
        .map((s) => {'primitive': s.primitive, 'args': s.args})
        .toList(),
    'createdAt': createdAt.toIso8601String(),
    'useCount': useCount,
  };

  factory SkillModel.fromJson(Map<String, dynamic> json) => SkillModel(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '1.0',
    steps: (json['steps'] as List<dynamic>? ?? [])
        .map((s) => PrimitiveStep.fromJson(s as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    useCount: json['useCount'] as int? ?? 0,
  );

  String toJsonString() => jsonEncode(toJson());
}
```

- [ ] **Step 4: Create SkillStore**

Create `lib/services/skill_engine/skill_store.dart`:

```dart
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
```

- [ ] **Step 5: Run tests — expect pass**

```bash
flutter test test/services/skill_engine/skill_engine_test.dart
```

Expected: all SkillModel + SkillStore tests pass.

- [ ] **Step 6: Run full suite**

```bash
flutter test
```

Expected: all tests pass (57 + new skill tests).

- [ ] **Step 7: Commit**

```bash
git add lib/services/skill_engine/skill_model.dart lib/services/skill_engine/skill_store.dart test/services/skill_engine/skill_engine_test.dart
git commit -m "feat(skill-engine): add SkillModel data class and SkillStore persistence"
```

---

### Task 2: SkillGenerationService + SkillEngine + extend tests

**Files:**
- Create: `lib/services/skill_engine/skill_generation_service.dart`
- Create: `lib/services/skill_engine/skill_engine.dart`
- Modify: `test/services/skill_engine/skill_engine_test.dart` (add SkillEngine + SkillGenerationService tests)

**Interfaces:**
- Consumes (Task 1): `SkillModel`, `SkillStore.instance`
- Consumes (already built): `GemmaService.instance.generate(prompt)`, `PrimitiveEngine.instance.execute(steps)`
- Produces (consumed by Task 3 + 4): `SkillEngine.instance.execute(id)`, `SkillEngine.instance.generate(description)`, `SkillEngine.instance.list()`, `SkillEngine.instance.delete(id)`, `SkillEngine.instance.state`

- [ ] **Step 1: Add SkillEngine + SkillGenerationService tests to the test file**

Open `test/services/skill_engine/skill_engine_test.dart`. Add these groups after the SkillStore group:

```dart
import 'package:flutter/services.dart';
import 'package:pocketclaw/services/skill_engine/skill_engine.dart';
import 'package:pocketclaw/services/skill_engine/skill_generation_service.dart';
import 'package:pocketclaw/services/gemma_service.dart';

// Add at the top of main():
  // ── SkillGenerationService ─────────────────────────────────────────────────

  group('SkillGenerationService', () {
    void mockGemmaChannel(String response) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_gemma'),
        (call) async {
          if (call.method == 'getResponse' || call.method == 'generateResponse') {
            return response;
          }
          return null;
        },
      );
    }

    test('generates SkillModel from valid JSON response', () async {
      final validJson = '{"name":"Open Maps","description":"Opens Google Maps","steps":[{"primitive":"open_app","args":{"package":"com.google.android.apps.maps"}}]}';
      mockGemmaChannel(validJson);
      final skill = await SkillGenerationService.instance.generate('open google maps');
      expect(skill, isNotNull);
      expect(skill!.name, 'Open Maps');
      expect(skill.steps.length, 1);
      expect(skill.steps[0].primitive, 'open_app');
    });

    test('extracts JSON block from response with surrounding text', () async {
      final responseWithText = 'Here is your skill: {"name":"Test","description":"test","steps":[{"primitive":"read_screen","args":{}}]} Done!';
      mockGemmaChannel(responseWithText);
      final skill = await SkillGenerationService.instance.generate('test');
      expect(skill, isNotNull);
      expect(skill!.name, 'Test');
    });

    test('returns null for invalid JSON response', () async {
      mockGemmaChannel('I cannot generate that skill.');
      final skill = await SkillGenerationService.instance.generate('something bad');
      expect(skill, isNull);
    });

    test('returns null for JSON with unknown primitive', () async {
      final badPrimitive = '{"name":"Bad","description":"bad","steps":[{"primitive":"unknown_primitive","args":{}}]}';
      mockGemmaChannel(badPrimitive);
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
```

- [ ] **Step 2: Run tests — expect failure for new groups**

```bash
flutter test test/services/skill_engine/skill_engine_test.dart
```

Expected: FAIL on SkillEngine + SkillGenerationService tests (files not found).

- [ ] **Step 3: Create SkillGenerationService**

Create `lib/services/skill_engine/skill_generation_service.dart`:

```dart
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

  /// Generates a SkillModel from a natural-language description using Gemma.
  /// Returns null on any failure — never throws.
  Future<SkillModel?> generate(String description) async {
    try {
      final prompt = '''
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

      final response = await GemmaService.instance.generate(prompt);
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
```

- [ ] **Step 4: Create SkillEngine**

Create `lib/services/skill_engine/skill_engine.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../primitive_engine/primitive_engine.dart';
import 'skill_generation_service.dart';
import 'skill_model.dart';
import 'skill_store.dart';

enum SkillEngineState { idle, generating, executing, error }

class SkillEngine {
  SkillEngine._();
  static final SkillEngine instance = SkillEngine._();

  final ValueNotifier<SkillEngineState> _state =
      ValueNotifier(SkillEngineState.idle);
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
      debugPrint('🐾 SKILL ENGINE: executing "${skill.name}" (${skill.steps.length} steps)');
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
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
flutter test test/services/skill_engine/skill_engine_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Run full suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/services/skill_engine/skill_generation_service.dart lib/services/skill_engine/skill_engine.dart test/services/skill_engine/skill_engine_test.dart
git commit -m "feat(skill-engine): add SkillEngine orchestrator and SkillGenerationService"
```

---

### Task 3: SkillsScreen UI

**Files:**
- Create: `lib/screens/skills_screen.dart`

**Interfaces:**
- Consumes (Task 2): `SkillEngine.instance.list()`, `execute(id)`, `generate(description)`, `delete(id)`, `state`
- Consumes (Task 1): `SkillModel`

No new tests for this task — widget tests are skipped (the Screen Checklist is the gate instead).

- [ ] **Step 1: Create SkillsScreen**

Create `lib/screens/skills_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../core/pocketclaw_theme.dart';
import '../services/skill_engine/skill_engine.dart';
import '../services/skill_engine/skill_model.dart';
import '../services/skill_engine/skill_store.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  bool _creating = false;
  String? _runningId;
  final TextEditingController _descController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _createSkill() async {
    final description = _descController.text.trim();
    if (description.isEmpty) return;

    setState(() { _creating = true; });
    final skill = await SkillEngine.instance.generate(description);
    if (!mounted) return;
    setState(() { _creating = false; });

    if (skill != null) {
      _descController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Skill created: ${skill.name}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate skill. Try a clearer description.')),
      );
    }
  }

  Future<void> _runSkill(SkillModel skill) async {
    setState(() { _runningId = skill.id; });
    final result = await SkillEngine.instance.execute(skill.id);
    if (!mounted) return;
    setState(() { _runningId = null; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result)),
    );
  }

  Future<void> _deleteSkill(SkillModel skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PocketClawTheme.bg2,
        title: Text('Delete "${skill.name}"?',
            style: Theme.of(ctx).textTheme.titleMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: TextStyle(color: PocketClawTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SkillEngine.instance.delete(skill.id);
    if (!mounted) return;
    setState(() {});
  }

  void _showCreateDialog() {
    _descController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateInner) => AlertDialog(
          backgroundColor: PocketClawTheme.bg2,
          title: Text('Create Skill',
              style: Theme.of(ctx).textTheme.titleMedium),
          content: TextField(
            controller: _descController,
            autofocus: true,
            maxLines: 3,
            style: Theme.of(ctx).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Describe what the skill should do...',
              hintStyle: TextStyle(color: PocketClawTheme.muted),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: PocketClawTheme.cyan, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _creating
                  ? null
                  : () async {
                      await _createSkill();
                    },
              child: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: PocketClawTheme.bg,
      appBar: AppBar(
        backgroundColor: PocketClawTheme.bg,
        title: Text('Skills', style: theme.textTheme.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: PocketClawTheme.cyan,
            onPressed: _showCreateDialog,
            tooltip: 'Create Skill',
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<String>>(
        valueListenable: SkillStore.instance.box.listenable(),
        builder: (context, box, _) {
          final skills = SkillEngine.instance.list();
          if (skills.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_outlined,
                      color: PocketClawTheme.muted, size: 48),
                  const SizedBox(height: 12),
                  Text('No skills yet',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _showCreateDialog,
                    child: const Text('Create a Skill'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: skills.length,
            itemBuilder: (context, i) {
              final skill = skills[i];
              final isRunning = _runningId == skill.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onLongPress: () => _deleteSkill(skill),
                  child: Container(
                    decoration: PocketClawTheme.panel(),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(skill.name,
                                  style: theme.textTheme.titleMedium),
                              if (skill.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(skill.description,
                                    style: theme.textTheme.bodyLarge),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                '${skill.steps.length} step${skill.steps.length == 1 ? '' : 's'}'
                                ' · used ${skill.useCount}×',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        isRunning
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton(
                                onPressed: () => _runSkill(skill),
                                child: const Text('Run'),
                              ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Screen Checklist verification**

```
[x] Loading state shown — ValueListenableBuilder shows live box state
[x] Error state — snackbar on run/create failure
[x] Empty state — "No skills yet" + "Create a Skill" CTA
[x] Keyboard handled — dialog uses AlertDialog (system managed)
[x] Controllers disposed — _descController disposed in dispose()
[x] No fixed heights — responsive
[x] if (!mounted) return after every await — done in _createSkill() and _runSkill()
[x] const on all static widgets — done
[x] Colors from PocketClawTheme only — done
```

- [ ] **Step 3: Run full suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/skills_screen.dart
git commit -m "feat(skill-engine): add SkillsScreen for listing, creating, and running skills"
```

---

### Task 4: Wire skill commands into ChatCommandService + init in main.dart

**Files:**
- Modify: `lib/services/chat_command_service.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes (Task 2): `SkillEngine.instance.execute(id)`, `SkillEngine.instance.generate(description)`, `SkillEngine.instance.list()`
- Consumes (Task 1): `SkillStore.instance.init()`

- [ ] **Step 1: Add skill commands to ChatCommandService**

Open `lib/services/chat_command_service.dart`. Add `skill_engine` imports at the top:
```dart
import 'skill_engine/skill_engine.dart';
import 'skill_engine/skill_store.dart';
```

At the top of `tryHandleWithGemma()`, BEFORE the `tryHandle()` fast-path call, insert:

```dart
    // 0. Skill execution: "run X" / "execute X" / "use skill X" / "launch skill X"
    final runMatch = RegExp(
      r'^(?:run|execute|use skill|launch skill)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (runMatch != null) {
      final skillName = runMatch.group(1)!.trim();
      return await _runSkillByName(skillName);
    }

    // 0b. Skill generation: "create skill: X" / "make skill: X" / "new skill: X"
    final createMatch = RegExp(
      r'^(?:create skill|make skill|new skill)[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (createMatch != null) {
      final description = createMatch.group(1)!.trim();
      return await _createSkillFromCommand(description);
    }
```

Add the two private helper methods at the bottom of the class (before the closing `}`):

```dart
  Future<String?> _runSkillByName(String nameQuery) async {
    final skills = SkillEngine.instance.list();
    if (skills.isEmpty) return 'No skills saved. Say "create skill: [description]" to make one.';

    final lower = nameQuery.toLowerCase();
    final match = skills.firstWhere(
      (s) => s.name.toLowerCase().contains(lower),
      orElse: () => skills.firstWhere(
        (s) => lower.contains(s.name.toLowerCase()),
        orElse: () => skills.first, // fallback — will return not-found below
      ),
    );

    // Verify we found a real match (not just fallback)
    final isRealMatch =
        match.name.toLowerCase().contains(lower) ||
        lower.contains(match.name.toLowerCase());
    if (!isRealMatch) {
      return "No skill named '$nameQuery' found. Available: ${skills.map((s) => s.name).join(', ')}.";
    }

    return await SkillEngine.instance.execute(match.id);
  }

  Future<String?> _createSkillFromCommand(String description) async {
    final skill = await SkillEngine.instance.generate(description);
    if (skill == null) {
      return 'Could not generate skill. Try a clearer description.';
    }
    return '✅ Skill "${skill.name}" created with ${skill.steps.length} step${skill.steps.length == 1 ? '' : 's'}.';
  }
```

- [ ] **Step 2: Wire init in main.dart**

Open `lib/main.dart`. Add imports with the other service imports:
```dart
import 'services/skill_engine/skill_store.dart';
import 'services/skill_engine/skill_engine.dart';
```

In the init sequence, after `await ContextEngine.instance.init();`, add:
```dart
    await SkillStore.instance.init();
    await SkillEngine.instance.init();
```

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/services/chat_command_service.dart lib/main.dart
git commit -m "feat(skill-engine): wire skill commands into ChatCommandService and init sequence"
```
