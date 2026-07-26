import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conversation.dart';
import '../services/conversation_store.dart';

/// List of all stored conversations. Tap to switch, long-press to delete.
///
/// Pops with the picked conversation (or with a sentinel Conversation
/// having id='NEW' when the user taps "新对话").
class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({
    super.key,
    required this.currentConversationId,
  });

  /// The id currently being viewed, so we can mark it as selected and
  /// pop without a swap if the user re-picks the same one.
  final String currentConversationId;

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = ConversationStore.instance.loadAll();
  }

  void _reload() {
    setState(() {
      _future = ConversationStore.instance.loadAll();
    });
  }

  Future<void> _confirm删除(Conversation conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除对话？'),
        content: Text('"${conv.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ConversationStore.instance.delete(conv.id);
      _reload();
    }
  }

  /// Build a relative-time string like "5m ago", "2h ago", "yesterday",
  /// "May 12". Cheap, no l10n, good enough for v1.
  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('对话列表')),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新对话'),
            onTap: () {
              // Sentinel: empty Conversation with id='NEW' signals "start new"
              Navigator.pop(
                context,
                Conversation(id: 'NEW', title: '新对话'),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Conversation>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final convs = snapshot.data!;
                if (convs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '还没有对话。从主页开始聊天吧。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: convs.length,
                  itemBuilder: (_, i) {
                    final c = convs[i];
                    final selected = c.id == widget.currentConversationId;
                    return ListTile(
                      title: Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${c.messages.length} messages • ${_relativeTime(c.updatedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      selected: selected,
                      onTap: () => Navigator.pop(context, c),
                      onLongPress: () => _confirm删除(c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
