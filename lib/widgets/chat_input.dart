import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/pocketclaw_theme.dart';
import '../services/device_actions_service.dart';

/// Bottom input bar: attachment thumbnail (if any), text field, send button.
///
/// Notifies parent via [onSend] when the user taps send. The parent is
/// responsible for clearing the attachment state after a send.
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.enabled,
    this.attachedImage,
    this.attachedImageName,
    this.attachedDocumentName,
    this.attachedDocumentSectionCount,
    this.preparingAttachment = false,
    this.disabledHint,
    required this.onAttachImage,
    required this.onAttachDocument,
    required this.onClearAttachment,
    this.autoListen = false,
  });

  final void Function(String text) onSend;
  final bool enabled;
  final Uint8List? attachedImage;
  final String? attachedImageName;
  final String? attachedDocumentName;
  final int? attachedDocumentSectionCount;
  final bool preparingAttachment;
  final String? disabledHint;
  final VoidCallback onAttachImage;
  final VoidCallback onAttachDocument;
  final VoidCallback onClearAttachment;
  final bool autoListen;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isPressed = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _pulseController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    _initSpeech();
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-trigger recording if passed from parent
    if (widget.autoListen == true && oldWidget.autoListen != true) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _speechEnabled && !_isListening) {
          _startListening();
        }
      });
    }
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speechToText.initialize(
        onError: (val) => debugPrint('🐾 VOICE: STT error: $val'),
        onStatus: (val) => debugPrint('🐾 语音：STT 状态：$val'),
      );
      if (mounted) {
        setState(() => _speechEnabled = available);
      }
    } catch (e) {
      debugPrint('🐾 VOICE: failed to init STT: $e');
    }
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) return;
    try {
      _focusNode.unfocus();
      setState(() {
        _isListening = true;
      });
      _pulseController.repeat(reverse: true);
      await _speechToText.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _controller.text = result.recognizedWords;
            });
          }
        },
      );
      // Self-healing: if the user already released the touch while we were starting, stop immediately!
      if (!_isPressed) {
        await _stopListening();
      }
    } catch (e) {
      debugPrint('🐾 VOICE: start listen failed: $e');
      if (mounted) {
        setState(() {
          _isListening = false;
        });
        _pulseController.stop();
        _pulseController.value = 0.0;
      }
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speechToText.stop();
    } catch (e) {
      debugPrint('🐾 VOICE: stop listen failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isListening = false;
        });
        _pulseController.stop();
        _pulseController.value = 0.0;
      }
    }
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _speechToText.stop();
    _pulseController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty &&
        widget.attachedImage == null &&
        widget.attachedDocumentName == null) {
      return;
    }
    if (!widget.enabled || widget.preparingAttachment) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: PocketClawTheme.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.attachedImage != null)
                _AttachmentChip(
                  imageBytes: widget.attachedImage!,
                  name: widget.attachedImageName ?? 'image',
                  busy: widget.preparingAttachment,
                  subtitle: widget.preparingAttachment
                      ? 'Preparing image context...'
                      : null,
                  onRemove: widget.onClearAttachment,
                ),
              if (widget.attachedDocumentName != null)
                _DocumentAttachmentChip(
                  name: widget.attachedDocumentName!,
                  sectionCount: widget.attachedDocumentSectionCount ?? 0,
                  onRemove: widget.onClearAttachment,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _InputIconButton(
                    icon: Icons.add_photo_alternate_outlined,
                    tooltip: '附加图片',
                    onPressed: widget.enabled && !widget.preparingAttachment
                        ? widget.onAttachImage
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _InputIconButton(
                    icon: Icons.description_outlined,
                    tooltip: '附加文档',
                    onPressed: widget.enabled && !widget.preparingAttachment
                        ? widget.onAttachDocument
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening... Speak now!'
                            : widget.enabled
                            ? '随便问爪爪…'
                            : widget.disabledHint ?? '爪爪在想…',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_controller.text.isEmpty || _isListening)
                    GestureDetector(
                      onTapDown: (_) async {
                        if (!widget.enabled) return;
                        _isPressed = true;
                        // 1. Dynamic mic permission check & request
                        final permissions = await DeviceActionsService.instance
                            .checkAppPermissions();
                        if (permissions['mic'] != true) {
                          await DeviceActionsService.instance
                              .requestAppPermissions();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 600),
                          );
                          final recheck = await DeviceActionsService.instance
                              .checkAppPermissions();
                          if (recheck['mic'] != true) {
                            _isPressed = false;
                            return; // User did not grant permission
                          }
                        }

                        // 2. Initialize speech if not already ready
                        if (!_speechEnabled) {
                          await _initSpeech();
                        }

                        if (_speechEnabled && _isPressed) {
                          await _startListening();
                        }
                      },
                      onTapUp: (_) async {
                        _isPressed = false;
                        if (!widget.enabled) return;
                        if (_isListening) {
                          await _stopListening();
                          // Wait briefly for last recognized chunk to settle in text field
                          await Future<void>.delayed(
                            const Duration(milliseconds: 400),
                          );
                          if (_controller.text.trim().isNotEmpty) {
                            _handleSend();
                          }
                        }
                      },
                      onTapCancel: () async {
                        _isPressed = false;
                        if (!widget.enabled) return;
                        if (_isListening) {
                          await _stopListening();
                        }
                      },
                      child: AnimatedScale(
                        scale: _isListening
                            ? (1.25 + (_pulseController.value * 0.08))
                            : 1.0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutBack,
                        child: DecoratedBox(
                          decoration: PocketClawTheme.panel(
                            color: _isListening
                                ? PocketClawTheme.purple
                                : PocketClawTheme.cyan,
                            border: PocketClawTheme.text,
                            shadow: !_isListening && widget.enabled,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening
                                  ? PocketClawTheme.text
                                  : PocketClawTheme.ink,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    _SendButton(
                      onPressed: widget.enabled && !widget.preparingAttachment
                          ? _handleSend
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputIconButton extends StatelessWidget {
  const _InputIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: PocketClawTheme.panel(
        color: PocketClawTheme.bg3,
        border: onPressed == null
            ? PocketClawTheme.muted
            : PocketClawTheme.cyan,
        shadow: onPressed != null,
      ),
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
        color: onPressed == null ? PocketClawTheme.muted : PocketClawTheme.text,
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: PocketClawTheme.panel(
        color: onPressed == null ? PocketClawTheme.bg3 : PocketClawTheme.cyan,
        border: PocketClawTheme.text,
        shadow: onPressed != null,
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_upward),
        tooltip: '发送',
        onPressed: onPressed,
        color: onPressed == null ? PocketClawTheme.muted : PocketClawTheme.ink,
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.imageBytes,
    required this.name,
    this.subtitle,
    this.busy = false,
    required this.onRemove,
  });

  final Uint8List imageBytes;
  final String name;
  final String? subtitle;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      padding: const EdgeInsets.all(6),
      decoration: PocketClawTheme.panel(
        color: PocketClawTheme.bg3,
        border: PocketClawTheme.purple,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              imageBytes,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (busy) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}

class _DocumentAttachmentChip extends StatelessWidget {
  const _DocumentAttachmentChip({
    required this.name,
    required this.sectionCount,
    required this.onRemove,
  });

  final String name;
  final int sectionCount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      padding: const EdgeInsets.all(8),
      decoration: PocketClawTheme.panel(
        color: PocketClawTheme.bg3,
        border: PocketClawTheme.purple,
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: PocketClawTheme.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sectionCount == 1
                      ? '1 section ready'
                      : '$sectionCount sections ready',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}
