import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/pocketclaw_theme.dart';
import '../services/marketplace/marketplace_service.dart';
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

  Future<void> _createSkill({StateSetter? dialogSetState}) async {
    final description = _descController.text.trim();
    if (description.isEmpty) return;

    setState(() { _creating = true; });
    dialogSetState?.call(() {});
    final skill = await SkillEngine.instance.generate(description);
    if (!mounted) return;
    setState(() { _creating = false; });
    dialogSetState?.call(() {});

    if (skill != null) {
      _descController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Skill created: ${skill.name}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法生成技能。请写得更清楚一些。')),
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
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
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

  Future<void> _exportSkill(SkillModel skill) async {
    await MarketplaceService.instance.exportBundle(
      skills: [skill],
      suggestedName: skill.name,
    );
  }

  void _showCreateDialog() {
    _descController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateInner) => AlertDialog(
          backgroundColor: PocketClawTheme.bg2,
          title: Text('创建技能',
              style: Theme.of(ctx).textTheme.titleMedium),
          content: TextField(
            controller: _descController,
            autofocus: true,
            maxLines: 3,
            style: Theme.of(ctx).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: '描述技能要做什么…',
              hintStyle: TextStyle(color: PocketClawTheme.muted),
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
                      await _createSkill(dialogSetState: setStateInner);
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
        title: Text('技能', style: theme.textTheme.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: PocketClawTheme.cyan,
            onPressed: _showCreateDialog,
            tooltip: '创建技能',
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
                  Text('还没有技能',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _showCreateDialog,
                    child: const Text('创建一个技能'),
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
                      await _exportSkill(skill);
                    } else if (action == 'delete') {
                      await _deleteSkill(skill);
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
    );
  }
}
