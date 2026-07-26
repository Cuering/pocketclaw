import 'dart:typed_data';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/pocketclaw_theme.dart';
import '../core/status_words.dart';
import '../models/conversation.dart';
import '../models/document.dart';
import '../services/document_store.dart';
import '../services/rag_service.dart';
import '../models/message.dart';
import '../services/conversation_store.dart';
import '../services/gemma_service.dart';
import '../services/prefs_service.dart';
import '../services/voice_service.dart';
import '../services/chat_command_service.dart';
import '../services/device_actions_service.dart';
import '../services/overlay_controller_service.dart';
import '../services/web_search_service.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';
import 'conversation_list_screen.dart';
import 'skills_screen.dart';
import 'workflows_screen.dart';
import '../services/marketplace/marketplace_service.dart';

const String kMainPortName = 'pocketclaw_main_port';

/// The chat screen. Renders one conversation; persists every turn to Hive.
///
/// If `conversation` is null, starts a fresh empty conversation that will
/// be persisted as soon as the first message is sent.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.conversation});

  /// The conversation to display. Null = start a new chat.
  final Conversation? conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // Current conversation. Initialized from widget.conversation or a fresh one.
  late Conversation _conversation;

  // Optional attached image for the next outgoing message.
  Uint8List? _pendingImage;
  String? _pendingImageName;
  String? _pendingImageSummary;
  bool _preparingImageSummary = false;
  Document? _pendingDocument;
  String? _pendingDocumentText;

  // Documents indexed for the current conversation. Used for preview/history
  // lookup and document-intent RAG retrieval; not shown as persistent chips.
  List<Document> _documents = const [];

  // True while a document is being chunked + embedded. Disables the
  // attach button to prevent double-indexing and shows inline status.
  bool _indexing = false;
  String? _indexingDocumentName;
  String _indexingStatus = StatusWords.random();
  String _thinkingStatus = StatusWords.random();

  // Remembered failed send (for the Retry button on a failed assistant
  // bubble). Cleared on success or on a fresh send. We also keep the
  // bytes so retry recreates the exact same multimodal request.
  String? _lastFailedText;
  Uint8List? _lastFailedImage;
  String? _lastFailedImageName;
  String? _lastFailedImageSummary;

  // Whether Gemma is currently generating; disables input when true.
  bool _busy = false;

  // For auto-scrolling the message list to the bottom on new content.
  final _scrollController = ScrollController();
  ReceivePort? _overlayPort;
  bool _torchOn = false;

  static const int _recentContextMessageCount = 24;
  static const List<String> _allowedDocumentExtensions = ['md', 'pdf', 'txt'];
  static const int _maxImageBytes = 10 * 1024 * 1024;
  static const int _maxDocumentBytes = 15 * 1024 * 1024;
  static const int _maxExtractedDocumentChars = 120000;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation ?? Conversation();
    WidgetsBinding.instance.addObserver(this);
    _registerOverlayPort();
    _loadDocuments();
    // The overlay should not cover the main app while the user is inside it.
    // ignore: discarded_futures
    OverlayControllerService.instance.hide();
    // ignore: discarded_futures
    // VoiceService.instance.syncContinuousState();

    // Aggressive post-frame delay to ensure the overlay bubble closes when opening the app
    Future.delayed(const Duration(milliseconds: 400), () {
      OverlayControllerService.instance.hide();
    });
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent passes a different conversation, swap to it.
    if (widget.conversation != null &&
        widget.conversation!.id != _conversation.id) {
      setState(() {
        _conversation = widget.conversation!;
        _pendingImage = null;
        _pendingImageName = null;
        _pendingImageSummary = null;
        _pendingDocument = null;
        _pendingDocumentText = null;
        _documents = const [];
      });
      _loadDocuments();
    }
  }

  @override
  void dispose() {
    _overlayPort?.close();
    IsolateNameServer.removePortNameMapping(kMainPortName);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      OverlayControllerService.instance.hide();
      // ignore: discarded_futures
      // VoiceService.instance.syncContinuousState();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // ignore: discarded_futures
      OverlayControllerService.instance.showIfEnabled();
      // ignore: discarded_futures
      // VoiceService.instance.syncContinuousState();
    }
  }

  void _registerOverlayPort() {
    IsolateNameServer.removePortNameMapping(kMainPortName);
    _overlayPort = ReceivePort();
    IsolateNameServer.registerPortWithName(
      _overlayPort!.sendPort,
      kMainPortName,
    );
    _overlayPort!.listen(_onOverlayEvent);
  }

  Future<void> _onOverlayEvent(dynamic event) async {
    if (event is! Map) return;
    final type = event['type'] as String?;
    if (type == 'overlay_deactivated') {
      await OverlayControllerService.instance.markDisabledFromOverlay();
      if (!mounted) return;
      setState(() {});
      _showSnack('悬浮窗已关闭。');
      return;
    }
    if (type == 'open_app') {
      await DeviceActionsService.instance.openApp();
      return;
    }
    if (type == 'toggle_torch') {
      _torchOn = !_torchOn;
      final result = await DeviceActionsService.instance.setTorch(_torchOn);
      if (!result.ok) _torchOn = !_torchOn;
      return;
    }
    if (type == 'manual_voice_listen') {
      // ignore: discarded_futures
      VoiceService.instance.triggerManualVoiceCapture();
      return;
    }
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
      if (bytes.length > _maxImageBytes) {
        _showFileTooLarge(
          'Images can be up to ${_formatBytes(_maxImageBytes)}.',
        );
        return;
      }
      await _attachImageFile(name: picked.name, bytes: bytes);
    } catch (e, stack) {
      debugPrint('🐾 CHAT: image pick failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法打开图片选择器。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickAndIndexDocument() async {
    if (_indexing) return;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedDocumentExtensions,
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (!mounted) return;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("无法读取该文件。"),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      final ext = file.extension?.toLowerCase() ?? '';
      if (_isDocumentExtension(ext)) {
        if (bytes.length > _maxDocumentBytes) {
          _showFileTooLarge(
            'Documents can be up to ${_formatBytes(_maxDocumentBytes)}.',
          );
          return;
        }
        await _indexDocumentFile(name: file.name, extension: ext, bytes: bytes);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('支持的文档：md、pdf、txt。'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e, stack) {
      debugPrint('🐾 CHAT: file pick failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("无法打开文件选择器。"),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  bool _isDocumentExtension(String ext) =>
      ext == 'md' || ext == 'pdf' || ext == 'txt';

  void _showFileTooLarge(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb.truncateToDouble() == mb ? 0 : 1)} MB';
  }

  Future<void> _attachImageFile({
    required String name,
    required Uint8List bytes,
  }) async {
    await _deletePendingDocumentIfAny();
    setState(() {
      _pendingImage = bytes;
      _pendingImageName = name;
      _pendingImageSummary = null;
      _pendingDocument = null;
      _pendingDocumentText = null;
    });
    // ignore: discarded_futures
    _preparePendingImageSummary(bytes, name);
  }

  Future<void> _clearAttachment() async {
    final doc = _pendingDocument;
    setState(() {
      _pendingImage = null;
      _pendingImageName = null;
      _pendingImageSummary = null;
      _preparingImageSummary = false;
      _pendingDocument = null;
      _pendingDocumentText = null;
    });
    if (doc != null) {
      try {
        await RagService.instance.deleteDocument(doc);
        await _loadDocuments();
      } catch (e, stack) {
        debugPrint('🐾 CHAT: pending doc cleanup failed: $e\n$stack');
      }
    }
  }

  Future<void> _deletePendingDocumentIfAny() async {
    final doc = _pendingDocument;
    if (doc == null) return;
    setState(() {
      _pendingDocument = null;
      _pendingDocumentText = null;
    });
    try {
      await RagService.instance.deleteDocument(doc);
      await _loadDocuments();
    } catch (e, stack) {
      debugPrint('🐾 CHAT: pending doc cleanup failed: $e\n$stack');
    }
  }

  Future<void> _preparePendingImageSummary(
    Uint8List imageBytes,
    String imageName,
  ) async {
    if (GemmaService.instance.state.value != GemmaState.ready) return;
    setState(() {
      _preparingImageSummary = true;
      _thinkingStatus = StatusWords.random();
    });
    try {
      final summary = await GemmaService.instance.generate(
        'Extract any visible text from this image, then summarize the image. '
        'Return concise notes for future chat context.',
        imageBytes: imageBytes,
        userName: PrefsService.instance.current.name,
      );
      if (!mounted || _pendingImage != imageBytes) return;
      setState(() {
        _pendingImageSummary = summary.trim().isEmpty
            ? 'Image attached: $imageName.'
            : summary.trim();
      });
    } catch (e, stack) {
      debugPrint('🐾 CHAT: image summary failed: $e\n$stack');
      if (!mounted || _pendingImage != imageBytes) return;
      setState(() => _pendingImageSummary = 'Image attached: $imageName.');
      await _recoverModelAfterBackgroundFailure();
    } finally {
      if (mounted && _pendingImage == imageBytes) {
        setState(() => _preparingImageSummary = false);
      }
    }
  }

  Future<void> _recoverModelAfterBackgroundFailure() async {
    try {
      if (GemmaService.instance.state.value == GemmaState.error) {
        await GemmaService.instance.init();
      }
      if (GemmaService.instance.state.value == GemmaState.installed) {
        await GemmaService.instance.ensureInstalled();
        await GemmaService.instance.ensureLoaded();
      }
    } catch (e, stack) {
      debugPrint('🐾 CHAT: model recovery failed: $e\n$stack');
    }
  }

  /// Routes a dynamic-UI button command through the existing send path.
  void _handleComponentCommand(String command) {
    if (command.trim().isEmpty) return;
    _handleSend(command); // existing send path; self-guards on _busy
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Build the prompt sent to Gemma, including conversation history.
  String _buildPromptFromHistory(String newUserText) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You may render a rich UI component instead of plain text ONLY when the '
      'data is clearly structured. To do so, output a fenced block:\n'
      '```pcui\n{"type":"card","title":"...","body":"..."}\n```\n'
      'Supported types: card {title,body}; list {items:[{title,subtitle}]}; '
      'key_value {title,rows:[{label,value}]}; buttons {buttons:[{label,command}]}. '
      'Prefer plain text for normal answers. Emit at most one component.',
    );
    buffer.writeln();
    if (_hasPriorUploadMemory()) {
      buffer.writeln(
        '[Memory rule] Earlier image/document summaries below are available '
        'chat memory. If the user asks about a prior upload, answer from that '
        'memory and prior assistant replies instead of asking them to upload '
        'again. Ask for reupload only when no relevant memory exists.',
      );
      buffer.writeln();
    }
    final summary = _conversation.contextSummary;
    if (summary != null && summary.trim().isNotEmpty) {
      buffer.writeln('[Earlier conversation summary]');
      buffer.writeln(summary.trim());
      buffer.writeln();
    }
    for (final msg in _recentMessagesForPrompt(excludeLastUser: true)) {
      if (msg.isUser) {
        buffer.writeln('User: ${_messageTextForPrompt(msg)}');
      } else if (msg.isAssistant) {
        buffer.writeln('Assistant: ${_messageTextForPrompt(msg)}');
      }
    }
    buffer.write('User: $newUserText');
    return buffer.toString();
  }

  bool _hasPriorUploadMemory() =>
      _conversation.messages.any((m) => m.hasDoc || m.hasImageSummary) ||
      (_conversation.contextSummary?.contains(
            'Files/images already discussed',
          ) ??
          false);

  List<Message> _recentMessagesForPrompt({bool excludeLastUser = false}) {
    final start = _conversation.messages.length - _recentContextMessageCount;
    final recent = _conversation.messages
        .skip(start < 0 ? 0 : start)
        .where((m) => m.text.isNotEmpty || m.hasDoc || m.hasImageSummary)
        .toList();
    if (excludeLastUser && recent.isNotEmpty && recent.last.isUser) {
      recent.removeLast();
    }
    return recent;
  }

  String _messageTextForPrompt(Message msg) {
    final parts = <String>[];
    if (msg.text.trim().isNotEmpty) parts.add(msg.text.trim());
    if (msg.hasDoc) parts.add('[Attached document: ${msg.attachedDocName}]');
    if (msg.hasImageSummary) {
      final name = msg.imageName?.trim().isNotEmpty == true
          ? msg.imageName!.trim()
          : 'uploaded image';
      parts.add('[Prior image: $name]\n${msg.imageSummary!.trim()}');
    } else if (msg.hasImage) {
      final name = msg.imageName?.trim().isNotEmpty == true
          ? msg.imageName!.trim()
          : 'uploaded image';
      parts.add('[Attached image: $name]');
    }
    return parts.join('\n');
  }

  void _compactForContextIfNeeded() {
    final compactThrough =
        _conversation.messages.length - _recentContextMessageCount;
    if (compactThrough <= _conversation.contextSummaryMessageCount) return;

    final newlyOlder = _conversation.messages
        .skip(_conversation.contextSummaryMessageCount)
        .take(compactThrough - _conversation.contextSummaryMessageCount)
        .toList();
    if (newlyOlder.isEmpty) return;

    final userFacts = <String>[];
    final attachments = <String>[];
    final openIntents = <String>[];
    final condensedTurns = <String>[];

    final existing = _conversation.contextSummary;
    for (final msg in newlyOlder) {
      final who = msg.isUser
          ? 'User'
          : msg.isAssistant
          ? 'Claw'
          : 'System';
      final text = _messageTextForPrompt(msg);
      if (text.trim().isEmpty) continue;

      final compactText = _shorten(text, 420);
      condensedTurns.add('- $who: $compactText');

      if (msg.hasDoc) {
        attachments.add('Document available: ${msg.attachedDocName}.');
      }
      if (msg.hasImageSummary) {
        final name = msg.imageName?.trim().isNotEmpty == true
            ? msg.imageName!.trim()
            : 'uploaded image';
        attachments.add(
          'Image available: $name. ${_shorten(msg.imageSummary!.trim(), 240)}',
        );
      }
      if (msg.isUser) {
        final lower = msg.text.toLowerCase();
        if (lower.contains('i am ') ||
            lower.contains("i'm ") ||
            lower.contains('my name') ||
            lower.contains('i built') ||
            lower.contains('i prefer') ||
            lower.contains('remember')) {
          userFacts.add(_shorten(msg.text.trim(), 240));
        }
        if (lower.contains('fix') ||
            lower.contains('todo') ||
            lower.contains('issue') ||
            lower.contains('bug') ||
            lower.contains('need to') ||
            lower.contains('should')) {
          openIntents.add(_shorten(msg.text.trim(), 240));
        }
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('Running conversation memory for Claw.');
    final existingText = existing?.trim();
    if (existingText != null && existingText.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Previous memory:');
      buffer.writeln(existingText);
    }
    if (userFacts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('User facts/preferences:');
      for (final fact in _dedupe(userFacts).take(8)) {
        buffer.writeln('- $fact');
      }
    }
    if (attachments.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Files/images already discussed:');
      for (final attachment in _dedupe(attachments).take(10)) {
        buffer.writeln('- $attachment');
      }
    }
    if (openIntents.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Likely active goals or unresolved items:');
      for (final intent in _dedupe(openIntents).take(8)) {
        buffer.writeln('- $intent');
      }
    }
    if (condensedTurns.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Condensed older turns:');
      for (final turn in condensedTurns.take(16)) {
        buffer.writeln(turn);
      }
    }

    _conversation.contextSummary = _shorten(buffer.toString().trim(), 5000);
    _conversation.contextSummaryMessageCount = compactThrough;

    for (var i = 0; i < compactThrough; i++) {
      final msg = _conversation.messages[i];
      if (msg.hasImage) {
        _conversation.messages[i] = msg.copyWith(clearImage: true);
      }
    }
    debugPrint('🐾 CHAT: compacted context through $compactThrough messages');
  }

  String _shorten(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars).trimRight()}...';
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final normalized = value.toLowerCase().trim();
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      result.add(value);
    }
    return result;
  }

  String _imageMemoryFromAssistant({
    required String? imageName,
    required String assistantText,
    String? existingSummary,
  }) {
    final label = imageName?.trim().isNotEmpty == true
        ? imageName!.trim()
        : 'uploaded image';
    final existing = existingSummary?.trim();
    final answer = assistantText.trim();
    if (answer.isEmpty || answer == '__CLAW_ERROR__') {
      return existing?.isNotEmpty == true
          ? existing!
          : 'Image attached: $label.';
    }
    final described =
        'Assistant previously described $label as: '
        '${_shorten(answer, 1000)}';
    if (existing == null ||
        existing.isEmpty ||
        existing.startsWith('Image attached:')) {
      return described;
    }
    if (existing.contains('Assistant previously described')) return existing;
    return '${_shorten(existing, 700)}\n$described';
  }

  String _withContinuationHintIfNeeded(String text) {
    final trimmed = text.trimRight();
    if (trimmed.length < 5500) return text;
    const completeEndings = ['.', '!', '?', ')', ']', '`'];
    if (completeEndings.any(trimmed.endsWith)) return text;
    return '$trimmed\n\n我可能触达了回复长度上限。发送「继续」我会接着往下说。';
  }

  bool _looksLikeDocumentQuery(String text) {
    final lower = text.toLowerCase();
    return lower.contains('summari') ||
        lower.contains('summary') ||
        lower.contains('tldr') ||
        lower.contains('tl;dr') ||
        lower.contains('explain') ||
        lower.contains('describe') ||
        lower.contains('what is this') ||
        lower.contains("what's this") ||
        lower.contains('overview') ||
        lower.contains('key point') ||
        lower.contains('main idea') ||
        lower.contains('document') ||
        lower.contains('doc') ||
        lower.contains('file') ||
        lower.contains('pdf');
  }

  bool _looksLikeWebSearchQuery(String text) {
    final lower = text.toLowerCase();
    return lower.contains('search web') ||
        lower.contains('web search') ||
        lower.contains('look up') ||
        lower.contains('google ') ||
        lower.contains('latest ') ||
        lower.contains('current ');
  }

  String _webSearchQuery(String text) {
    var query = text.trim();
    for (final prefix in [
      'search web for',
      'search web',
      'web search for',
      'web search',
      'look up',
      'google',
    ]) {
      if (query.toLowerCase().startsWith(prefix)) {
        query = query.substring(prefix.length).trim();
        break;
      }
    }
    return query;
  }

  String _prependDocumentTextContext({
    required String prompt,
    required Document doc,
    required String text,
  }) {
    final context = StringBuffer()
      ..writeln('Use this attached document to answer the user.')
      ..writeln('Document: ${doc.name}')
      ..writeln('---')
      ..writeln(_shorten(text.trim(), 18000))
      ..writeln('---');
    return '${context.toString()}\n$prompt';
  }

  String _prependRetrievedContext({
    required String prompt,
    required List<RetrievedChunk> hits,
  }) {
    final context = StringBuffer();
    context.writeln('Use the following document excerpts to answer:');
    for (final h in hits) {
      context.writeln();
      context.writeln('[From ${h.docName}]');
      context.writeln(h.content);
    }
    context.writeln();
    context.writeln('---');
    return '${context.toString()}\n$prompt';
  }

  String _prependWebSearchContext({
    required String prompt,
    required String query,
    required String summary,
  }) {
    final context = StringBuffer()
      ..writeln(
        'Use these web search notes to answer. If they are thin, say so.',
      )
      ..writeln('Search query: $query')
      ..writeln('---')
      ..writeln(summary)
      ..writeln('---');
    return '${context.toString()}\n$prompt';
  }

  Future<void> _handleSend(String text) async {
    if (_busy || _preparingImageSummary) return;

    final imageBytes = _pendingImage;
    final imageName = _pendingImageName;
    final imageSummary =
        _pendingImageSummary ??
        (imageBytes != null
            ? 'Image attached: ${imageName ?? 'uploaded image'}.'
            : null);
    final doc = _pendingDocument;
    final docText = _pendingDocumentText;
    final userMsg = Message(
      role: MessageRole.user,
      text: text,
      imageBytes: imageBytes,
      imageName: imageName,
      imageSummary: imageSummary,
      attachedDocId: doc?.id,
      attachedDocName: doc?.name,
      attachedDocChunkCount: doc?.chunkCount,
    );
    final assistantMsg = Message(role: MessageRole.assistant, text: '');
    final userIndex = _conversation.messages.length;

    setState(() {
      _conversation.messages.add(userMsg);
      _conversation.messages.add(assistantMsg);
      _pendingImage = null;
      _pendingImageName = null;
      _pendingImageSummary = null;
      _pendingDocument = null;
      _pendingDocumentText = null;
      _busy = true;
      _thinkingStatus = StatusWords.random();
    });
    _scrollToBottom();

    final commandResponse = imageBytes == null && doc == null
        ? await ChatCommandService.instance.tryHandleWithGemma(text)
        : null;
    if (commandResponse != null) {
      if (mounted) {
        setState(() {
          final lastIdx = _conversation.messages.length - 1;
          _conversation.messages[lastIdx] = _conversation.messages[lastIdx]
              .copyWith(text: commandResponse);
          _busy = false;
          _lastFailedText = null;
          _lastFailedImage = null;
          _lastFailedImageName = null;
          _lastFailedImageSummary = null;
        });
      }
      if (_conversation.title == '新对话') {
        _conversation.title = _conversation.deriveTitleFromMessages();
      }
      try {
        await ConversationStore.instance.save(_conversation);
      } catch (e, stack) {
        debugPrint('🐾 CHAT: command save failed: $e\n$stack');
      }
      return;
    }

    _compactForContextIfNeeded();
    var prompt = _buildPromptFromHistory(_messageTextForPrompt(userMsg));

    if (imageBytes == null && doc == null && _looksLikeWebSearchQuery(text)) {
      final query = _webSearchQuery(text);
      final webSummary = await WebSearchService.instance.searchSummary(query);
      if (webSummary == null || webSummary.trim().isEmpty) {
        if (mounted) {
          setState(() {
            final lastIdx = _conversation.messages.length - 1;
            _conversation
                .messages[lastIdx] = _conversation.messages[lastIdx].copyWith(
              text:
                  '暂时无法使用网络搜索。你可能处于离线状态，或搜索服务没有返回可用结果。',
            );
            _busy = false;
          });
        }
        try {
          await ConversationStore.instance.save(_conversation);
        } catch (e, stack) {
          debugPrint('🐾 CHAT: web search failure save failed: $e\n$stack');
        }
        return;
      }
      prompt = _prependWebSearchContext(
        prompt: prompt,
        query: query,
        summary: webSummary,
      );
    }

    final retrievalQuery = text.trim().isEmpty && doc != null
        ? 'summarize the document ${doc.name}'
        : text;
    if (doc != null && docText != null && docText.trim().isNotEmpty) {
      prompt = _prependDocumentTextContext(
        prompt: prompt,
        doc: doc,
        text: docText,
      );
    } else if (_documents.isNotEmpty &&
        (doc != null || _looksLikeDocumentQuery(retrievalQuery))) {
      try {
        var hits = await RagService.instance.retrieve(
          query: retrievalQuery,
          conversationId: _conversation.id,
        );

        // Fallback for generic queries: "summarise", "explain", "tldr",
        // "what's this about" — these have no semantic overlap with the
        // doc's actual content, so similarity search misses. When the
        // query looks like one of these AND retrieval was empty (or only
        // brought back low-quality hits), fall back to filename-anchored
        // retrieval which grabs doc starts regardless of query terms.
        if (hits.length <= 1 && _looksLikeDocumentQuery(retrievalQuery)) {
          debugPrint(
            '🐾 CHAT: generic query, using filename-anchored fallback',
          );
          hits = await RagService.instance.getDocStarts(
            conversationId: _conversation.id,
          );
        }

        if (hits.isNotEmpty) {
          prompt = _prependRetrievedContext(prompt: prompt, hits: hits);
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
            _conversation.messages[lastIdx] = _conversation.messages[lastIdx]
                .copyWith(text: responseBuffer.toString());
          });
          _scrollToBottom();
        },
      );
      if (mounted) {
        setState(() {
          final lastIdx = _conversation.messages.length - 1;
          final current = _conversation.messages[lastIdx];
          _conversation.messages[lastIdx] = current.copyWith(
            text: _withContinuationHintIfNeeded(current.text),
          );
        });
      }
    } catch (e, stack) {
      debugPrint('🐾 CHAT: generate failed: $e\n$stack');
      if (mounted) {
        setState(() {
          // Remember what failed so the Retry button can re-run it.
          _lastFailedText = text;
          _lastFailedImage = imageBytes;
          _lastFailedImageName = imageName;
          _lastFailedImageSummary = imageSummary;
          final lastIdx = _conversation.messages.length - 1;
          // Tag the assistant message with a sentinel that the bubble
          // renderer recognises and replaces with a Retry UI.
          _conversation.messages[lastIdx] = _conversation.messages[lastIdx]
              .copyWith(text: '__CLAW_ERROR__');
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
            _lastFailedImageName = null;
            _lastFailedImageSummary = null;
          }
          if (userIndex < _conversation.messages.length &&
              _conversation.messages[userIndex].hasImage) {
            final userImageMsg = _conversation.messages[userIndex];
            _conversation.messages[userIndex] = userImageMsg.copyWith(
              imageSummary: _imageMemoryFromAssistant(
                imageName: userImageMsg.imageName,
                assistantText: _conversation.messages.last.text,
                existingSummary: userImageMsg.imageSummary,
              ),
            );
          }
        });
      }

      // Auto-title if this is the first user message in a brand-new chat.
      if (_conversation.title == 'New chat' || _conversation.title == '新建聊天') {
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
              content: Text('无法保存此会话。'),
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
      final docs = await DocumentStore.instance.loadForConversation(
        _conversation.id,
      );
      if (!mounted) return;
      setState(() => _documents = docs);
    } catch (e, stack) {
      debugPrint('🐾 CHAT: _loadDocuments failed: $e\n$stack');
      // Soft-fail: empty list, chat keeps working.
    }
  }

  /// Read a selected text/PDF document, index it, and keep it as the pending
  /// attachment for the next send. The original bytes are discarded after
  /// extraction.
  Future<void> _indexDocumentFile({
    required String name,
    required String extension,
    required Uint8List bytes,
  }) async {
    if (GemmaService.instance.embedderState.value != EmbedderState.installed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("爪爪还在准备中。稍等…"),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Extract text based on file type. PDF -> Syncfusion. txt/md -> UTF-8.
    String text;
    try {
      if (extension == 'pdf') {
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
          content: Text("爪爪读不了这个文件。换一个试试？"),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这个文件看起来是空的。'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    if (text.length > _maxExtractedDocumentChars) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '文档提取后过大。请控制在 '
            '${_maxExtractedDocumentChars ~/ 1000}k characters.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _indexing = true;
      _indexingDocumentName = name;
      _indexingStatus = StatusWords.random();
    });

    try {
      await _deletePendingDocumentIfAny();
      // Persist the conversation FIRST if it has no messages yet, so
      // the document's conversationId points at something that will
      // exist when the user later reopens the chat.
      if (_conversation.messages.isEmpty && (_conversation.title == 'New chat' || _conversation.title == '新建聊天')) {
        _conversation.title = name;
        await ConversationStore.instance.save(_conversation);
      }

      final doc = await RagService.instance.indexDocument(
        text: text,
        name: name,
        conversationId: _conversation.id,
      );

      await _loadDocuments();
      if (!mounted) return;

      setState(() {
        _pendingImage = null;
        _pendingImageName = null;
        _pendingImageSummary = null;
        _preparingImageSummary = false;
        _pendingDocument = doc;
        _pendingDocumentText = text;
      });

      // The pending document chip in the composer is the completion signal.
    } catch (e, stack) {
      debugPrint('🐾 CHAT: indexDocument failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('爪爪读不了这个文件，换一个试试？'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _indexing = false;
          _indexingDocumentName = null;
        });
      }
    }
  }

  /// Open a bottom sheet showing the indexed document chunks. The original
  /// bytes are not kept around; preview is rebuilt from the vector store text.
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
    final imageName = _lastFailedImageName;
    final imageSummary = _lastFailedImageSummary;
    if (text == null) return;
    setState(() {
      // Drop the last two messages (the user msg + the failed assistant msg)
      // so _handleSend re-adds them cleanly.
      if (_conversation.messages.length >= 2) {
        _conversation.messages.removeLast();
        _conversation.messages.removeLast();
      }
      _pendingImage = image;
      _pendingImageName = imageName;
      _pendingImageSummary = imageSummary;
      _lastFailedText = null;
      _lastFailedImage = null;
      _lastFailedImageName = null;
      _lastFailedImageSummary = null;
    });
    await _handleSend(text);
  }

  Future<void> _regenerateLatestAssistant() async {
    if (_busy || _conversation.messages.isEmpty) return;
    final assistantIndex = _conversation.messages.length - 1;
    final assistant = _conversation.messages[assistantIndex];
    if (!assistant.isAssistant) return;

    Message? userMsg;
    int? userIndex;
    for (var i = assistantIndex - 1; i >= 0; i--) {
      final msg = _conversation.messages[i];
      if (msg.isUser) {
        userMsg = msg;
        userIndex = i;
        break;
      }
    }
    if (userMsg == null) return;

    setState(() {
      _conversation.messages[assistantIndex] = assistant.copyWith(text: '');
      _busy = true;
      _thinkingStatus = StatusWords.random();
    });
    _scrollToBottom();

    var prompt = _buildPromptFromHistory(_messageTextForPrompt(userMsg));
    final retrievalQuery = userMsg.text.trim().isEmpty && userMsg.hasDoc
        ? 'summarize the document ${userMsg.attachedDocName}'
        : userMsg.text;
    if (_documents.isNotEmpty && _looksLikeDocumentQuery(retrievalQuery)) {
      try {
        var hits = await RagService.instance.retrieve(
          query: retrievalQuery,
          conversationId: _conversation.id,
        );
        if (hits.length <= 1 && _looksLikeDocumentQuery(retrievalQuery)) {
          hits = await RagService.instance.getDocStarts(
            conversationId: _conversation.id,
          );
        }
        if (hits.isNotEmpty) {
          prompt = _prependRetrievedContext(prompt: prompt, hits: hits);
        }
      } catch (e, stack) {
        debugPrint('🐾 CHAT: regenerate retrieval failed: $e\n$stack');
      }
    }

    try {
      final responseBuffer = StringBuffer();
      await GemmaService.instance.generate(
        prompt,
        imageBytes: userMsg.imageBytes,
        userName: PrefsService.instance.current.name,
        onToken: (chunk) {
          responseBuffer.write(chunk);
          if (!mounted) return;
          setState(() {
            _conversation.messages[assistantIndex] = _conversation
                .messages[assistantIndex]
                .copyWith(text: responseBuffer.toString());
          });
          _scrollToBottom();
        },
      );
      if (mounted) {
        setState(() {
          final current = _conversation.messages[assistantIndex];
          _conversation.messages[assistantIndex] = current.copyWith(
            text: _withContinuationHintIfNeeded(current.text),
          );
        });
      }
    } catch (e, stack) {
      debugPrint('🐾 CHAT: regenerate failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _lastFailedText = userMsg!.text;
        _lastFailedImage = userMsg.imageBytes;
        _lastFailedImageName = userMsg.imageName;
        _lastFailedImageSummary = userMsg.imageSummary;
        _conversation.messages[assistantIndex] = _conversation
            .messages[assistantIndex]
            .copyWith(text: '__CLAW_ERROR__');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (_conversation.messages[assistantIndex].text != '__CLAW_ERROR__' &&
              _conversation.messages[assistantIndex].text.isNotEmpty) {
            _lastFailedText = null;
            _lastFailedImage = null;
            _lastFailedImageName = null;
            _lastFailedImageSummary = null;
          }
          if (userIndex != null && _conversation.messages[userIndex].hasImage) {
            final userImageMsg = _conversation.messages[userIndex];
            _conversation.messages[userIndex] = userImageMsg.copyWith(
              imageSummary: _imageMemoryFromAssistant(
                imageName: userImageMsg.imageName,
                assistantText: _conversation.messages[assistantIndex].text,
                existingSummary: userImageMsg.imageSummary,
              ),
            );
          }
        });
      }
      try {
        await ConversationStore.instance.save(_conversation);
      } catch (e, stack) {
        debugPrint('🐾 CHAT: regenerate save failed: $e\n$stack');
      }
    }
  }

  Future<void> _openConversationList() async {
    final picked = await Navigator.of(context).push<Conversation?>(
      MaterialPageRoute(
        builder: (_) =>
            ConversationListScreen(currentConversationId: _conversation.id),
      ),
    );
    if (picked == null || !mounted) return;
    // Special sentinel: empty id = "start new chat"
    if (picked.id == 'NEW') {
      setState(() {
        _conversation = Conversation();
        _documents = const [];
        _pendingDocument = null;
        _pendingDocumentText = null;
      });
      _loadDocuments();
    } else {
      setState(() {
        _conversation = picked;
        _documents = const [];
        _pendingDocument = null;
        _pendingDocumentText = null;
      });
      _loadDocuments();
    }
  }

  Future<void> _setOverlayEnabled(bool enabled) async {
    final applied = await OverlayControllerService.instance.setEnabled(enabled);
    if (!mounted) return;
    setState(() {});
    if (!applied && enabled) {
      _showSnack('需要「显示在其他应用上层」权限。');
    }
  }

  Future<void> _importSkillBundle() async {
    try {
      final result = await MarketplaceService.instance.importFromFile();
      if (!mounted) return;
      if (result == null) return; // cancelled
      final msg = StringBuffer(
        '已添加 ${result.skillsAdded} 个技能',
      );
      if (result.workflowsAdded > 0) {
        msg.write('，${result.workflowsAdded} 个工作流');
      }
      if (result.warnings.isNotEmpty) {
        msg.write('（${result.warnings.length} 条警告）');
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg.toString())));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不是有效的 .pcskill 文件')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法导入该文件。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // endDrawer: const _SettingsDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openConversationList,
          tooltip: '会话',
        ),
        title: Text(_conversation.title, overflow: TextOverflow.ellipsis),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.settings),
          //   onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          //   tooltip: '爪爪设置',
          // ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear') {
                setState(() {
                  _conversation = Conversation();
                  _documents = const [];
                  _pendingDocument = null;
                  _pendingDocumentText = null;
                });
                _loadDocuments();
              } else if (value == 'skills') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SkillsScreen()),
                );
              } else if (value == 'workflows') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkflowsScreen(),
                  ),
                );
              } else if (value == 'import_skill') {
                await _importSkillBundle();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('新建聊天')),
              PopupMenuItem(value: 'skills', child: Text('技能')),
              PopupMenuItem(value: 'workflows', child: Text('工作流')),
              PopupMenuItem(value: 'import_skill', child: Text('导入技能…')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _OverlayPreferenceCard(
            enabled: PrefsService.instance.current.overlayEnabled,
            onChanged: _setOverlayEnabled,
          ),
          ValueListenableBuilder<GemmaState>(
            valueListenable: GemmaService.instance.state,
            builder: (context, state, _) {
              if (state == GemmaState.ready || state == GemmaState.generating) {
                return const SizedBox.shrink();
              }
              return Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: DecoratedBox(
                    decoration: PocketClawTheme.panel(
                      color: PocketClawTheme.bg2,
                      border: PocketClawTheme.warning,
                    ),
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
                              onPressed: _retrySetup,
                              child: const Text('重试'),
                            ),
                          if (state == GemmaState.notInstalled)
                            TextButton(
                              onPressed: _retrySetup,
                              child: const Text('开始设置'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<EmbedderState>(
            valueListenable: GemmaService.instance.embedderState,
            builder: (context, state, _) {
              if (state == EmbedderState.installed) {
                return const SizedBox.shrink();
              }
              return Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: DecoratedBox(
                    decoration: PocketClawTheme.panel(
                      color: PocketClawTheme.bg2,
                      border: PocketClawTheme.purple,
                    ),
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
                              _bannerForEmbedderState(state),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (state == EmbedderState.error ||
                              state == EmbedderState.notInstalled)
                            TextButton(
                              onPressed: _retrySetup,
                              child: const Text('重试'),
                            ),
                        ],
                      ),
                    ),
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
                      final isLastFailed =
                          i == _conversation.messages.length - 1 &&
                          m.text == '__CLAW_ERROR__';
                      return MessageBubble(
                        message: m,
                        onCommand: _handleComponentCommand,
                        loadingText: m.isAssistant && m.text.isEmpty && _busy
                            ? _thinkingStatus
                            : null,
                        onRetry: isLastFailed
                            ? _retry
                            : i == _conversation.messages.length - 1 &&
                                  m.isAssistant &&
                                  m.text.isNotEmpty
                            ? _regenerateLatestAssistant
                            : null,
                        onDocTap: m.hasDoc
                            ? () => _previewDocument(m.attachedDocId!)
                            : null,
                      );
                    },
                  ),
          ),
          if (_indexing)
            _IndexingDocumentBanner(
              name: _indexingDocumentName ?? 'document',
              status: _indexingStatus,
            ),
          ValueListenableBuilder<GemmaState>(
            valueListenable: GemmaService.instance.state,
            builder: (context, state, _) {
              final modelReady =
                  state == GemmaState.ready || state == GemmaState.generating;
              return ValueListenableBuilder<EmbedderState>(
                valueListenable: GemmaService.instance.embedderState,
                builder: (context, embedderState, _) {
                  final embedderReady =
                      embedderState == EmbedderState.installed;
                  return ChatInput(
                    onSend: _handleSend,
                    enabled: !_busy && modelReady && embedderReady,
                    attachedImage: _pendingImage,
                    attachedImageName: _pendingImageName,
                    attachedDocumentName: _pendingDocument?.name,
                    attachedDocumentSectionCount: _pendingDocument?.chunkCount,
                    preparingAttachment: _preparingImageSummary || _indexing,
                    disabledHint: _busy
                        ? '$_thinkingStatus...'
                        : _indexing
                        ? '$_indexingStatus...'
                        : _preparingImageSummary
                        ? '$_thinkingStatus...'
                        : null,
                    onAttachImage: _pickImage,
                    onAttachDocument: _pickAndIndexDocument,
                    onClearAttachment: _clearAttachment,
                  );
                },
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
        return '需要完成设置后才能聊天。';
      case GemmaState.installing:
        return '$_thinkingStatus...';
      case GemmaState.installed:
        return '$_thinkingStatus...';
      case GemmaState.loading:
        return '$_thinkingStatus...';
      case GemmaState.error:
        return '无法启动爪爪。请重试。';
      case GemmaState.ready:
      case GemmaState.generating:
        return '';
    }
  }

  String _bannerForEmbedderState(EmbedderState state) {
    switch (state) {
      case EmbedderState.notInstalled:
        return '需要完成文档理解设置后才能聊天。';
      case EmbedderState.installing:
        return '$_indexingStatus...';
      case EmbedderState.error:
        return '文档理解设置失败，请重试以完成设置。';
      case EmbedderState.installed:
        return '';
    }
  }

  Future<void> _retrySetup() async {
    try {
      if (GemmaService.instance.state.value == GemmaState.error) {
        await GemmaService.instance.init();
      }
      if (GemmaService.instance.state.value == GemmaState.notInstalled ||
          GemmaService.instance.state.value == GemmaState.error) {
        await GemmaService.instance.ensureInstalled();
      }
      if (GemmaService.instance.state.value == GemmaState.installed) {
        await GemmaService.instance.ensureLoaded();
      }
      if (GemmaService.instance.embedderState.value !=
          EmbedderState.installed) {
        await GemmaService.instance.installEmbedder();
      }
    } catch (e, stack) {
      debugPrint('🐾 CHAT: retry setup failed: $e\n$stack');
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
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/images/pocketclaw_icon.png',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text('随便问爪爪', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '附加截图、粘贴文本，或直接输入。全部在设备本地运行。',
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

class _OverlayPreferenceCard extends StatelessWidget {
  const _OverlayPreferenceCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: DecoratedBox(
        decoration: PocketClawTheme.panel(
          color: PocketClawTheme.bg2,
          border: enabled ? PocketClawTheme.mint : PocketClawTheme.cyan,
          shadow: false,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('悬浮窗', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'PocketClaw 在后台时生效。'
                          : '已关闭。开启后可使用悬浮助手。',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _IndexingDocumentBanner extends StatelessWidget {
  const _IndexingDocumentBanner({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DecoratedBox(
          decoration: PocketClawTheme.panel(
            color: PocketClawTheme.bg3,
            border: PocketClawTheme.mint,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$status $name...',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  final String _previewStatus = StatusWords.random();

  @override
  void initState() {
    super.initState();
    _chunksFuture = RagService.instance
        .getDocStarts(
          conversationId: widget.document.conversationId,
          perDocLimit: widget.document.chunkCount,
        )
        .then(
          (all) => all.where((c) => c.docName == widget.document.name).toList(),
        );
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
        decoration: const BoxDecoration(
          color: PocketClawTheme.bg2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(
            top: BorderSide(color: PocketClawTheme.cyan, width: 3),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: PocketClawTheme.cyan,
                  ),
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
                          '${widget.document.chunkCount} 个片段',
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text('$_previewStatus…'),
                          ],
                        ),
                      ),
                    );
                  }
                  final chunks = snap.data ?? const [];
                  if (chunks.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '无法加载文档内容。',
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

/*
class _SettingsDrawer extends StatefulWidget {
  const _SettingsDrawer();

  @override
  State<_SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<_SettingsDrawer> with WidgetsBindingObserver {
  bool _overlayGranted = false;
  bool _micGranted = false;
  bool _cameraGranted = false;
  bool _notificationGranted = false;

  final _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyController.text = PrefsService.instance.current.picovoiceAccessKey ?? '';
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    final status = await DeviceActionsService.instance.checkAppPermissions();
    if (mounted) {
      setState(() {
        _overlayGranted = overlay;
        _micGranted = status['mic'] ?? false;
        _cameraGranted = status['camera'] ?? false;
        _notificationGranted = status['notifications'] ?? false;
      });
    }
  }

  Future<void> _grantOverlay() async {
    await OverlayControllerService.instance.ensurePermission();
    await _checkPermissions();
  }

  Future<void> _grantSystem() async {
    await DeviceActionsService.instance.requestAppPermissions();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _checkPermissions();
  }

  Future<void> _saveKey(String val) async {
    final current = PrefsService.instance.current;
    await PrefsService.instance.update(
      current.copyWith(picovoiceAccessKey: val.trim().isEmpty ? null : val.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = PrefsService.instance.current;

    return Drawer(
      backgroundColor: PocketClawTheme.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '爪爪设置',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: PocketClawTheme.cyan,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
              const Divider(color: PocketClawTheme.cyan, thickness: 2, height: 24),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Text(
                      '系统权限',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: PocketClawTheme.purple,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PermissionItem(
                      icon: Icons.open_in_new,
                      title: '显示在其他应用上层',
                      granted: _overlayGranted,
                      onGrant: _grantOverlay,
                    ),
                    _PermissionItem(
                      icon: Icons.mic_none,
                      title: '麦克风',
                      granted: _micGranted,
                      onGrant: _grantSystem,
                    ),
                    _PermissionItem(
                      icon: Icons.camera_alt_outlined,
                      title: '相机与视觉',
                      granted: _cameraGranted,
                      onGrant: _grantSystem,
                    ),
                    _PermissionItem(
                      icon: Icons.notifications_none,
                      title: '通知',
                      granted: _notificationGranted,
                      onGrant: _grantSystem,
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: PocketClawTheme.panel(
                        color: PocketClawTheme.bg3,
                        border: PocketClawTheme.cyan,
                        radius: 8,
                        shadow: true,
                      ),
                      child: InkWell(
                        onTap: () => DeviceActionsService.instance.openAppSettings(),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.settings, size: 16, color: PocketClawTheme.cyan),
                              SizedBox(width: 8),
                              Text(
                                '在系统设置中管理',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: PocketClawTheme.cyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '根据 Android 安全规则，撤销权限需在系统设置中手动完成。点上方打开设置。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '语音控制',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: PocketClawTheme.purple,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SwitchSetting(
                      title: '「嘿 PC」唤醒词',
                      subtitle: '持续后台聆听。',
                      value: prefs.continuousListening,
                      onChanged: (val) async {
                        await PrefsService.instance.update(
                          prefs.copyWith(continuousListening: val),
                        );
                        setState(() {});
                      },
                    ),
                    _SwitchSetting(
                      title: '保持屏幕常亮',
                      subtitle: '聆听时获取唤醒锁。',
                      value: prefs.keepScreenAwake,
                      onChanged: (val) async {
                        await PrefsService.instance.update(
                          prefs.copyWith(keepScreenAwake: val),
                        );
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Picovoice Porcupine 密钥',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: PocketClawTheme.purple,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '可选。填写密钥以启用硬件级唤醒词解析；留空则使用本地持续语音识别作为回退。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keyController,
                      decoration: const InputDecoration(
                        hintText: 'Porcupine AccessKey…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: _saveKey,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.granted,
    required this.onGrant,
  });

  final IconData icon;
  final String title;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: PocketClawTheme.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: granted ? PocketClawTheme.mint : PocketClawTheme.cyan,
          width: 2,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: granted ? PocketClawTheme.mint : PocketClawTheme.cyan),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        trailing: TextButton(
          onPressed: granted ? null : onGrant,
          child: Text(
            granted ? 'ACTIVE' : 'GRANT',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: granted ? PocketClawTheme.mint : PocketClawTheme.cyan,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: PocketClawTheme.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PocketClawTheme.cyan, width: 2),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: PocketClawTheme.cyan,
        activeTrackColor: PocketClawTheme.bg3,
      ),
    );
  }
}
*/
