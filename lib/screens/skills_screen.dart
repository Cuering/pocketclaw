import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
                      await _createSkill(dialogSetState: setStateInner);
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
