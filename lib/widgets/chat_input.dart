import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../core/pocketclaw_theme.dart';

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

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
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
                    tooltip: 'Attach image',
                    onPressed: widget.enabled && !widget.preparingAttachment
                        ? widget.onAttachImage
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _InputIconButton(
                    icon: Icons.description_outlined,
                    tooltip: 'Attach document',
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
                        hintText: widget.enabled
                            ? 'Ask Claw anything…'
                            : widget.disabledHint ?? 'Claw is thinking…',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
        tooltip: 'Send',
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
