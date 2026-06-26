# Phase 3 — Workflow Engine + Long Running Tasks Design Spec

**Date:** 2026-06-26
**Phase:** 3 of 5 (further_plan.md)
**Owner:** Manoj Shetty (personal side project)
**Status:** Ready for implementation

---

## Goal

Build the Workflow Engine (IFTTT-style trigger-step automation where steps are saved skills) and the Background Task Engine (persistent in-app task scheduling with a hook point for Android WorkManager in Phase 5).

---

## Scope

**In scope (Phase 3):**
- `WorkflowModel` — JSON-serializable: id, name, description, triggerType, stepSkillIds, createdAt, lastRunAt, runCount
- `WorkflowStore` — Hive `Box<String>` persistence wrapper
- `WorkflowGenerationService` — Gemma prompt → WorkflowModel (lists user's skills, asks for ordered subset)
- `WorkflowEngine` — singleton orchestrator: execute, generate, list, delete
- `BackgroundTask` — JSON-serializable task model: id, title, workflowId, status, scheduledFor, createdAt, completedAt, result
- `TaskStore` — Hive `Box<String>` persistence wrapper
- `BackgroundTaskEngine` — singleton: schedule, cancel, list, re-schedule on app resume
- `WorkflowsScreen` — list, create, run, delete workflows
- Wire workflow commands into `ChatCommandService`
- Wire all four new singletons into `main.dart` init sequence
- Add "Workflows" to chat screen PopupMenu

**Out of scope:**
- True background execution via WorkManager (Phase 5) — architecture supports it via hook point
- Task history screen (Phase 4)
- Event-based triggers (`pdf_received`, `on_share`) — Phase 5
- Skill Marketplace (Phase 4)

---

## Architecture

```
User voice/text / scheduled timer
        ↓
ChatCommandService
  "run workflow X"      →  WorkflowEngine.execute(id)
  "create workflow: X"  →  WorkflowGenerationService → Gemma → WorkflowModel
        ↓
WorkflowEngine
  ├── WorkflowStore  (Hive Box<String>)
  └── for each stepSkillId: SkillEngine.instance.execute(skillId)  [sequential]

BackgroundTaskEngine
  ├── TaskStore  (Hive Box<String>)
  └── in-app Timer for scheduled tasks
        ↑ WorkManager hook point for Phase 5
```

**Layering:** `Workflow → Skill → Primitive → Accessibility`
WorkflowEngine never calls PrimitiveEngine directly — always via SkillEngine.

---

## Data Models

### WorkflowModel

```dart
// lib/services/workflow_engine/workflow_model.dart

class WorkflowModel {
  final String id;              // "wf-<timestamp>"
  final String name;            // "Study from PDF"
  final String description;     // "Extract, summarize, and create flashcards"
  final String triggerType;     // "manual" | "scheduled" (Phase 5: "on_share", "pdf_received")
  final List<String> stepSkillIds; // ordered list of skill IDs
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
}
```

### BackgroundTask

```dart
// lib/services/background_task_engine/background_task.dart

enum TaskStatus { pending, running, done, failed, cancelled }

class BackgroundTask {
  final String id;              // "task-<timestamp>"
  final String title;           // human-readable label
  final String? workflowId;     // nullable — task may be standalone
  TaskStatus status;
  final DateTime createdAt;
  DateTime? scheduledFor;       // null = run immediately
  DateTime? completedAt;
  String? result;               // summary string or error message

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

**Hive storage:** `Box<String>` keyed by id — each entry is `jsonEncode(model.toJson())`. No TypeAdapters needed.

---

## Services

### WorkflowStore

```dart
// lib/services/workflow_engine/workflow_store.dart

class WorkflowStore {
  WorkflowStore._();
  static final WorkflowStore instance = WorkflowStore._();

  static const String _boxName = 'workflows';
  Box<String>? _box;

  Future<void> init() async { ... }     // open Hive box
  Future<void> dispose() async {}       // no-op

  Future<void> save(WorkflowModel workflow) async { ... }
  WorkflowModel? get(String id) { ... }
  List<WorkflowModel> getAll() { ... }  // sorted by createdAt descending
  Future<void> delete(String id) async { ... }
  Box<String> get box => _requireBox;   // for listenable
}
```

### TaskStore

```dart
// lib/services/background_task_engine/task_store.dart

class TaskStore {
  TaskStore._();
  static final TaskStore instance = TaskStore._();

  static const String _boxName = 'background_tasks';
  Box<String>? _box;

  Future<void> init() async { ... }
  Future<void> dispose() async {}

  Future<void> save(BackgroundTask task) async { ... }
  BackgroundTask? get(String id) { ... }
  List<BackgroundTask> getAll() { ... }
  List<BackgroundTask> getByStatus(TaskStatus status) { ... }
  Future<void> delete(String id) async { ... }
  Box<String> get box => _requireBox;
}
```

### WorkflowGenerationService

Builds a Gemma prompt listing the user's saved skills (name + description) and asks for a workflow as JSON. Validates that every `stepSkillId` exists in `SkillStore`. Returns `null` on any failure — never throws.

**Prompt template:**
```
You are a workflow generator for PocketClaw, a private on-device Android assistant.

Available skills:
<list each skill as "- id: <id>  name: <name>  description: <description>">

Generate a workflow for: "<description>"

A workflow is an ordered sequence of skill IDs to execute in order.

Respond with ONLY valid JSON (no explanation, no markdown):
{"name":"<short name>","description":"<one sentence>","stepSkillIds":["<id>","<id>",...],"triggerType":"manual"}
```

Uses `@visibleForTesting Future<WorkflowModel?> Function(String)? generateOverride` for tests (same pattern as SkillGenerationService).

### WorkflowEngine

```dart
// lib/services/workflow_engine/workflow_engine.dart

enum WorkflowEngineState { idle, generating, executing, error }

class WorkflowEngine {
  WorkflowEngine._();
  static final WorkflowEngine instance = WorkflowEngine._();

  final ValueNotifier<WorkflowEngineState> _state =
      ValueNotifier(WorkflowEngineState.idle);
  ValueListenable<WorkflowEngineState> get state => _state;
  String? lastError;

  Future<void> init() async {}
  Future<void> dispose() async { _state.dispose(); }

  List<WorkflowModel> list() => WorkflowStore.instance.getAll();
  WorkflowModel? get(String id) => WorkflowStore.instance.get(id);

  /// Execute all steps sequentially. Returns a multi-line summary string.
  /// Never throws — errors update state and return error string.
  Future<String> execute(String workflowId) async { ... }

  /// Generate a new workflow from natural-language description.
  /// Returns WorkflowModel on success, null on failure. Never throws.
  Future<WorkflowModel?> generate(String description) async { ... }

  Future<void> delete(String id) async { ... }
}
```

`execute()` runs each `stepSkillId` via `SkillEngine.instance.execute()` in a loop, collects per-step results, increments `runCount`, updates `lastRunAt`, saves back to store. If a skill ID is not found, that step is skipped with a "skill not found" note in the result. The workflow always completes (never aborts mid-run).

### BackgroundTaskEngine

```dart
// lib/services/background_task_engine/background_task_engine.dart

enum BackgroundTaskEngineState { idle, running, error }

class BackgroundTaskEngine with WidgetsBindingObserver {
  BackgroundTaskEngine._();
  static final BackgroundTaskEngine instance = BackgroundTaskEngine._();

  final ValueNotifier<BackgroundTaskEngineState> _state =
      ValueNotifier(BackgroundTaskEngineState.idle);
  ValueListenable<BackgroundTaskEngineState> get state => _state;

  // Active timers keyed by taskId — WorkManager hook point for Phase 5
  final Map<String, Timer> _timers = {};

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    _resumePendingTasks();  // re-schedule tasks that survived a restart
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    _state.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumePendingTasks();
  }

  /// Schedule a workflow to run. runAt null = run immediately.
  /// Returns the created BackgroundTask. Never throws.
  Future<BackgroundTask> schedule(String workflowId, {DateTime? runAt}) async { ... }

  /// Cancel a pending task. No-op if already running/done/failed.
  Future<void> cancel(String taskId) async { ... }

  List<BackgroundTask> list() => TaskStore.instance.getAll();
  List<BackgroundTask> pending() =>
      TaskStore.instance.getByStatus(TaskStatus.pending);

  void _resumePendingTasks() { ... }  // re-arms Timers for persisted pending tasks
  Future<void> _runTask(BackgroundTask task) async { ... }  // executes via WorkflowEngine
}
```

`_resumePendingTasks()` reads all `pending` tasks from TaskStore. For tasks whose `scheduledFor` is null or in the past, runs immediately. For future tasks, sets a `Timer` for the remaining duration.

---

## WorkflowsScreen

`lib/screens/workflows_screen.dart` — full-page screen accessible from chat screen PopupMenu.

**States:**
- Empty: "No workflows yet" + "Create a Workflow" button
- List: `ListView.builder` of workflow cards
- Each card: name, description, step count, last run time, "Run" button, long-press to delete

**Create workflow flow:**
1. Tap "Create Workflow"
2. Text input dialog: "Describe what the workflow should do"
3. `WorkflowEngine.instance.generate(description)` — shows loading indicator
4. On success: snackbar "Workflow created: {name} ({N} steps)" + list refreshes
5. On failure: snackbar "Could not generate workflow. Try a clearer description."

**Run workflow flow:**
1. Tap "Run" → `BackgroundTaskEngine.instance.schedule(workflow.id)` (immediate)
2. Shows per-card running indicator while task is executing
3. On completion: snackbar with result summary

**Design:** Neobrutalism — `PocketClawTheme.panel()` cards, cyan borders, hardShadow. All colors from PocketClawTheme tokens.

---

## ChatCommandService Additions

Insert before existing skill commands (which are before Gemma fallback):

```dart
// Workflow execution: "run workflow X" / "execute workflow X" / "launch workflow X"
final runWfMatch = RegExp(
  r'^(?:run|execute|launch) workflow\s+(.+)$',
  caseSensitive: false,
).firstMatch(trimmed);
if (runWfMatch != null) {
  final name = runWfMatch.group(1)!.trim();
  return await _runWorkflowByName(name);
}

// Workflow generation: "create workflow: X" / "new workflow: X"
final createWfMatch = RegExp(
  r'^(?:create workflow|new workflow)[:\s]+(.+)$',
  caseSensitive: false,
).firstMatch(trimmed);
if (createWfMatch != null) {
  final description = createWfMatch.group(1)!.trim();
  return await _createWorkflowFromCommand(description);
}
```

`_runWorkflowByName` — case-insensitive prefix match, schedules via `BackgroundTaskEngine.instance.schedule()`, returns confirmation string.
`_createWorkflowFromCommand` — delegates to `WorkflowEngine.instance.generate()`, returns confirmation or error.

---

## main.dart Init Sequence

Add after `SkillEngine.instance.init()`:
```dart
await WorkflowStore.instance.init();
await WorkflowEngine.instance.init();
await TaskStore.instance.init();
await BackgroundTaskEngine.instance.init();
```

---

## chat_screen.dart PopupMenu

Add "Workflows" item to existing `PopupMenuButton`:
```dart
PopupMenuItem(value: 'workflows', child: Text('Workflows')),
```
Handler navigates to `WorkflowsScreen`.

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Gemma returns invalid JSON | `WorkflowGenerationService.generate()` returns `null`; no crash |
| stepSkillId not in SkillStore | Step skipped with "Skill not found" note in result; workflow continues |
| All steps fail | `WorkflowEngine.execute()` returns summary of all failures; state → error |
| Task timer fires but app offline from Gemma | `SkillEngine.execute()` returns error string; task marked failed |
| `WorkflowStore` not initialized | `_requireBox` throws `StateError`; caught in `WorkflowEngine` |

---

## Tests

### workflow_engine_test.dart (`test/services/workflow_engine/`)

- `WorkflowModel.toJson() / fromJson()` round-trip — all fields preserved including nullable lastRunAt
- `WorkflowModel.fromJson()` with missing optional fields — uses defaults
- `WorkflowStore.save() / get() / getAll() / delete()` — CRUD round-trip
- `WorkflowStore.getAll()` — sorted by createdAt descending
- `WorkflowEngine.execute()` — mock SkillEngine override → returns multi-step summary
- `WorkflowEngine.execute()` with unknown workflowId — sets state to error, returns error string
- `WorkflowEngine.execute()` with one invalid skillId — skips that step, continues, returns partial summary
- `WorkflowEngine.generate()` — mock Gemma returns valid JSON → WorkflowModel created + saved
- `WorkflowEngine.generate()` — mock Gemma returns invalid JSON → returns null, no crash
- `WorkflowGenerationService` extracts JSON block from response with surrounding text

### background_task_engine_test.dart (`test/services/background_task_engine/`)

- `BackgroundTask.toJson() / fromJson()` round-trip — all fields preserved
- `BackgroundTask.fromJson()` with unknown status string — falls back to pending
- `TaskStore.save() / get() / getAll() / getByStatus() / delete()` — CRUD + filter
- `BackgroundTaskEngine.schedule()` with runAt=null — task runs immediately, status becomes done
- `BackgroundTaskEngine.schedule()` with future runAt — task status pending, timer armed
- `BackgroundTaskEngine.cancel()` — pending task marked cancelled, timer cleared
- `BackgroundTaskEngine._resumePendingTasks()` — overdue pending tasks run immediately

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `lib/services/workflow_engine/workflow_model.dart` | Create | WorkflowModel data class + JSON |
| `lib/services/workflow_engine/workflow_store.dart` | Create | Hive Box<String> persistence |
| `lib/services/workflow_engine/workflow_generation_service.dart` | Create | Gemma prompt → WorkflowModel |
| `lib/services/workflow_engine/workflow_engine.dart` | Create | Orchestrator singleton |
| `lib/services/background_task_engine/background_task.dart` | Create | BackgroundTask data class + JSON |
| `lib/services/background_task_engine/task_store.dart` | Create | Hive Box<String> persistence |
| `lib/services/background_task_engine/background_task_engine.dart` | Create | Scheduler singleton |
| `lib/screens/workflows_screen.dart` | Create | List/Create/Run/Delete UI |
| `lib/services/chat_command_service.dart` | Modify | Add workflow command detection |
| `lib/main.dart` | Modify | Init all four new singletons |
| `lib/screens/chat_screen.dart` | Modify | Add "Workflows" PopupMenu item |
| `test/services/workflow_engine/workflow_engine_test.dart` | Create | Unit tests |
| `test/services/background_task_engine/background_task_engine_test.dart` | Create | Unit tests |
