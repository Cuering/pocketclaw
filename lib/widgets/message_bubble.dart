import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/message.dart';

/// Sentinel that ChatScreen writes into a message's text field when a
/// generation fails. The bubble renderer replaces it with a friendly
/// error UI + a Retry button.
const String kErrorSentinel = '__CLAW_ERROR__';

/// Renders one message in the chat thread.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDocTap,
  });

  final Message message;
  final VoidCallback? onRetry;
  /// Called when the doc-attachment card is tapped (to open preview).
  /// Null = card is non-interactive (e.g. inside the sender's bubble
  /// while doc is still indexing).
  final VoidCallback? onDocTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final isError = message.text == kErrorSentinel;

    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest;
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : isError
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  message.imageBytes!,
                  fit: BoxFit.cover,
                  height: 180,
                ),
              ),
              if (message.text.isNotEmpty && !isError)
                const SizedBox(height: 8),
            ],
            if (message.hasDoc) ...[
              _DocAttachmentCard(
                docName: message.attachedDocName!,
                chunkCount: message.attachedDocChunkCount ?? 0,
                onTap: onDocTap,
                onPrimary: isUser,
              ),
              if (message.text.isNotEmpty && !isError)
                const SizedBox(height: 8),
            ],
            if (isError) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 18, color: textColor),
                  const SizedBox(width: 6),
                  Text(
                    "Claw couldn't finish that.",
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                ],
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh, size: 16, color: textColor),
                  label: Text('Retry', style: TextStyle(color: textColor)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ] else if (message.text.isNotEmpty)
              isUser
                  ? Text(
                      message.text,
                      style: TextStyle(color: textColor, fontSize: 15),
                    )
                  : MarkdownBody(
                      data: message.text,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                        ),
                        code: TextStyle(
                          backgroundColor: theme.colorScheme.surface,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      selectable: true,
                    ),
          ],
        ),
      ),
    );
  }
}

class _DocAttachmentCard extends StatelessWidget {
  const _DocAttachmentCard({
    required this.docName,
    required this.chunkCount,
    required this.onTap,
    required this.onPrimary,
  });

  final String docName;
  final int chunkCount;
  final VoidCallback? onTap;

  /// True when this card is rendered inside a primary-colored (user) bubble.
  /// We invert the card's own surface color to keep contrast.
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = onPrimary
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.12)
        : theme.colorScheme.primaryContainer;
    final fg = onPrimary
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onPrimaryContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 20, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      docName,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chunkCount > 0)
                      Text(
                        chunkCount == 1
                            ? '1 section indexed'
                            : '$chunkCount sections indexed',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.75),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

