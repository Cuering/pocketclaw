import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:image_picker/image_picker.dart';

import '../models/conversation.dart';
import '../models/document.dart';
import '../services/document_store.dart';
import '../services/rag_service.dart';
import '../models/message.dart';
import '../services/conversation_store.dart';
import '../services/gemma_service.dart';
import '../services/prefs_service.dart';
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

  // Documents indexed for the current conversation. Loaded once on init
  // and after every successful index. Drives the chip strip above the
  // input bar and the RAG retrieval in _handleSend.
  List<Document> _documents = const [];

  // True while a document is being chunked + embedded. Disables the
  // attach button to prevent double-indexing and shows a snackbar.
  bool _indexing = false;

  // Remembered failed send (for the Retry button on a failed assistant
  // bubble). Cleared on success or on a fresh send. We also keep the
  // bytes so retry recreates the exact same multimodal request.
  String? _lastFailedText;
  Uint8List? _lastFailedImage;

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
    _loadDocuments();
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
        _documents = const [];
      });
      _loadDocuments();
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
    try {
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
    } catch (e, stack) {
      debugPrint('🐾 CHAT: image pick failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t open image picker.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
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
    var prompt = _buildPromptFromHistory(text);
    _conversation.messages
      ..clear()
      ..addAll(backup);

    _compactIfNeeded();

    // RAG: if any documents are indexed for this conversation, retrieve
    // the top chunks for the user's query and prepend them as context.
    // Soft-fails: if retrieval errors, we just send the prompt as-is so
    // chat keeps working even if the embedder or vector store dies.
    if (_documents.isNotEmpty) {
      try {
        var hits = await RagService.instance.retrieve(
          query: text,
          conversationId: _conversation.id,
        );

        // Fallback for generic queries: "summarise", "explain", "tldr",
        // "what's this about" — these have no semantic overlap with the
        // doc's actual content, so similarity search misses. When the
        // query looks like one of these AND retrieval was empty (or only
        // brought back low-quality hits), fall back to filename-anchored
        // retrieval which grabs doc starts regardless of query terms.
        final lower = text.toLowerCase();
        // Generic queries also fire fallback when retrieval was sparse
        // (1 or fewer hits) — a single tangential chunk + Gemma's training
        // data hallucination is worse than admitting we have nothing.
        final isGenericIntent = hits.length <= 1 &&
            (lower.contains('summari') ||
                lower.contains('summary') ||
                lower.contains('tldr') ||
                lower.contains('tl;dr') ||
                lower.contains('explain') ||
                lower.contains('describe') ||
                lower.contains('what is this') ||
                lower.contains("what's this") ||
                lower.contains('what is the') ||
                lower.contains('overview') ||
                lower.contains('key point') ||
                lower.contains('main idea') ||
                lower.contains('the document') ||
                lower.contains('the doc') ||
                lower.contains('the file') ||
                lower.contains('the pdf'));
        if (isGenericIntent) {
          debugPrint('🐾 CHAT: generic query, using filename-anchored fallback');
          hits = await RagService.instance.getDocStarts(
            conversationId: _conversation.id,
          );
        }

        if (hits.isNotEmpty) {
          final context = StringBuffer();
          context.writeln('Use the following document excerpts to answer:');
          for (final h in hits) {
            context.writeln();
            context.writeln('[From ${h.docName}]');
            context.writeln(h.content);
          }
          context.writeln();
          context.writeln('---');
          prompt = '${context.toString()}\n$prompt';
          debugPrint('🐾 CHAT: prepended ${hits.length} RAG chunks');
        }
      } catch (e, stack) {
        debugPrint('🐾 CHAT: retrieval failed (soft-fail): $e\n$stack');
      }
    }

    try {
      final responseBuffer = StringBuffer();
      await GemmaService.instance.generate(
        prompt,
        imageBytes: imageBytes,
        userName: PrefsService.instance.current.name,
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
          // Remember what failed so the Retry button can re-run it.
          _lastFailedText = text;
          _lastFailedImage = imageBytes;
          final lastIdx = _conversation.messages.length - 1;
          // Tag the assistant message with a sentinel that the bubble
          // renderer recognises and replaces with a Retry UI.
          _conversation.messages[lastIdx] =
              _conversation.messages[lastIdx].copyWith(
            text: '__CLAW_ERROR__',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          // If we got here without setting _lastFailedText, the run
          // succeeded -- clear any previous failure marker.
          // We use the empty-string check on the trailing assistant message
          // as a proxy for "did anything stream in?".
          if (_conversation.messages.isNotEmpty &&
              _conversation.messages.last.text != '__CLAW_ERROR__' &&
              _conversation.messages.last.text.isNotEmpty) {
            _lastFailedText = null;
            _lastFailedImage = null;
          }
        });
      }

      // Auto-title if this is the first user message in a brand-new chat.
      if (_conversation.title == 'New chat') {
        _conversation.title = _conversation.deriveTitleFromMessages();
      }

      // Persist after every completed turn. Failure here is logged but
      // not surfaced — the in-memory conversation is still usable.
      try {
        await ConversationStore.instance.save(_conversation);
      } catch (e, stack) {
        debugPrint('🐾 CHAT: save failed: $e\n$stack');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Couldn\'t save this conversation.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Load the documents indexed for the current conversation. Cheap —
  /// just walks the Hive box filtering by conversation_id.
  Future<void> _loadDocuments() async {
    try {
      final docs = await DocumentStore.instance
          .loadForConversation(_conversation.id);
      if (!mounted) return;
      setState(() => _documents = docs);
    } catch (e, stack) {
      debugPrint('🐾 CHAT: _loadDocuments failed: $e\n$stack');
      // Soft-fail: empty list, chat keeps working.
    }
  }

  /// Open file picker, read selected .txt file, hand off to RagService
  /// for chunking + embedding + storage. Snackbar progress, chip
  /// strip refresh on success.
  Future<void> _pickAndIndexDocument() async {
    if (_indexing) return;
    if (GemmaService.instance.embedderState.value !=
        EmbedderState.installed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Claw is still getting ready. Just a moment…"),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'pdf'],
        withData: true,
      );
    } catch (e, stack) {
      debugPrint('🐾 CHAT: file picker failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the file picker."),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't read that file."),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Extract text based on file type. PDF -> Syncfusion. txt/md -> UTF-8.
    final ext = file.extension?.toLowerCase() ?? '';
    String text;
    try {
      if (ext == 'pdf') {
        final pdfDoc = PdfDocument(inputBytes: bytes);
        text = PdfTextExtractor(pdfDoc).extractText();
        pdfDoc.dispose();
      } else {
        text = String.fromCharCodes(bytes);
      }
    } catch (e, stack) {
      debugPrint('🐾 CHAT: text extraction failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Claw couldn't read that file. Try a different one?"),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file looks empty.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _indexing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reading ${file.name}…'),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      // Persist the conversation FIRST if it has no messages yet, so
      // the document's conversationId points at something that will
      // exist when the user later reopens the chat.
      if (_conversation.messages.isEmpty &&
          _conversation.title == 'New chat') {
        _conversation.title = file.name;
        await ConversationStore.instance.save(_conversation);
      }

      final doc = await RagService.instance.indexDocument(
        text: text,
        name: file.name,
        conversationId: _conversation.id,
      );

      await _loadDocuments();
      if (!mounted) return;

      // Append a user message bubble showing the attachment, persist it.
      // This is what makes the doc visible in chat history (Option A).
      final docMsg = Message(
        role: MessageRole.user,
        text: '',
        attachedDocId: doc.id,
        attachedDocName: doc.name,
        attachedDocChunkCount: doc.chunkCount,
      );
      setState(() {
        _conversation.messages.add(docMsg);
      });
      try {
        await ConversationStore.instance.save(_conversation);
      } catch (e) {
        debugPrint('🐾 CHAT: failed to save doc msg: $e');
      }
      _scrollToBottom();

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Done! Ask Claw about ${file.name}.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stack) {
      debugPrint('🐾 CHAT: indexDocument failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Claw couldn't read that file. Try a different one?"),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _indexing = false);
    }
  }

  /// Remove a document from the conversation's context. Soft-delete:
  /// chunks remain orphans in the vector store but become invisible
  /// because we filter by conversation_id at retrieve time.
  Future<void> _removeDocument(Document doc) async {
    try {
      await RagService.instance.deleteDocument(doc);
      await _loadDocuments();
    } catch (e, stack) {
      debugPrint('🐾 CHAT: _removeDocument failed: $e\n$stack');
    }
  }

  /// Open a bottom sheet showing what's known about an indexed doc.
  /// The original bytes aren't kept around (only chunks in the vector
  /// store), so for now the preview shows metadata + suggested questions.
  /// v2 can fetch chunk contents back by id and show them in full.
  Future<void> _previewDocument(String docId) async {
    final doc = await DocumentStore.instance.getById(docId);
    if (doc == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DocumentPreviewSheet(document: doc),
    );
  }

  /// Re-runs the last failed user send. The failed assistant bubble is
  /// removed first so the new attempt produces a fresh one.
  Future<void> _retry() async {
    final text = _lastFailedText;
    final image = _lastFailedImage;
    if (text == null) return;
    setState(() {
      // Drop the last two messages (the user msg + the failed assistant msg)
      // so _handleSend re-adds them cleanly.
      if (_conversation.messages.length >= 2) {
        _conversation.messages.removeLast();
        _conversation.messages.removeLast();
      }
      _pendingImage = image;
      _lastFailedText = null;
      _lastFailedImage = null;
    });
    await _handleSend(text);
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
        _documents = const [];
      });
      _loadDocuments();
    } else {
      setState(() {
        _conversation = picked;
        _compactionNote = null;
        _documents = const [];
      });
      _loadDocuments();
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
                  _documents = const [];
                });
                _loadDocuments();
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
                      if (state == GemmaState.error)
                        TextButton(
                          onPressed: () {
                            // Re-bootstrap Gemma. init() is safe to call again.
                            GemmaService.instance.init();
                          },
                          child: const Text('Retry'),
                        ),
                      if (state == GemmaState.notInstalled)
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
                    itemBuilder: (_, i) {
                    final m = _conversation.messages[i];
                    // Only attach retry to the last message if it's a failed one.
                    final isLastFailed = i == _conversation.messages.length - 1 &&
                        m.text == '__CLAW_ERROR__';
                    return MessageBubble(
                      message: m,
                      onRetry: isLastFailed ? _retry : null,
                      onDocTap: m.hasDoc
                          ? () => _previewDocument(m.attachedDocId!)
                          : null,
                    );
                  },
                  ),
          ),
          if (_documents.isNotEmpty)
            _DocumentChipsBar(
              documents: _documents,
              onRemove: _removeDocument,
              onTap: (d) => _previewDocument(d.id),
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
                onAttachDocument: _pickAndIndexDocument,
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
        return 'Claw needs to finish setup before you can chat.';
      case GemmaState.installing:
        return 'Setting up Claw…';
      case GemmaState.installed:
        return 'Almost ready…';
      case GemmaState.loading:
        return 'Almost ready…';
      case GemmaState.error:
        return 'Couldn\'t start Claw. Check your connection and try again.';
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

class _DocumentChipsBar extends StatelessWidget {
  const _DocumentChipsBar({
    required this.documents,
    required this.onRemove,
    required this.onTap,
  });

  final List<Document> documents;
  final void Function(Document) onRemove;
  final void Function(Document) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: theme.colorScheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: documents.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d = documents[i];
          return InputChip(
            avatar: const Icon(Icons.description_outlined, size: 18),
            label: Text(
              d.name,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => onTap(d),
            onDeleted: () => onRemove(d),
            deleteIcon: const Icon(Icons.close, size: 16),
          );
        },
      ),
    );
  }
}


class _DocumentPreviewSheet extends StatefulWidget {
  const _DocumentPreviewSheet({required this.document});

  final Document document;

  @override
  State<_DocumentPreviewSheet> createState() => _DocumentPreviewSheetState();
}

class _DocumentPreviewSheetState extends State<_DocumentPreviewSheet> {
  late Future<List<RetrievedChunk>> _chunksFuture;

  @override
  void initState() {
    super.initState();
    _chunksFuture = RagService.instance
        .getDocStarts(
          conversationId: widget.document.conversationId,
          perDocLimit: widget.document.chunkCount,
        )
        .then((all) =>
            all.where((c) => c.docName == widget.document.name).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.document.name,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.document.chunkCount} sections',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<RetrievedChunk>>(
                future: _chunksFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                        child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final chunks = snap.data ?? const [];
                  if (chunks.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "Couldn't load the document content.",
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  final sorted = [...chunks]
                    ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const Divider(height: 24),
                    itemBuilder: (_, i) {
                      final c = sorted[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Section ${c.chunkIndex + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            c.content,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
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
}
