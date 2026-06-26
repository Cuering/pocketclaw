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

  final ValueNotifier<BackgroundTaskEngineState> _state = ValueNotifier(
    BackgroundTaskEngineState.idle,
  );
  ValueListenable<BackgroundTaskEngineState> get state => _state;

  // Keyed by taskId — WorkManager hook point for Phase 5.
  final Map<String, Timer> _timers = {};
  // Task ids currently executing. Guards the exactly-once contract: a
  // concurrent _resumePendingTasks (init + rapid app-resume events) must
  // never start a second run of a task already in flight.
  final Set<String> _running = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _resumePendingTasks();
    debugPrint('🐾 TASK ENGINE: initialized');
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _running.clear();
    _state.dispose();
    debugPrint('🐾 TASK ENGINE: disposed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🐾 TASK ENGINE: app resumed — checking pending tasks');
      _resumePendingTasks(); // fire-and-forget
    }
  }

  /// Schedule a workflow to run.
  ///
  /// runAt null or in the past: runs immediately, awaits completion, returns
  /// the completed task (status done or failed).
  ///
  /// runAt in the future: arms a Timer, returns the pending task immediately.
  /// Never throws.
  Future<BackgroundTask> schedule(String workflowId, {DateTime? runAt}) async {
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
      debugPrint(
        '🐾 TASK ENGINE: scheduled task ${task.id} for workflow $workflowId',
      );

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

  Future<void> _resumePendingTasks() async {
    final tasks = TaskStore.instance.getByStatus(TaskStatus.pending);
    final now = DateTime.now();
    for (final task in tasks) {
      if (_timers.containsKey(task.id)) continue; // already armed
      final runAt = task.scheduledFor;
      if (runAt == null || !runAt.isAfter(now)) {
        // Overdue — run immediately
        debugPrint('🐾 TASK ENGINE: resuming overdue task ${task.id}');
        await _runTask(task);
      } else {
        final delay = runAt.difference(now);
        _timers[task.id] = Timer(delay, () async {
          _timers.remove(task.id);
          await _runTask(task);
        });
        debugPrint(
          '🐾 TASK ENGINE: re-armed task ${task.id} for ${delay.inSeconds}s',
        );
      }
    }
  }

  Future<void> _runTask(BackgroundTask task) async {
    // Exactly-once guard. The synchronous prefix here (the membership check +
    // add) runs to completion before any await yields, so a concurrent caller
    // that already selected this still-pending task is turned away.
    if (_running.contains(task.id)) {
      debugPrint('🐾 TASK ENGINE: task ${task.id} already running — skipping');
      return;
    }
    _running.add(task.id);

    _state.value = BackgroundTaskEngineState.running;
    task.status = TaskStatus.running;
    await TaskStore.instance.save(task);
    debugPrint('🐾 TASK ENGINE: running task ${task.id}');

    try {
      final result = await WorkflowEngine.instance.execute(
        task.workflowId ?? '',
      );
      task.status = TaskStatus.done;
      task.result = result;
      task.completedAt = DateTime.now();
      debugPrint('🐾 TASK ENGINE: task ${task.id} done');
    } catch (e) {
      task.status = TaskStatus.failed;
      task.result = 'Error: $e';
      task.completedAt = DateTime.now();
      debugPrint('🐾 TASK ENGINE: task ${task.id} failed: $e');
    } finally {
      _running.remove(task.id);
    }

    await TaskStore.instance.save(task);
    _state.value = BackgroundTaskEngineState.idle;
  }
}
