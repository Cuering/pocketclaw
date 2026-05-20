import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message.dart';
import '../services/gemma_service.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

/// Single-conversation chat screen.
///
/// Holds the message list in memory (v1; persistence in B3).
/// Streams Gemma's response token-by-token into the trailing assistant
/// message bubble for a real chat feel.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.onOpenDiagnostics});

  /// Optional callback so the app bar overflow menu can route to the
  /// existing diagnostic screen.
  final VoidCallback? onOpenDiagnostics;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // In-memory conversation. B3 will persist via Hive.
  final List<Message> _messages = [];

  // Optional attached image for the next outgoing message.
  Uint8List? _pendingImage;
  String? _pendingImageName;

  // Whether Gemma is currently generating; disables input when true.
  bool _busy = false;

  // For auto-scrolling the message list to the bottom on new content.
  final _scrollController = ScrollController();

  // Cheap token estimate: chars / 4. Used to gate compaction.
  // Gemma 4 E2B has 128K context. We compact when estimate exceeds 100K
  // so the actual prompt + response always fits with headroom.
  static const int _compactionThresholdTokens = 100000;

  // Hint shown if we drop messages during compaction. We prepend this as
  // a synthetic system note so Gemma knows there was prior context.
  String? _compactionNote;

  @override
  void initState() {
    super.initState();
    _bootstrapModel();
  }

  Future<void> _bootstrapModel() async {
    // Wait for model to be ready. If it's not installed/loaded, we expect
    // the user to have done that in the diagnostic screen first. We show
    // a banner in build() to point them there if not ready.
    // (B3 task: collapse model setup into a proper onboarding flow.)
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // Defer to next frame so the new message is in the layout tree.
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

  /// Build the full prompt that gets sent to Gemma for this turn.
  ///
  /// Concatenates the conversation history as text. This is the conversation
  /// memory mechanism — Gemma sees every turn. Compaction drops old turns
  /// (B2 will upgrade to LLM-summarised compaction).
  String _buildPromptFromHistory(String newUserText) {
    final buffer = StringBuffer();
    if (_compactionNote != null) {
      buffer.writeln('[Earlier conversation: $_compactionNote]');
      buffer.writeln();
    }
    for (final msg in _messages) {
      if (msg.isUser) {
        buffer.writeln('User: ${msg.text}');
      } else if (msg.isAssistant) {
        buffer.writeln('Assistant: ${msg.text}');
      }
    }
    buffer.write('User: $newUserText');
    return buffer.toString();
  }

  /// Drop oldest non-system messages until the estimated token count
  /// falls under the threshold. Records what was dropped in _compactionNote.
  void _compactIfNeeded() {
    int estimate() {
      int chars = (_compactionNote?.length ?? 0);
      for (final m in _messages) {
        chars += m.text.length + 20; // +20 for role labels
      }
      return chars ~/ 4;
    }

    if (estimate() <= _compactionThresholdTokens) return;

    int droppedCount = 0;
    while (estimate() > _compactionThresholdTokens && _messages.length > 4) {
      _messages.removeAt(0);
      droppedCount++;
    }
    if (droppedCount > 0) {
      _compactionNote =
          '${droppedCount + (_compactionNote != null ? 1 : 0)} earlier messages compacted to save context space.';
      debugPrint('🐾 CHAT: compacted, dropped $droppedCount messages');
    }
  }

  Future<void> _handleSend(String text) async {
    if (_busy) return;

    // Snapshot the attached image (we'll clear pending state immediately
    // so the chip disappears from the input bar as the message appears).
    final imageBytes = _pendingImage;

    final userMsg = Message(
      role: MessageRole.user,
      text: text,
      imageBytes: imageBytes,
    );

    // Placeholder assistant message; we'll mutate its text as tokens stream in.
    final assistantMsg = Message(role: MessageRole.assistant, text: '');

    setState(() {
      _messages.add(userMsg);
      _messages.add(assistantMsg);
      _pendingImage = null;
      _pendingImageName = null;
      _busy = true;
    });
    _scrollToBottom();

    // Build prompt with full conversation history (excluding the empty
    // assistant placeholder we just added).
    final history = _messages.sublist(0, _messages.length - 1);
    final historyForPrompt = history.where((m) => m.text.isNotEmpty).toList();

    // Temporary swap: build prompt using historyForPrompt by reassigning.
    final historyBackup = List<Message>.from(_messages);
    _messages
      ..clear()
      ..addAll(historyForPrompt.where((m) => m != userMsg));
    final prompt = _buildPromptFromHistory(text);
    _messages
      ..clear()
      ..addAll(historyBackup);

    // Compaction check on the in-memory list (drops oldest if needed).
    _compactIfNeeded();

    try {
      final responseBuffer = StringBuffer();
      await GemmaService.instance.generate(
        prompt,
        imageBytes: imageBytes,
        onToken: (chunk) {
          responseBuffer.write(chunk);
          if (!mounted) return;
          // Mutate the placeholder assistant message in place by replacing
          // it with a new Message that has the accumulated text.
          setState(() {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
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
          final lastIdx = _messages.length - 1;
          _messages[lastIdx] = _messages[lastIdx].copyWith(
            text: 'Error: $e',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claw'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'diagnostics') widget.onOpenDiagnostics?.call();
              if (value == 'clear') {
                setState(() {
                  _messages.clear();
                  _compactionNote = null;
                });
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear chat')),
              PopupMenuItem(value: 'diagnostics', child: Text('Diagnostics')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Model-state banner — shows install/load status from the
          // singleton's ValueListenable.
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
            child: _messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => MessageBubble(message: _messages[i]),
                  ),
          ),
          ChatInput(
            onSend: _handleSend,
            enabled: !_busy,
            attachedImage: _pendingImage,
            attachedImageName: _pendingImageName,
            onAttachImage: _pickImage,
            onClearAttachment: _clearAttachment,
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
            Text(
              '🐾',
              style: TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'Ask Claw anything',
              style: theme.textTheme.titleLarge,
            ),
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
