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
