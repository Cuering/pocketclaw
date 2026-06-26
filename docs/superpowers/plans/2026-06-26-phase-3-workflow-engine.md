# Phase 3 — Workflow Engine + Background Task Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add IFTTT-style workflows (ordered chains of saved skills) and a background task engine that runs them immediately or on a future timer.

**Architecture:** WorkflowEngine orchestrates sequential SkillEngine.execute() calls; BackgroundTaskEngine schedules tasks using in-app Timers (WorkManager hook point for Phase 5); both stores are Hive `Box<String>` with jsonEncode/jsonDecode. Layering: `Workflow → Skill → Primitive → Accessibility`.

**Tech Stack:** Flutter/Dart, Hive `Box<String>`, `dart:async Timer`, `WidgetsBindingObserver`, `ValueListenable<T>`, `@visibleForTesting` override injection.

## Global Constraints

- Singleton pattern: `static final XxxService instance = XxxService._();` — never `new XxxService()`
- Hive storage: `Box<String>` keyed by id, `jsonEncode`/`jsonDecode` — NO TypeAdapters
- State via `ValueListenable<T>` — no Riverpod, Provider, or BLoC
- `build()` must be pure — no service calls, no side effects
- Every async-backed widget shows: loading → error → data
- `if (!mounted) return` after every `await` before using `context` or `setState`
- Dispose every `TextEditingController`, `StreamSubscription`, `Timer` in `dispose()`
- `const` on every widget constructor that can be const
- `ListView.builder` — never `ListView(children: items.map(...).toList())`
- PocketClawTheme tokens only — never `Color(0xFF...)` inline
- `GemmaState.ready` check before `GemmaService.instance.generate()`
- `flutter test` must pass before every commit
- Services catch their own exceptions — widgets react to state, never try/catch service calls
- WorkflowEngine.execute() and BackgroundTaskEngine.schedule() never throw

---

### Task 1: Data layer — WorkflowModel, WorkflowStore, BackgroundTask, TaskStore

**Files:**
- Create: `lib/services/workflow_engine/workflow_model.dart`
- Create: `lib/services/workflow_engine/workflow_store.dart`
- Create: `lib/services/background_task_engine/background_task.dart`
- Create: `lib/services/background_task_engine/task_store.dart`
- Create: `test/services/workflow_engine/workflow_engine_test.dart` (all Phase 3 tests live here — data + service layer)

**Interfaces:**
- Consumes: `package:hive_flutter/hive_flutter.dart`, `dart:convert`
- Produces:
  - `WorkflowModel({required String id, required String name, String description, String triggerType, required List<String> stepSkillIds, required DateTime createdAt, DateTime? lastRunAt, int runCount})`
  - `WorkflowModel.fromJson(Map<String,dynamic>) → WorkflowModel`
  - `WorkflowModel.toJson() → Map<String,dynamic>`
  - `WorkflowStore.instance.init() → Future<void>`
  - `WorkflowStore.instance.save(WorkflowModel) → Future<void>`
  - `WorkflowStore.instance.get(String id) → WorkflowModel?`
  - `WorkflowStore.instance.getAll() → List<WorkflowModel>` (sorted newest first)
  - `WorkflowStore.instance.delete(String id) → Future<void>`
  - `WorkflowStore.instance.box → Box<String>` (for `.listenable()`)
  - `enum TaskStatus { pending, running, done, failed, cancelled }`
  - `BackgroundTask({required String id, required String title, String? workflowId, TaskStatus status, required DateTime createdAt, DateTime? scheduledFor, DateTime? completedAt, String? result})`
  - `BackgroundTask.fromJson(Map<String,dynamic>) → BackgroundTask`
  - `BackgroundTask.toJson() → Map<String,dynamic>`
  - `TaskStore.instance.init() → Future<void>`
  - `TaskStore.instance.save(BackgroundTask) → Future<void>`
  - `TaskStore.instance.get(String id) → BackgroundTask?`
  - `TaskStore.instance.getAll() → List<BackgroundTask>`
  - `TaskStore.instance.getByStatus(TaskStatus) → List<BackgroundTask>`
  - `TaskStore.instance.delete(String id) → Future<void>`
  - `TaskStore.instance.box → Box<String>`

- [ ] **Step 1: Write failing tests for WorkflowModel**

Create `test/services/workflow_engine/workflow_engine_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_model.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_store.dart';
import 'package:pocketclaw/services/background_task_engine/background_task.dart';
import 'package:pocketclaw/services/background_task_engine/task_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── WorkflowModel ──────────────────────────────────────────────────────────

  group('WorkflowModel', () {
    final sample = WorkflowModel(
      id: 'wf-001',
      name: 'Study from PDF',
      description: 'Extract text, summarize, make flashcards',
      triggerType: 'manual',
      stepSkillIds: ['skill-111', 'skill-222'],
      createdAt: DateTime(2026, 6, 26, 10, 0),
      lastRunAt: DateTime(2026, 6, 26, 12, 0),
      runCount: 3,
    );

    test('toJson / fromJson round-trip preserves all fields', () {
      final json = sample.toJson();
      final restored = WorkflowModel.fromJson(json);
      expect(restored.id, 'wf-001');
      expect(restored.name, 'Study from PDF');
      expect(restored.description, 'Extract text, summarize, make flashcards');
      expect(restored.triggerType, 'manual');
      expect(restored.stepSkillIds, ['skill-111', 'skill-222']);
      expect(restored.createdAt, DateTime(2026, 6, 26, 10, 0));
      expect(restored.lastRunAt, DateTime(2026, 6, 26, 12, 0));
      expect(restored.runCount, 3);
    });

    test('fromJson uses defaults for optional fields', () {
      final json = {
        'id': 'wf-x',
        'name': 'Test',
        'stepSkillIds': [],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final wf = WorkflowModel.fromJson(json);
      expect(wf.description, '');
      expect(wf.triggerType, 'manual');
      expect(wf.lastRunAt, isNull);
      expect(wf.runCount, 0);
    });

    test('toJson encodes lastRunAt as null when not set', () {
      final wf = WorkflowModel(
        id: 'wf-2',
        name: 'No run',
        stepSkillIds: [],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(wf.toJson()['lastRunAt'], isNull);
    });
  });

  // ── WorkflowStore ──────────────────────────────────────────────────────────

  group('WorkflowStore', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await WorkflowStore.instance.init();
    });

    tearDown(() async {
      await WorkflowStore.instance.box.clear();
    });

    WorkflowModel makeWf(String id, String name, DateTime createdAt) =>
        WorkflowModel(
          id: id,
          name: name,
          stepSkillIds: [],
          createdAt: createdAt,
        );

    test('save and get round-trip', () async {
      final wf = makeWf('wf-1', 'Workflow One', DateTime(2026, 6, 1));
      await WorkflowStore.instance.save(wf);
      final retrieved = WorkflowStore.instance.get('wf-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Workflow One');
    });

    test('getAll returns sorted newest first', () async {
      final older = makeWf('wf-old', 'Old', DateTime(2026, 1, 1));
      final newer = makeWf('wf-new', 'New', DateTime(2026, 6, 1));
      await WorkflowStore.instance.save(older);
      await WorkflowStore.instance.save(newer);
      final all = WorkflowStore.instance.getAll();
      expect(all[0].id, 'wf-new');
      expect(all[1].id, 'wf-old');
    });

    test('delete removes workflow', () async {
      await WorkflowStore.instance.save(makeWf('wf-del', 'Delete Me', DateTime(2026, 1, 1)));
      await WorkflowStore.instance.delete('wf-del');
      expect(WorkflowStore.instance.get('wf-del'), isNull);
    });

    test('get returns null for unknown id', () {
      expect(WorkflowStore.instance.get('nonexistent'), isNull);
    });
  });

  // ── BackgroundTask ─────────────────────────────────────────────────────────

  group('BackgroundTask', () {
    final sample = BackgroundTask(
      id: 'task-001',
      title: 'Run Study Workflow',
      workflowId: 'wf-001',
      status: TaskStatus.done,
      createdAt: DateTime(2026, 6, 26, 10, 0),
      scheduledFor: DateTime(2026, 6, 26, 11, 0),
      completedAt: DateTime(2026, 6, 26, 11, 5),
      result: '✅ 2 steps completed',
    );

    test('toJson / fromJson round-trip preserves all fields', () {
      final json = sample.toJson();
      final restored = BackgroundTask.fromJson(json);
      expect(restored.id, 'task-001');
      expect(restored.title, 'Run Study Workflow');
      expect(restored.workflowId, 'wf-001');
      expect(restored.status, TaskStatus.done);
      expect(restored.createdAt, DateTime(2026, 6, 26, 10, 0));
      expect(restored.scheduledFor, DateTime(2026, 6, 26, 11, 0));
      expect(restored.completedAt, DateTime(2026, 6, 26, 11, 5));
      expect(restored.result, '✅ 2 steps completed');
    });

    test('fromJson uses defaults for optional fields', () {
      final json = {
        'id': 'task-x',
        'title': 'Test',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final task = BackgroundTask.fromJson(json);
      expect(task.workflowId, isNull);
      expect(task.status, TaskStatus.pending);
      expect(task.scheduledFor, isNull);
      expect(task.completedAt, isNull);
      expect(task.result, isNull);
    });

    test('fromJson with unknown status falls back to pending', () {
      final json = {
        'id': 'task-y',
        'title': 'Test',
        'status': 'unknown_status',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final task = BackgroundTask.fromJson(json);
      expect(task.status, TaskStatus.pending);
    });
  });

  // ── TaskStore ──────────────────────────────────────────────────────────────

  group('TaskStore', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await TaskStore.instance.init();
    });

    tearDown(() async {
      await TaskStore.instance.box.clear();
    });

    BackgroundTask makeTask(String id, TaskStatus status) => BackgroundTask(
          id: id,
          title: 'Task $id',
          status: status,
          createdAt: DateTime(2026, 6, 1),
        );

    test('save and get round-trip', () async {
      final task = makeTask('t1', TaskStatus.pending);
      await TaskStore.instance.save(task);
      final retrieved = TaskStore.instance.get('t1');
      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Task t1');
    });

    test('getByStatus filters correctly', () async {
      await TaskStore.instance.save(makeTask('t-pending', TaskStatus.pending));
      await TaskStore.instance.save(makeTask('t-done', TaskStatus.done));
      final pending = TaskStore.instance.getByStatus(TaskStatus.pending);
      expect(pending.length, 1);
      expect(pending.first.id, 't-pending');
    });

    test('delete removes task', () async {
      await TaskStore.instance.save(makeTask('t-del', TaskStatus.pending));
      await TaskStore.instance.delete('t-del');
      expect(TaskStore.instance.get('t-del'), isNull);
    });

    test('getAll returns all tasks', () async {
      await TaskStore.instance.save(makeTask('ta', TaskStatus.pending));
      await TaskStore.instance.save(makeTask('tb', TaskStatus.done));
      expect(TaskStore.instance.getAll().length, 2);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/services/workflow_engine/workflow_engine_test.dart --reporter expanded 2>&1 | head -20
```

Expected: compilation errors — `WorkflowModel`, `WorkflowStore`, `BackgroundTask`, `TaskStore` not found.

- [ ] **Step 3: Create WorkflowModel**

Create `lib/services/workflow_engine/workflow_model.dart`:

```dart
import 'dart:convert';

class WorkflowModel {
  final String id;
  final String name;
  final String description;
  final String triggerType;
  final List<String> stepSkillIds;
  final DateTime createdAt;
  DateTime? lastRunAt;
  int runCount;

  WorkflowModel({
    required this.id,
    required this.name,
    this.description = '',
    this.triggerType = 'manual',
    required this.stepSkillIds,
    required this.createdAt,
    this.lastRunAt,
    this.runCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'triggerType': triggerType,
        'stepSkillIds': stepSkillIds,
        'createdAt': createdAt.toIso8601String(),
        'lastRunAt': lastRunAt?.toIso8601String(),
        'runCount': runCount,
      };

  factory WorkflowModel.fromJson(Map<String, dynamic> json) => WorkflowModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        triggerType: json['triggerType'] as String? ?? 'manual',
        stepSkillIds: List<String>.from(json['stepSkillIds'] as List),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastRunAt: json['lastRunAt'] != null
            ? DateTime.parse(json['lastRunAt'] as String)
            : null,
        runCount: json['runCount'] as int? ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());
}
```

- [ ] **Step 4: Create WorkflowStore**

Create `lib/services/workflow_engine/workflow_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'workflow_model.dart';

class WorkflowStore {
  WorkflowStore._();
  static final WorkflowStore instance = WorkflowStore._();

  static const String _boxName = 'workflows';
  Box<String>? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    debugPrint('🐾 WORKFLOW STORE: opened box with ${_box!.length} workflows');
  }

  Future<void> dispose() async {}

  Box<String> get box {
    final b = _box;
    if (b == null) {
      throw StateError(
          'WorkflowStore not initialized. Call init() in main() first.');
    }
    return b;
  }

  Box<String> get _requireBox => box;

  Future<void> save(WorkflowModel workflow) async {
    await _requireBox.put(workflow.id, jsonEncode(workflow.toJson()));
    debugPrint('🐾 WORKFLOW STORE: saved "${workflow.name}" (${workflow.id})');
  }

  WorkflowModel? get(String id) {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return WorkflowModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🐾 WORKFLOW STORE: failed to parse workflow $id: $e');
      return null;
    }
  }

  List<WorkflowModel> getAll() {
    final b = _requireBox;
    final results = <WorkflowModel>[];
    for (final key in b.keys) {
      final raw = b.get(key as String);
      if (raw == null) continue;
      try {
        results.add(
            WorkflowModel.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('🐾 WORKFLOW STORE: skipping unparseable workflow $key: $e');
      }
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
    debugPrint('🐾 WORKFLOW STORE: deleted workflow $id');
  }
}
```

- [ ] **Step 5: Create BackgroundTask**

Create `lib/services/background_task_engine/background_task.dart`:

```dart
enum TaskStatus { pending, running, done, failed, cancelled }

class BackgroundTask {
  final String id;
  final String title;
  final String? workflowId;
  TaskStatus status;
  final DateTime createdAt;
  DateTime? scheduledFor;
  DateTime? completedAt;
  String? result;

  BackgroundTask({
    required this.id,
    required this.title,
    this.workflowId,
    this.status = TaskStatus.pending,
    required this.createdAt,
    this.scheduledFor,
    this.completedAt,
    this.result,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'workflowId': workflowId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'result': result,
      };

  factory BackgroundTask.fromJson(Map<String, dynamic> json) => BackgroundTask(
        id: json['id'] as String,
        title: json['title'] as String,
        workflowId: json['workflowId'] as String?,
        status: TaskStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TaskStatus.pending,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        scheduledFor: json['scheduledFor'] != null
            ? DateTime.parse(json['scheduledFor'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        result: json['result'] as String?,
      );
}
```

- [ ] **Step 6: Create TaskStore**

Create `lib/services/background_task_engine/task_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'background_task.dart';

class TaskStore {
  TaskStore._();
  static final TaskStore instance = TaskStore._();

  static const String _boxName = 'background_tasks';
  Box<String>? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    debugPrint('🐾 TASK STORE: opened box with ${_box!.length} tasks');
  }

  Future<void> dispose() async {}

  Box<String> get box {
    final b = _box;
    if (b == null) {
      throw StateError(
          'TaskStore not initialized. Call init() in main() first.');
    }
    return b;
  }

  Box<String> get _requireBox => box;

  Future<void> save(BackgroundTask task) async {
    await _requireBox.put(task.id, jsonEncode(task.toJson()));
    debugPrint('🐾 TASK STORE: saved task "${task.title}" (${task.id})');
  }

  BackgroundTask? get(String id) {
    final raw = _requireBox.get(id);
    if (raw == null) return null;
    try {
      return BackgroundTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🐾 TASK STORE: failed to parse task $id: $e');
      return null;
    }
  }

  List<BackgroundTask> getAll() {
    final b = _requireBox;
    final results = <BackgroundTask>[];
    for (final key in b.keys) {
      final raw = b.get(key as String);
      if (raw == null) continue;
      try {
        results.add(
            BackgroundTask.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('🐾 TASK STORE: skipping unparseable task $key: $e');
      }
    }
    return results;
  }

  List<BackgroundTask> getByStatus(TaskStatus status) =>
      getAll().where((t) => t.status == status).toList();

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
    debugPrint('🐾 TASK STORE: deleted task $id');
  }
}
```

- [ ] **Step 7: Run the data-layer tests**

```bash
flutter test test/services/workflow_engine/workflow_engine_test.dart --reporter expanded 2>&1 | tail -10
```

Expected: all data-layer tests pass (WorkflowModel, WorkflowStore, BackgroundTask, TaskStore groups). Service/engine groups will fail to compile — that is expected; the engine classes are added in Task 2.

- [ ] **Step 8: Run the full suite**

```bash
flutter test 2>&1 | tail -5
```

Expected: `All tests passed!` (pre-existing 71 + new data-layer tests).

- [ ] **Step 9: Commit**

```bash
git add lib/services/workflow_engine/workflow_model.dart \
        lib/services/workflow_engine/workflow_store.dart \
        lib/services/background_task_engine/background_task.dart \
        lib/services/background_task_engine/task_store.dart \
        test/services/workflow_engine/workflow_engine_test.dart \
        test/services/background_task_engine/background_task_engine_test.dart
git commit -m "feat(workflow-engine): add WorkflowModel, WorkflowStore, BackgroundTask, TaskStore"
```

---

### Task 2: Service layer — WorkflowGenerationService, WorkflowEngine, BackgroundTaskEngine

**Files:**
- Create: `lib/services/workflow_engine/workflow_generation_service.dart`
- Create: `lib/services/workflow_engine/workflow_engine.dart`
- Create: `lib/services/background_task_engine/background_task_engine.dart`
- Modify: `test/services/workflow_engine/workflow_engine_test.dart` (append engine + BackgroundTaskEngine test groups)

**Interfaces:**
- Consumes (from Task 1): `WorkflowModel`, `WorkflowStore`, `BackgroundTask`, `TaskStore`, `TaskStatus`
- Consumes (existing): `SkillEngine.instance.execute(String skillId) → Future<String>`, `SkillEngine.instance.list() → List<SkillModel>`, `GemmaService.instance.generate(String prompt) → Future<String>`, `GemmaService.instance.state → ValueListenable<GemmaState>`, `GemmaState` (enum)
- Produces:
  - `WorkflowGenerationService.instance.generate(String description) → Future<WorkflowModel?>`
  - `WorkflowGenerationService.instance.generateOverride` (`@visibleForTesting Future<String> Function(String prompt)?`)
  - `enum WorkflowEngineState { idle, generating, executing, error }`
  - `WorkflowEngine.instance.state → ValueListenable<WorkflowEngineState>`
  - `WorkflowEngine.instance.lastError → String?`
  - `WorkflowEngine.instance.execute(String workflowId) → Future<String>`
  - `WorkflowEngine.instance.generate(String description) → Future<WorkflowModel?>`
  - `WorkflowEngine.instance.list() → List<WorkflowModel>`
  - `WorkflowEngine.instance.get(String id) → WorkflowModel?`
  - `WorkflowEngine.instance.delete(String id) → Future<void>`
  - `enum BackgroundTaskEngineState { idle, running, error }`
  - `BackgroundTaskEngine.instance.state → ValueListenable<BackgroundTaskEngineState>`
  - `BackgroundTaskEngine.instance.schedule(String workflowId, {DateTime? runAt}) → Future<BackgroundTask>`
  - `BackgroundTaskEngine.instance.cancel(String taskId) → Future<void>`
  - `BackgroundTaskEngine.instance.list() → List<BackgroundTask>`
  - `BackgroundTaskEngine.instance.pending() → List<BackgroundTask>`

- [ ] **Step 1: Add service-layer tests to the existing test files**

Append to `test/services/workflow_engine/workflow_engine_test.dart` (after the existing `TaskStore` group closing brace, before the final `}`):

```dart
  // ── WorkflowEngine ─────────────────────────────────────────────────────────

  group('WorkflowGenerationService', () {
    tearDown(() {
      WorkflowGenerationService.instance.generateOverride = null;
    });

    test('generate returns null when no skills exist', () async {
      // SkillStore is empty in this test — early exit
      final result = await WorkflowGenerationService.instance.generate('Study PDF');
      expect(result, isNull);
    });

    test('generate parses valid JSON from override', () async {
      // Inject a saved skill so the guard passes
      Hive.init('test/hive_test_db');
      await SkillStore.instance.init();
      await SkillStore.instance.save(SkillModel(
        id: 'skill-aaa',
        name: 'Extract Text',
        steps: [],
        createdAt: DateTime(2026, 1, 1),
      ));

      WorkflowGenerationService.instance.generateOverride = (_) async =>
          '{"name":"Study","description":"Study workflow","stepSkillIds":["skill-aaa"],"triggerType":"manual"}';

      final result = await WorkflowGenerationService.instance.generate('Study PDF');
      expect(result, isNotNull);
      expect(result!.name, 'Study');
      expect(result.stepSkillIds, ['skill-aaa']);

      await SkillStore.instance.box.clear();
    });

    test('generate returns null for invalid JSON', () async {
      WorkflowGenerationService.instance.generateOverride =
          (_) async => 'not valid json at all';
      final result = await WorkflowGenerationService.instance.generate('Study PDF');
      expect(result, isNull);
    });

    test('generate returns null when stepSkillIds reference missing skills', () async {
      WorkflowGenerationService.instance.generateOverride = (_) async =>
          '{"name":"Bad","description":"bad","stepSkillIds":["nonexistent-id"],"triggerType":"manual"}';
      final result = await WorkflowGenerationService.instance.generate('Study PDF');
      expect(result, isNull);
    });
  });

  group('WorkflowEngine', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await WorkflowStore.instance.init();
      await SkillStore.instance.init();
    });

    tearDown(() async {
      await WorkflowStore.instance.box.clear();
      await SkillStore.instance.box.clear();
      WorkflowEngine.instance.lastError = null;
    });

    test('execute returns error string for unknown workflowId', () async {
      final result = await WorkflowEngine.instance.execute('nonexistent-wf');
      expect(result, contains('not found'));
      expect(WorkflowEngine.instance.state.value, WorkflowEngineState.error);
    });

    test('execute runs steps sequentially and returns summary', () async {
      // Save a skill and a workflow referencing it
      final skill = SkillModel(id: 'sk-1', name: 'Test Skill', steps: [], createdAt: DateTime(2026, 1, 1));
      await SkillStore.instance.save(skill);

      final wf = WorkflowModel(
        id: 'wf-exec-1',
        name: 'Test Workflow',
        stepSkillIds: ['sk-1'],
        createdAt: DateTime(2026, 1, 1),
      );
      await WorkflowStore.instance.save(wf);

      // Override SkillEngine to avoid MethodChannel in tests
      WorkflowEngine.instance.skillExecuteOverride = (id) async => '✅ done';

      final result = await WorkflowEngine.instance.execute('wf-exec-1');
      expect(result, contains('Test Workflow'));
      expect(result, contains('1 step'));

      // runCount and lastRunAt are updated
      final updated = WorkflowStore.instance.get('wf-exec-1');
      expect(updated!.runCount, 1);
      expect(updated.lastRunAt, isNotNull);
      expect(WorkflowEngine.instance.state.value, WorkflowEngineState.idle);

      WorkflowEngine.instance.skillExecuteOverride = null;
    });

    test('execute skips missing skill and continues', () async {
      final wf = WorkflowModel(
        id: 'wf-skip',
        name: 'Skip Workflow',
        stepSkillIds: ['missing-skill'],
        createdAt: DateTime(2026, 1, 1),
      );
      await WorkflowStore.instance.save(wf);

      WorkflowEngine.instance.skillExecuteOverride = null;
      final result = await WorkflowEngine.instance.execute('wf-skip');
      // Workflow completes — missing skill produces a note, not a crash
      expect(result, isA<String>());
      expect(WorkflowEngine.instance.state.value, WorkflowEngineState.idle);
    });

    test('generate returns null when no skills exist', () async {
      final result = await WorkflowEngine.instance.generate('Study PDF');
      expect(result, isNull);
    });
  });

  group('BackgroundTaskEngine', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await TaskStore.instance.init();
      await WorkflowStore.instance.init();
      await SkillStore.instance.init();
      await BackgroundTaskEngine.instance.init();
    });

    tearDown(() async {
      // Do NOT call BackgroundTaskEngine.instance.dispose() — it disposes
      // _state which is a final field and cannot be re-created for subsequent tests.
      // Instead, cancel all pending tasks to clear timers.
      final pending = BackgroundTaskEngine.instance.pending();
      for (final t in pending) {
        await BackgroundTaskEngine.instance.cancel(t.id);
      }
      await TaskStore.instance.box.clear();
      await WorkflowStore.instance.box.clear();
      await SkillStore.instance.box.clear();
    });

    test('schedule with runAt null runs immediately and returns done task', () async {
      final skill = SkillModel(id: 'sk-bg', name: 'BG Skill', steps: [], createdAt: DateTime(2026, 1, 1));
      await SkillStore.instance.save(skill);
      final wf = WorkflowModel(
        id: 'wf-bg',
        name: 'BG Workflow',
        stepSkillIds: ['sk-bg'],
        createdAt: DateTime(2026, 1, 1),
      );
      await WorkflowStore.instance.save(wf);
      WorkflowEngine.instance.skillExecuteOverride = (id) async => '✅ done';

      final task = await BackgroundTaskEngine.instance.schedule('wf-bg');
      expect(task.status, TaskStatus.done);
      expect(task.result, isNotNull);
      expect(task.completedAt, isNotNull);

      WorkflowEngine.instance.skillExecuteOverride = null;
    });

    test('schedule with future runAt returns pending task without running', () async {
      final wf = WorkflowModel(
        id: 'wf-future',
        name: 'Future Workflow',
        stepSkillIds: [],
        createdAt: DateTime(2026, 1, 1),
      );
      await WorkflowStore.instance.save(wf);

      final runAt = DateTime.now().add(const Duration(hours: 1));
      final task = await BackgroundTaskEngine.instance.schedule('wf-future', runAt: runAt);
      expect(task.status, TaskStatus.pending);
      expect(task.scheduledFor, runAt);

      // Clean up timer
      await BackgroundTaskEngine.instance.cancel(task.id);
    });

    test('cancel marks pending task as cancelled', () async {
      final wf = WorkflowModel(
        id: 'wf-cancel',
        name: 'Cancel Workflow',
        stepSkillIds: [],
        createdAt: DateTime(2026, 1, 1),
      );
      await WorkflowStore.instance.save(wf);

      final runAt = DateTime.now().add(const Duration(hours: 1));
      final task = await BackgroundTaskEngine.instance.schedule('wf-cancel', runAt: runAt);
      await BackgroundTaskEngine.instance.cancel(task.id);

      final stored = TaskStore.instance.get(task.id);
      expect(stored!.status, TaskStatus.cancelled);
    });
  });
```

Also add these imports at the top of the file (after existing imports):

```dart
import 'package:pocketclaw/services/workflow_engine/workflow_generation_service.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_engine.dart';
import 'package:pocketclaw/services/background_task_engine/background_task_engine.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/skill_engine/skill_store.dart';
```

- [ ] **Step 2: Verify the new test groups fail to compile**

```bash
flutter test test/services/workflow_engine/workflow_engine_test.dart --reporter expanded 2>&1 | head -10
```

Expected: compilation errors — `WorkflowGenerationService`, `WorkflowEngine`, `BackgroundTaskEngine` not found (the data-layer groups already pass but can't compile with these missing imports).

- [ ] **Step 3: Create WorkflowGenerationService**

Create `lib/services/workflow_engine/workflow_generation_service.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../gemma_service.dart';
import '../skill_engine/skill_store.dart';
import 'workflow_model.dart';
import 'workflow_store.dart';

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
```

- [ ] **Step 4: Create WorkflowEngine**

Create `lib/services/workflow_engine/workflow_engine.dart`:

```dart
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
```

- [ ] **Step 5: Create BackgroundTaskEngine**

Create `lib/services/background_task_engine/background_task_engine.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../workflow_engine/workflow_engine.dart';
import 'background_task.dart';
import 'task_store.dart';

enum BackgroundTaskEngineState { idle, running, error }

class BackgroundTaskEngine with WidgetsBindingObserver {
  BackgroundTaskEngine._();
  static final BackgroundTaskEngine instance = BackgroundTaskEngine._();

  final ValueNotifier<BackgroundTaskEngineState> _state =
      ValueNotifier(BackgroundTaskEngineState.idle);
  ValueListenable<BackgroundTaskEngineState> get state => _state;

  // Keyed by taskId — WorkManager hook point for Phase 5.
  final Map<String, Timer> _timers = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _resumePendingTasks();
    debugPrint('🐾 TASK ENGINE: initialized');
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _state.dispose();
    debugPrint('🐾 TASK ENGINE: disposed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🐾 TASK ENGINE: app resumed — checking pending tasks');
      _resumePendingTasks();
    }
  }

  /// Schedule a workflow to run.
  ///
  /// runAt null or in the past: runs immediately, awaits completion, returns
  /// the completed task (status done or failed).
  ///
  /// runAt in the future: arms a Timer, returns the pending task immediately.
  /// Never throws.
  Future<BackgroundTask> schedule(String workflowId,
      {DateTime? runAt}) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final task = BackgroundTask(
        id: 'task-$ts',
        title: WorkflowEngine.instance.get(workflowId)?.name ?? workflowId,
        workflowId: workflowId,
        status: TaskStatus.pending,
        createdAt: DateTime.now(),
        scheduledFor: runAt,
      );
      await TaskStore.instance.save(task);
      debugPrint('🐾 TASK ENGINE: scheduled task ${task.id} for workflow $workflowId');

      final now = DateTime.now();
      final isImmediate = runAt == null || !runAt.isAfter(now);

      if (isImmediate) {
        await _runTask(task);
        return TaskStore.instance.get(task.id) ?? task;
      } else {
        final delay = runAt.difference(now);
        _timers[task.id] = Timer(delay, () async {
          _timers.remove(task.id);
          await _runTask(task);
        });
        debugPrint('🐾 TASK ENGINE: timer armed for ${delay.inSeconds}s');
        return task;
      }
    } catch (e) {
      debugPrint('🐾 TASK ENGINE: schedule failed: $e');
      // Return a failed task so callers always get a BackgroundTask back
      final ts = DateTime.now().millisecondsSinceEpoch;
      return BackgroundTask(
        id: 'task-err-$ts',
        title: workflowId,
        workflowId: workflowId,
        status: TaskStatus.failed,
        createdAt: DateTime.now(),
        result: 'Schedule error: $e',
        completedAt: DateTime.now(),
      );
    }
  }

  /// Cancel a pending task. No-op if already running/done/failed/cancelled.
  Future<void> cancel(String taskId) async {
    _timers[taskId]?.cancel();
    _timers.remove(taskId);

    final task = TaskStore.instance.get(taskId);
    if (task == null || task.status != TaskStatus.pending) return;
    task.status = TaskStatus.cancelled;
    await TaskStore.instance.save(task);
    debugPrint('🐾 TASK ENGINE: cancelled task $taskId');
  }

  List<BackgroundTask> list() => TaskStore.instance.getAll();

  List<BackgroundTask> pending() =>
      TaskStore.instance.getByStatus(TaskStatus.pending);

  void _resumePendingTasks() {
    final tasks = TaskStore.instance.getByStatus(TaskStatus.pending);
    final now = DateTime.now();
    for (final task in tasks) {
      if (_timers.containsKey(task.id)) continue; // already armed
      final runAt = task.scheduledFor;
      if (runAt == null || !runAt.isAfter(now)) {
        // Overdue — run immediately
        debugPrint('🐾 TASK ENGINE: resuming overdue task ${task.id}');
        _runTask(task);
      } else {
        final delay = runAt.difference(now);
        _timers[task.id] = Timer(delay, () async {
          _timers.remove(task.id);
          await _runTask(task);
        });
        debugPrint('🐾 TASK ENGINE: re-armed task ${task.id} for ${delay.inSeconds}s');
      }
    }
  }

  Future<void> _runTask(BackgroundTask task) async {
    _state.value = BackgroundTaskEngineState.running;
    task.status = TaskStatus.running;
    await TaskStore.instance.save(task);
    debugPrint('🐾 TASK ENGINE: running task ${task.id}');

    try {
      final result = await WorkflowEngine.instance.execute(task.workflowId ?? '');
      task.status = TaskStatus.done;
      task.result = result;
      task.completedAt = DateTime.now();
      debugPrint('🐾 TASK ENGINE: task ${task.id} done');
    } catch (e) {
      task.status = TaskStatus.failed;
      task.result = 'Error: $e';
      task.completedAt = DateTime.now();
      debugPrint('🐾 TASK ENGINE: task ${task.id} failed: $e');
    }

    await TaskStore.instance.save(task);
    _state.value = BackgroundTaskEngineState.idle;
  }
}
```

- [ ] **Step 6: Run the service-layer tests**

```bash
flutter test test/services/workflow_engine/workflow_engine_test.dart --reporter expanded 2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 7: Run the full suite**

```bash
flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 8: Commit**

```bash
git add lib/services/workflow_engine/workflow_generation_service.dart \
        lib/services/workflow_engine/workflow_engine.dart \
        lib/services/background_task_engine/background_task_engine.dart \
        test/services/workflow_engine/workflow_engine_test.dart
git commit -m "feat(workflow-engine): add WorkflowEngine, WorkflowGenerationService, BackgroundTaskEngine"
```

---

### Task 3: WorkflowsScreen UI

**Files:**
- Create: `lib/screens/workflows_screen.dart`

**Interfaces:**
- Consumes: `WorkflowEngine.instance` (list, generate, execute, delete, state), `BackgroundTaskEngine.instance.schedule(workflowId)`, `WorkflowStore.instance.box.listenable()`, `PocketClawTheme.*`
- Produces: `class WorkflowsScreen extends StatefulWidget { const WorkflowsScreen({super.key}); }`

- [ ] **Step 1: Create WorkflowsScreen**

Create `lib/screens/workflows_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/pocketclaw_theme.dart';
import '../services/workflow_engine/workflow_engine.dart';
import '../services/workflow_engine/workflow_model.dart';
import '../services/workflow_engine/workflow_store.dart';
import '../services/background_task_engine/background_task_engine.dart';

class WorkflowsScreen extends StatefulWidget {
  const WorkflowsScreen({super.key});

  @override
  State<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends State<WorkflowsScreen> {
  bool _creating = false;
  String? _runningId;
  final TextEditingController _descController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _createWorkflow({StateSetter? dialogSetState}) async {
    final description = _descController.text.trim();
    if (description.isEmpty) return;

    setState(() { _creating = true; });
    dialogSetState?.call(() {});
    final workflow = await WorkflowEngine.instance.generate(description);
    if (!mounted) return;
    setState(() { _creating = false; });
    dialogSetState?.call(() {});

    if (workflow != null) {
      _descController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Workflow created: ${workflow.name} (${workflow.stepSkillIds.length} step${workflow.stepSkillIds.length == 1 ? '' : 's'})'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not generate workflow. Create some skills first, then try again.'),
        ),
      );
    }
  }

  Future<void> _runWorkflow(WorkflowModel workflow) async {
    setState(() { _runningId = workflow.id; });
    final task = await BackgroundTaskEngine.instance.schedule(workflow.id);
    if (!mounted) return;
    setState(() { _runningId = null; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(task.result ?? 'Workflow complete')),
    );
  }

  Future<void> _deleteWorkflow(WorkflowModel workflow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PocketClawTheme.bg2,
        title: Text('Delete "${workflow.name}"?',
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
    await WorkflowEngine.instance.delete(workflow.id);
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
          title: Text('Create Workflow',
              style: Theme.of(ctx).textTheme.titleMedium),
          content: TextField(
            controller: _descController,
            autofocus: true,
            maxLines: 3,
            style: Theme.of(ctx).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Describe what the workflow should do...',
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
                      await _createWorkflow(dialogSetState: setStateInner);
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
        title: Text('Workflows', style: theme.textTheme.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: PocketClawTheme.cyan,
            onPressed: _showCreateDialog,
            tooltip: 'Create Workflow',
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<String>>(
        valueListenable: WorkflowStore.instance.box.listenable(),
        builder: (context, box, _) {
          final workflows = WorkflowEngine.instance.list();
          if (workflows.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree_outlined,
                      color: PocketClawTheme.muted, size: 48),
                  const SizedBox(height: 12),
                  Text('No workflows yet',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _showCreateDialog,
                    child: const Text('Create a Workflow'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: workflows.length,
            itemBuilder: (context, i) {
              final workflow = workflows[i];
              final isRunning = _runningId == workflow.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onLongPress: () => _deleteWorkflow(workflow),
                  child: Container(
                    decoration: PocketClawTheme.panel(),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(workflow.name,
                                  style: theme.textTheme.titleMedium),
                              if (workflow.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(workflow.description,
                                    style: theme.textTheme.bodyLarge),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                '${workflow.stepSkillIds.length} skill${workflow.stepSkillIds.length == 1 ? '' : 's'}'
                                ' · run ${workflow.runCount}×'
                                '${workflow.lastRunAt != null ? ' · last ran ${_formatDate(workflow.lastRunAt!)}' : ''}',
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
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : FilledButton(
                                onPressed: () => _runWorkflow(workflow),
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

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
```

- [ ] **Step 2: Run the full test suite**

```bash
flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add lib/screens/workflows_screen.dart
git commit -m "feat(workflow-engine): add WorkflowsScreen for listing, creating, and running workflows"
```

---

### Task 4: Wire into ChatCommandService, main.dart, chat_screen.dart

**Files:**
- Modify: `lib/services/chat_command_service.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/chat_screen.dart`

**Interfaces:**
- Consumes: `WorkflowEngine.instance`, `BackgroundTaskEngine.instance`, `WorkflowsScreen`
- Current `chat_command_service.dart` skill block (lines ~18-36): insert workflow blocks immediately BEFORE the skill run block
- Current `main.dart` init sequence ends at line 495: `await SkillEngine.instance.init();` — add four new lines after it
- Current `chat_screen.dart` PopupMenu (around line 1320): add `'workflows'` item

- [ ] **Step 1: Add workflow imports to ChatCommandService**

At the top of `lib/services/chat_command_service.dart`, after the existing skill engine imports:

```dart
import 'workflow_engine/workflow_engine.dart';
import 'background_task_engine/background_task_engine.dart';
```

- [ ] **Step 2: Insert workflow command detection in ChatCommandService**

In `tryHandleWithGemma()`, insert the two workflow regex blocks BEFORE the existing skill run block (before `// 0. Skill execution:`):

```dart
    // 0a. Workflow execution: "run workflow X" / "execute workflow X" / "launch workflow X"
    final runWfMatch = RegExp(
      r'^(?:run|execute|launch) workflow\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (runWfMatch != null) {
      final name = runWfMatch.group(1)!.trim();
      return await _runWorkflowByName(name);
    }

    // 0b. Workflow generation: "create workflow: X" / "new workflow: X"
    final createWfMatch = RegExp(
      r'^(?:create workflow|new workflow)[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (createWfMatch != null) {
      final description = createWfMatch.group(1)!.trim();
      return await _createWorkflowFromCommand(description);
    }
```

- [ ] **Step 3: Add workflow helper methods to ChatCommandService**

Append before the final closing `}` of the `ChatCommandService` class:

```dart
  Future<String?> _runWorkflowByName(String nameQuery) async {
    final workflows = WorkflowEngine.instance.list();
    if (workflows.isEmpty) {
      return 'No workflows saved. Say "create workflow: [description]" to make one.';
    }

    final lower = nameQuery.toLowerCase();
    final match = workflows.firstWhere(
      (w) => w.name.toLowerCase().contains(lower),
      orElse: () => workflows.firstWhere(
        (w) => lower.contains(w.name.toLowerCase()),
        orElse: () => workflows.first,
      ),
    );

    final isRealMatch = match.name.toLowerCase().contains(lower) ||
        lower.contains(match.name.toLowerCase());
    if (!isRealMatch) {
      return "No workflow named '$nameQuery' found. Available: ${workflows.map((w) => w.name).join(', ')}.";
    }

    final task = await BackgroundTaskEngine.instance.schedule(match.id);
    return task.result ?? '✅ Workflow "${match.name}" complete.';
  }

  Future<String?> _createWorkflowFromCommand(String description) async {
    final workflow = await WorkflowEngine.instance.generate(description);
    if (workflow == null) {
      return 'Could not generate workflow. Create some skills first, then try again.';
    }
    return '✅ Workflow "${workflow.name}" created with ${workflow.stepSkillIds.length} step${workflow.stepSkillIds.length == 1 ? '' : 's'}.';
  }
```

- [ ] **Step 4: Add imports and init calls to main.dart**

Add to the import block in `lib/main.dart` (after the skill engine imports):

```dart
import 'services/workflow_engine/workflow_engine.dart';
import 'services/workflow_engine/workflow_store.dart';
import 'services/background_task_engine/background_task.dart';
import 'services/background_task_engine/background_task_engine.dart';
import 'services/background_task_engine/task_store.dart';
```

In the `main()` init sequence, after `await SkillEngine.instance.init();` (line ~495):

```dart
  await WorkflowStore.instance.init();
  await WorkflowEngine.instance.init();
  await TaskStore.instance.init();
  await BackgroundTaskEngine.instance.init();
```

- [ ] **Step 5: Add Workflows to chat_screen.dart PopupMenu**

Add the import at the top of `lib/screens/chat_screen.dart` (after the `skills_screen.dart` import):

```dart
import 'workflows_screen.dart';
```

In the `PopupMenuButton.onSelected` handler, add after the `'skills'` branch:

```dart
              } else if (value == 'workflows') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const WorkflowsScreen()),
                );
              }
```

In `itemBuilder`, add after the `'skills'` item:

```dart
              const PopupMenuItem(value: 'workflows', child: Text('Workflows')),
```

- [ ] **Step 6: Run the full test suite**

```bash
flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/services/chat_command_service.dart \
        lib/main.dart \
        lib/screens/chat_screen.dart
git commit -m "feat(workflow-engine): wire workflow commands, init sequence, and chat menu"
```
