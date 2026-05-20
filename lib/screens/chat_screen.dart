import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/conversation_store.dart';
import '../services/gemma_service.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';
import 'conversation_list_screen.dart';

/// The chat screen. Renders one conversation; persists every turn to Hive.
///
/// If `conversation` is null, starts a fresh empty conversation that will
/// be persisted as soon as the first message is sent.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.conversation,
    this.onOpenDiagnostics,
  });

  /// The conversation to display. Null = start a new chat.
  final Conversation? conversation;

  /// Callback to open the diagnostics debug screen from the overflow menu.
  final VoidCallback? onOpenDiagnostics;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Current conversation. Initialized from widget.conversation or a fresh one.
  late Conversation _conversation;

  // Optional attached image for the next outgoing message.
  Uint8List? _pendingImage;
  String? _pendingImageName;

  // Whether Gemma is currently generating; disables input when true.
  bool _busy = false;

  // For auto-scrolling the message list to the bottom on new content.
  final _scrollController = ScrollController();

  // Compaction threshold. Gemma 4 E2B has 128K context; we leave 28K
  // headroom for the system prompt + new message + response.
  static const int _compactionThresholdTokens = 100000;

  // Note prepended to the prompt when older messages are dropped.
  String? _compactionNote;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation ?? Conversation();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent passes a different conversation, swap to it.
    if (widget.conversation != null &&
        widget.conversation!.id != _conversation.id) {
      setState(() {
        _conversation = widget.conversation!;
        _compactionNote = null;
        _pendingImage = null;
        _pendingImageName = null;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingImage = bytes;
      _pendingImageName = picked.name;
    });
  }

  void _clearAttachment() {
    setState(() {
      _pendingImage = null;
      _pendingImageName = null;
    });
  }

  /// Build the prompt sent to Gemma, including conversation history.
  String _buildPromptFromHistory(String newUserText) {
    final buffer = StringBuffer();
    if (_compactionNote != null) {
      buffer.writeln('[Earlier conversation: $_compactionNote]');
      buffer.writeln();
    }
    for (final msg in _conversation.messages) {
      if (msg.isUser) {
        buffer.writeln('User: ${msg.text}');
      } else if (msg.isAssistant) {
        buffer.writeln('Assistant: ${msg.text}');
      }
    }
    buffer.write('User: $newUserText');
    return buffer.toString();
  }

  /// Drop oldest non-system messages until estimated tokens < threshold.
  void _compactIfNeeded() {
    int estimate() {
      int chars = (_compactionNote?.length ?? 0);
      for (final m in _conversation.messages) {
        chars += m.text.length + 20;
      }
      return chars ~/ 4;
    }

    if (estimate() <= _compactionThresholdTokens) return;

    int droppedCount = 0;
    while (estimate() > _compactionThresholdTokens &&
        _conversation.messages.length > 4) {
      _conversation.messages.removeAt(0);
      droppedCount++;
    }
    if (droppedCount > 0) {
      _compactionNote =
          '${droppedCount + (_compactionNote != null ? 1 : 0)} earlier '
          'messages compacted to save context space.';
      debugPrint('🐾 CHAT: compacted, dropped $droppedCount messages');
    }
  }

  Future<void> _handleSend(String text) async {
    if (_busy) return;

    final imageBytes = _pendingImage;
    final userMsg = Message(
      role: MessageRole.user,
      text: text,
      imageBytes: imageBytes,
    );
    final assistantMsg = Message(role: MessageRole.assistant, text: '');

    setState(() {
      _conversation.messages.add(userMsg);
      _conversation.messages.add(assistantMsg);
      _pendingImage = null;
      _pendingImageName = null;
      _busy = true;
    });
    _scrollToBottom();

    // Build prompt from history excluding the empty assistant placeholder
    // we just added.
    final history = _conversation.messages
        .sublist(0, _conversation.messages.length - 1);
    final historyForPrompt = history
        .where((m) => m.text.isNotEmpty || m.hasImage)
        .toList();
    // Cheap reuse of the prompt builder: temporarily swap the messages list.
    final backup = List<Message>.from(_conversation.messages);
    _conversation.messages
      ..clear()
      ..addAll(historyForPrompt.where((m) => m != userMsg));
    final prompt = _buildPromptFromHistory(text);
    _conversation.messages
      ..clear()
      ..addAll(backup);

    _compactIfNeeded();

    try {
      final responseBuffer = StringBuffer();
      await GemmaService.instance.generate(
        prompt,
        imageBytes: imageBytes,
        onToken: (chunk) {
          responseBuffer.write(chunk);
          if (!mounted) return;
          setState(() {
            final lastIdx = _conversation.messages.length - 1;
            _conversation.messages[lastIdx] =
                _conversation.messages[lastIdx].copyWith(
              text: responseBuffer.toString(),
            );
          });
          _scrollToBottom();
        },
      );
    } catch (e, stack) {
      debugPrint('🐾 CHAT: generate failed: $e\n$stack');
      if (mounted) {
        setState(() {
          final lastIdx = _conversation.messages.length - 1;
          _conversation.messages[lastIdx] =
              _conversation.messages[lastIdx].copyWith(text: 'Error: $e');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);

      // Auto-title if this is the first user message in a brand-new chat.
      if (_conversation.title == 'New chat') {
        _conversation.title = _conversation.deriveTitleFromMessages();
      }

      // Persist after every completed turn. Failure here is logged but
      // not surfaced — the in-memory conversation is still usable.
      try {
        await ConversationStore.instance.save(_conversation);
      } catch (e) {
        debugPrint('🐾 CHAT: save failed: $e');
      }
    }
  }

  Future<void> _openConversationList() async {
    final picked = await Navigator.of(context).push<Conversation?>(
      MaterialPageRoute(
        builder: (_) => ConversationListScreen(
          currentConversationId: _conversation.id,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // Special sentinel: empty id = "start new chat"
    if (picked.id == 'NEW') {
      setState(() {
        _conversation = Conversation();
        _compactionNote = null;
      });
    } else {
      setState(() {
        _conversation = picked;
        _compactionNote = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openConversationList,
          tooltip: 'Conversations',
        ),
        title: Text(
          _conversation.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'diagnostics') widget.onOpenDiagnostics?.call();
              if (value == 'clear') {
                setState(() {
                  _conversation = Conversation();
                  _compactionNote = null;
                });
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('New chat')),
              PopupMenuItem(value: 'diagnostics', child: Text('Diagnostics')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<GemmaState>(
            valueListenable: GemmaService.instance.state,
            builder: (context, state, _) {
              if (state == GemmaState.ready ||
                  state == GemmaState.generating) {
                return const SizedBox.shrink();
              }
              return Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bannerForState(state),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (state == GemmaState.notInstalled ||
                          state == GemmaState.error)
                        TextButton(
                          onPressed: widget.onOpenDiagnostics,
                          child: const Text('Set up'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: _conversation.messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _conversation.messages.length,
                    itemBuilder: (_, i) =>
                        MessageBubble(message: _conversation.messages[i]),
                  ),
          ),
          ValueListenableBuilder<GemmaState>(
            valueListenable: GemmaService.instance.state,
            builder: (context, state, _) {
              final modelReady = state == GemmaState.ready ||
                  state == GemmaState.generating;
              return ChatInput(
                onSend: _handleSend,
                enabled: !_busy && modelReady,
                attachedImage: _pendingImage,
                attachedImageName: _pendingImageName,
                onAttachImage: _pickImage,
                onClearAttachment: _clearAttachment,
              );
            },
          ),
        ],
      ),
    );
  }

  String _bannerForState(GemmaState state) {
    switch (state) {
      case GemmaState.notInstalled:
        return 'Claw needs to download its brain (~1.5 GB) before you can chat.';
      case GemmaState.installing:
        return 'Downloading Claw…';
      case GemmaState.installed:
        return 'Claw is installed but not loaded into memory yet.';
      case GemmaState.loading:
        return 'Loading Claw into memory…';
      case GemmaState.error:
        final err = GemmaService.instance.lastError;
        return 'Setup error: ${err ?? "unknown"}';
      case GemmaState.ready:
      case GemmaState.generating:
        return '';
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🐾', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text('Ask Claw anything', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Attach a screenshot, paste text, or just type. Everything runs on-device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
