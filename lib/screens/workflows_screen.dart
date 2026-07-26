import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/pocketclaw_theme.dart';
import '../services/background_task_engine/background_task_engine.dart';
import '../services/marketplace/marketplace_service.dart';
import '../services/skill_engine/skill_model.dart';
import '../services/skill_engine/skill_store.dart';
import '../services/workflow_engine/workflow_engine.dart';
import '../services/workflow_engine/workflow_model.dart';
import '../services/workflow_engine/workflow_store.dart';

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

    setState(() {
      _creating = true;
    });
    dialogSetState?.call(() {});
    final workflow = await WorkflowEngine.instance.generate(description);
    if (!mounted) return;
    setState(() {
      _creating = false;
    });
    dialogSetState?.call(() {});

    if (workflow != null) {
      _descController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Workflow created: ${workflow.name} (${workflow.stepSkillIds.length} step${workflow.stepSkillIds.length == 1 ? '' : 's'})',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '无法生成工作流。请先创建一些技能再试。',
          ),
        ),
      );
    }
  }

  Future<void> _runWorkflow(WorkflowModel workflow) async {
    setState(() {
      _runningId = workflow.id;
    });
    final task = await BackgroundTaskEngine.instance.schedule(workflow.id);
    if (!mounted) return;
    setState(() {
      _runningId = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(task.result ?? '工作流完成')));
  }

  Future<void> _deleteWorkflow(WorkflowModel workflow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PocketClawTheme.bg2,
        title: Text(
          'Delete "${workflow.name}"?',
          style: Theme.of(ctx).textTheme.titleMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '删除',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: PocketClawTheme.error,
                  ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await WorkflowEngine.instance.delete(workflow.id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _exportWorkflow(WorkflowModel workflow) async {
    final skills = <SkillModel>[];
    for (final id in workflow.stepSkillIds) {
      final s = SkillStore.instance.get(id);
      if (s != null) skills.add(s);
    }
    await MarketplaceService.instance.exportBundle(
      skills: skills,
      workflows: [workflow],
      suggestedName: workflow.name,
    );
  }

  void _showCreateDialog() {
    _descController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateInner) => AlertDialog(
          backgroundColor: PocketClawTheme.bg2,
          title: Text(
            '创建工作流',
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
          content: TextField(
            controller: _descController,
            autofocus: true,
            maxLines: 3,
            style: Theme.of(ctx).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: '描述工作流要做什么…',
              hintStyle: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: PocketClawTheme.muted,
                ),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: PocketClawTheme.cyan, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
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
                  : const Text('生成'),
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
        title: Text('工作流', style: theme.textTheme.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: PocketClawTheme.cyan,
            onPressed: _showCreateDialog,
            tooltip: '创建工作流',
          ),
        ],
      ),
      body: ValueListenableBuilder<WorkflowEngineState>(
        valueListenable: WorkflowEngine.instance.state,
        builder: (context, engineState, _) => Column(
          children: [
            if (engineState == WorkflowEngineState.error)
              Container(
                width: double.infinity,
                color: PocketClawTheme.error.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  WorkflowEngine.instance.lastError ?? '工作流引擎错误',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: PocketClawTheme.error,
                  ),
                ),
              ),
            Expanded(
              child: ValueListenableBuilder<Box<String>>(
                valueListenable: WorkflowStore.instance.box.listenable(),
                builder: (context, box, _) {
                  final workflows = WorkflowEngine.instance.list();
                  if (workflows.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_tree_outlined,
                            color: PocketClawTheme.muted,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text('还没有工作流', style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _showCreateDialog,
                            child: const Text('创建一个工作流'),
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
                          onLongPress: () async {
                            final action = await showModalBottomSheet<String>(
                              context: context,
                              backgroundColor: PocketClawTheme.bg2,
                              builder: (ctx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.ios_share,
                                          color: PocketClawTheme.cyan),
                                      title: Text('导出',
                                          style: Theme.of(ctx).textTheme.bodyMedium),
                                      onTap: () => Navigator.pop(ctx, 'export'),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.delete_outline,
                                          color: PocketClawTheme.error),
                                      title: Text('删除',
                                          style: Theme.of(ctx).textTheme.bodyMedium),
                                      onTap: () => Navigator.pop(ctx, 'delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (!mounted) return;
                            if (action == 'export') {
                              await _exportWorkflow(workflow);
                            } else if (action == 'delete') {
                              await _deleteWorkflow(workflow);
                            }
                          },
                          child: Container(
                            decoration: PocketClawTheme.panel(),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        workflow.name,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      if (workflow.description.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          workflow.description,
                                          style: theme.textTheme.bodyLarge,
                                        ),
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
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : FilledButton(
                                        onPressed: () => _runWorkflow(workflow),
                                        child: const Text('运行'),
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
            ),
          ],
        ),
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
