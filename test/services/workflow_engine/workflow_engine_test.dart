import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_model.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_store.dart';
import 'package:pocketclaw/services/background_task_engine/background_task.dart';
import 'package:pocketclaw/services/background_task_engine/task_store.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_generation_service.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_engine.dart';
import 'package:pocketclaw/services/background_task_engine/background_task_engine.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/skill_engine/skill_store.dart';

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

    test('concurrent resume does not double-execute an overdue task', () async {
      final skill = SkillModel(
        id: 'sk-race',
        name: 'Race Skill',
        steps: [],
        createdAt: DateTime(2026, 1, 1),
      );
      await SkillStore.instance.save(skill);
      final wf = WorkflowModel(
        id: 'wf-race',
        name: 'Race Workflow',
        stepSkillIds: ['sk-race'],
        createdAt: DateTime(2026, 1, 1),
      );
      await WorkflowStore.instance.save(wf);

      // Gate execution so two resume passes overlap on the same in-flight task.
      final gate = Completer<void>();
      var execCount = 0;
      WorkflowEngine.instance.skillExecuteOverride = (id) async {
        execCount++;
        await gate.future;
        return '✅ done';
      };

      // Insert an overdue pending task directly (scheduledFor in the past).
      final task = BackgroundTask(
        id: 'task-race',
        title: 'Race Workflow',
        workflowId: 'wf-race',
        status: TaskStatus.pending,
        createdAt: DateTime(2026, 1, 1),
        scheduledFor: DateTime(2020, 1, 1),
      );
      await TaskStore.instance.save(task);

      // Fire two resume passes back-to-back via the public lifecycle hook.
      BackgroundTaskEngine.instance.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      BackgroundTaskEngine.instance.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // Let synchronous prefixes run + microtasks settle while gate is held.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Release the single in-flight run and let it finish.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(execCount, 1, reason: 'overdue task must execute exactly once');
      final updated = WorkflowStore.instance.get('wf-race');
      expect(updated!.runCount, 1);

      WorkflowEngine.instance.skillExecuteOverride = null;
    });
  });
}
