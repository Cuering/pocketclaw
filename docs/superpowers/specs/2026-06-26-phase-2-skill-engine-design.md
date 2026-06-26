# Phase 2 — Skill Engine Design Spec

**Date:** 2026-06-26
**Phase:** 2 of 5 (further_plan.md)
**Owner:** Manoj Shetty (personal side project)
**Status:** Ready for implementation

---

## Goal

Build the Skill Engine: a DSL for defining reusable action sequences (skills), a registry for storing them, a Gemma-powered generator for creating them from natural language, and a screen for managing them. Skills are combinations of primitives from Phase 1a.

---

## Scope

**In scope (Phase 2):**
- `SkillModel` — JSON-serializable data class for a named sequence of PrimitiveSteps
- `SkillStore` — Hive `Box<String>` persistence wrapper
- `SkillEngine` — singleton orchestrator: execute, generate, list, delete skills
- `SkillGenerationService` — Gemma prompt → SkillModel
- `SkillsScreen` — list, create, run, delete skills
- Wire skill commands ("run X", "create skill: X") into `ChatCommandService`
- Wire `SkillStore.instance.init()` + `SkillEngine.instance.init()` into `main.dart`

**Out of scope:**
- Skill Marketplace / import-export (Phase 4)
- Workflow Engine integration (Phase 3)
- Agent Loop multi-step observe-act cycles (Phase 5)
- Fine-tuning skill routing (Phase 5)

---

## Architecture

```
User voice/text command
        ↓
ChatCommandService.tryHandleWithGemma(text)
        ├── "run [name]" / "execute [name]" / "use skill [name]"
        │       → SkillEngine.instance.execute(id)
        │       → PrimitiveEngine.instance.execute(skill.steps)
        │       → returns execution summary string
        │
        └── "create skill: [desc]" / "make skill: [desc]" / "new skill: [desc]"
                → SkillEngine.instance.generate(description)
                → SkillGenerationService.generate(desc)
                → GemmaService.instance.generate(prompt)
                → parse JSON → validate steps → SkillStore.instance.save()
                → returns confirmation string

SkillsScreen (manual UI management)
        ↓
SkillEngine
        ├── SkillStore (Hive Box<String>)
        └── PrimitiveEngine.instance.execute(steps)
```

---

## Data Model

### SkillModel

```dart
// lib/services/skill_engine/skill_model.dart

class SkillModel {
  final String id;           // UUID (generated at creation)
  final String name;         // "Order Coffee"
  final String description;  // "Opens Swiggy and searches for coffee"
  final String version;      // "1.0"
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
    steps: (json['steps'] as List<dynamic>)
        .map((s) => PrimitiveStep.fromJson(s as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    useCount: json['useCount'] as int? ?? 0,
  );
}
```

**Hive storage:** `Box<String>` keyed by `skill.id` — each entry is `jsonEncode(skill.toJson())`. No TypeAdapters needed (same approach as ConversationStore).

---

## Services

### SkillStore

```dart
// lib/services/skill_engine/skill_store.dart

class SkillStore {
  SkillStore._();
  static final SkillStore instance = SkillStore._();

  static const String _boxName = 'skills';
  Box<String>? _box;

  Future<void> init() async { ... }      // open Hive box
  Future<void> dispose() async {}        // no-op

  Future<void> save(SkillModel skill) async { ... }
  SkillModel? get(String id) { ... }     // synchronous — Hive box is in-memory
  List<SkillModel> getAll() { ... }      // sorted by createdAt descending
  Future<void> delete(String id) async { ... }
  Box<String> get box => _requireBox;    // for listenable
}
```

### SkillGenerationService

Builds a Gemma prompt listing available primitives and asks for JSON. Extracts the first `{…}` JSON block from the response, validates each step via `PrimitiveStep.fromJson()`, returns `null` on any failure (never throws).

**Prompt template:**
```
You are a skill generator for PocketClaw, a private on-device Android assistant.

Available primitives (use ONLY these):
- open_app: args {"package": "com.example.app"}
- tap: args {"selector": "element description"}
- type: args {"text": "text to type"}
- scroll: args {"direction": "up|down|left|right"}
- back: args {}
- read_screen: args {}
- read_clipboard: args {}

Generate a skill for: "<description>"

Respond with ONLY valid JSON (no explanation, no markdown):
{"name":"<short name>","description":"<one sentence>","steps":[{"primitive":"<name>","args":{...}},...]}
```

### SkillEngine

```dart
// lib/services/skill_engine/skill_engine.dart

enum SkillEngineState { idle, generating, executing, error }

class SkillEngine {
  SkillEngine._();
  static final SkillEngine instance = SkillEngine._();

  final ValueNotifier<SkillEngineState> _state =
      ValueNotifier(SkillEngineState.idle);
  ValueListenable<SkillEngineState> get state => _state;
  String? lastError;

  Future<void> init() async {}
  Future<void> dispose() async { _state.dispose(); }

  List<SkillModel> list() => SkillStore.instance.getAll();
  SkillModel? get(String id) => SkillStore.instance.get(id);

  /// Execute a saved skill. Returns a human-readable summary.
  /// Never throws — errors update state to error.
  Future<String> execute(String skillId) async { ... }

  /// Generate a new skill from a natural-language description.
  /// Returns the created SkillModel, or null if generation failed.
  /// Never throws.
  Future<SkillModel?> generate(String description) async { ... }

  Future<void> delete(String id) async { ... }
}
```

---

## SkillsScreen

`lib/screens/skills_screen.dart` — full-page screen accessible from the main menu.

**States (per Screen Checklist):**
- Loading: while `SkillStore` init runs
- Empty: "No skills yet" + "Create a skill" button
- List: `ListView.builder` of skill cards — name, description, step count
- Each card: "Run" button + long-press to delete

**Create skill flow:**
1. User taps "Create Skill"
2. Text input dialog: "Describe what the skill should do"
3. `SkillEngine.instance.generate(description)` — shows loading state
4. On success: snackbar "Skill created: {name}" + list refreshes
5. On failure: snackbar "Could not generate skill. Try again."

**Run skill flow:**
1. Tap "Run" on a card → `SkillEngine.instance.execute(id)`
2. Shows executing state (CircularProgressIndicator)
3. On success: snackbar with result summary
4. On failure: snackbar with error message

**Design:** Neobrutalism — `PocketClawTheme.panel()` cards, cyan borders, `hardShadow`.

---

## ChatCommandService — Skill Command Detection

Extend `tryHandleWithGemma()` to detect skill commands BEFORE the Gemma JSON extraction call (string matching, no latency):

```dart
// Check for skill execution: "run X", "execute X", "use skill X"
final runMatch = RegExp(
  r'^(?:run|execute|use skill|launch skill)\s+(.+)$',
  caseSensitive: false,
).firstMatch(text.trim());
if (runMatch != null) {
  final skillName = runMatch.group(1)!.trim();
  return await _runSkillByName(skillName);
}

// Check for skill generation: "create skill: X", "make skill: X", "new skill: X"
final createMatch = RegExp(
  r'^(?:create skill|make skill|new skill)[:\s]+(.+)$',
  caseSensitive: false,
).firstMatch(text.trim());
if (createMatch != null) {
  final description = createMatch.group(1)!.trim();
  return await _createSkill(description);
}
```

Helper `_runSkillByName`: finds skill by case-insensitive name prefix, executes, returns summary.
Helper `_createSkill`: calls `SkillEngine.instance.generate()`, returns confirmation or error string.

---

## main.dart Init Sequence

Add after `ContextEngine.instance.init()`:
```dart
await SkillStore.instance.init();
await SkillEngine.instance.init();
```

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `lib/services/skill_engine/skill_model.dart` | Create | SkillModel data class + JSON |
| `lib/services/skill_engine/skill_store.dart` | Create | Hive Box<String> persistence |
| `lib/services/skill_engine/skill_engine.dart` | Create | Orchestrator singleton |
| `lib/services/skill_engine/skill_generation_service.dart` | Create | Gemma prompt → SkillModel |
| `lib/screens/skills_screen.dart` | Create | List/Create/Run/Delete UI |
| `lib/services/chat_command_service.dart` | Modify | Add skill command detection |
| `lib/main.dart` | Modify | Init SkillStore + SkillEngine |
| `test/services/skill_engine/skill_engine_test.dart` | Create | Unit tests |

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Gemma returns invalid JSON | `SkillGenerationService.generate()` returns `null`; no crash |
| JSON has unknown primitive | `PrimitiveStep.fromJson()` throws `ArgumentError`; caught → return `null` |
| Skill execution fails | `SkillEngine.execute()` sets state to error, returns error message string |
| Skill not found by name | `_runSkillByName` returns "No skill named '...' found." |
| SkillStore not initialized | `_requireBox` throws `StateError`; caught in SkillEngine |

---

## Tests

### skill_engine_test.dart

- `SkillModel.toJson() / fromJson()` round-trip — all fields preserved
- `SkillModel.fromJson()` with missing optional fields — uses defaults
- `SkillStore.save() / get() / getAll() / delete()` — CRUD round-trip
- `SkillStore.getAll()` — returns sorted by createdAt descending
- `SkillEngine.execute()` — mock PrimitiveEngine → returns summary string
- `SkillEngine.execute()` with unknown id — sets state to error, returns error string
- `SkillEngine.generate()` — mock GemmaService returns valid JSON → SkillModel created + saved
- `SkillEngine.generate()` — mock GemmaService returns invalid JSON → returns null, no crash
- `SkillGenerationService` extracts JSON block from response with surrounding text
