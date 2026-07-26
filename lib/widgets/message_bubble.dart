import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../core/pocketclaw_theme.dart';
import '../models/message.dart';
import '../services/dynamic_ui/dynamic_ui_service.dart';
import '../services/dynamic_ui/component_spec.dart';
import 'dynamic_component_widget.dart';

/// Sentinel that 对话Screen writes into a message's text field when a
/// generation fails. The bubble renderer replaces it with a friendly
/// error UI + a 重试 button.
const String kErrorSentinel = '__CLAW_ERROR__';

/// Renders one message in the chat thread.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.on重试,
    this.onDocTap,
    this.loadingText,
    this.onCommand,
  });

  final Message message;
  final VoidCallback? on重试;

  /// Called when the doc-attachment card is tapped (to open preview).
  /// Null = card is non-interactive (e.g. inside the sender's bubble
  /// while doc is still indexing).
  final VoidCallback? onDocTap;
  final String? loadingText;

  /// Called when a dynamic UI button inside an assistant bubble is tapped.
  /// The command string is forwarded to the chat send path.
  final void Function(String command)? onCommand;

  static const _shareChannel = MethodChannel('pocketclaw/share');

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isError = message.text == kErrorSentinel;

    final bubbleColor = isUser
        ? PocketClawTheme.purple
        : isError
        ? const Color(0xFF3A1720)
        : PocketClawTheme.bg2;
    final textColor = isUser
        ? PocketClawTheme.text
        : isError
        ? PocketClawTheme.text
        : PocketClawTheme.text;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: PocketClawTheme.panel(
              color: bubbleColor,
              border: isUser
                  ? PocketClawTheme.cyan
                  : isError
                  ? PocketClawTheme.error
                  : PocketClawTheme.text,
              radius: 8,
              shadow: true,
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
                  if (on重试 != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: on重试,
                      icon: Icon(Icons.refresh, size: 16, color: textColor),
                      label: Text('重试', style: TextStyle(color: textColor)),
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
                      : _AssistantMessageContent(
                          text: message.text,
                          textColor: textColor,
                          onCommand: onCommand,
                        ),
                if (!isUser &&
                    !isError &&
                    message.text.isEmpty &&
                    loadingText != null)
                  _LoadingStatus(text: loadingText!, color: textColor),
              ],
            ),
          ),
          _MessageActions(
            isUser: isUser,
            copyText: _copyableText(message),
            on重试: on重试,
            on复制: (value) => _copy(context, value),
            on分享: (value) => _share(context, value),
          ),
        ],
      ),
    );
  }

  String _copyableText(Message message) {
    final parts = <String>[];
    if (message.hasDoc) {
      parts.add('[Attached 文档: ${message.attachedDocName}]');
    }
    if (message.hasImage) {
      parts.add('[Attached image: ${message.imageName ?? 'uploaded image'}]');
    } else if (message.hasImageSummary) {
      parts.add(
        '[Image summary: ${message.imageName ?? 'uploaded image'}]\n'
        '${message.imageSummary!.trim()}',
      );
    }
    if (message.text.trim().isNotEmpty && message.text != kErrorSentinel) {
      parts.add(message.text.trim());
    }
    return parts.join('\n\n');
  }

  Future<void> _copy(BuildContext context, String value) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _share(BuildContext context, String value) async {
    if (value.trim().isEmpty) return;
    try {
      await _shareChannel.invokeMethod<bool>('shareText', {'text': value});
    } on PlatformException catch (_) {
      if (!context.mounted) return;
      await _copy(context, value);
    }
  }
}

class _LoadingStatus extends StatelessWidget {
  const _LoadingStatus({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(width: 8),
        Text('$text...', style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.isUser,
    required this.copyText,
    required this.on复制,
    required this.on分享,
    this.on重试,
  });

  final bool isUser;
  final String copyText;
  final VoidCallback? on重试;
  final void Function(String) on复制;
  final void Function(String) on分享;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 0 : 16,
        right: isUser ? 16 : 0,
        bottom: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: Icons.copy_outlined,
            label: '复制',
            color: color,
            onPressed: copyText.trim().isEmpty ? null : () => on复制(copyText),
          ),
          _ActionButton(
            icon: Icons.ios_share_outlined,
            label: '分享',
            color: color,
            onPressed: copyText.trim().isEmpty ? null : () => on分享(copyText),
          ),
          if (on重试 != null)
            _ActionButton(
              icon: Icons.refresh,
              label: '再试一次',
              color: color,
              onPressed: on重试,
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      color: color,
      tooltip: label,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 36, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AssistantMessageContent extends StatelessWidget {
  const _AssistantMessageContent({
    required this.text,
    required this.textColor,
    this.onCommand,
  });

  final String text;
  final Color textColor;
  final void Function(String command)? onCommand;

  @override
  Widget build(BuildContext context) {
    final segments = _splitSegments(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final segment in segments) ...[
          if (segment.pcuiSpec != null)
            DynamicComponentWidget(spec: segment.pcuiSpec!, onCommand: onCommand)
          else if (segment.isCode)
            _复制ableCodeBlock(code: segment.text)
          else if (segment.text.trim().isNotEmpty)
            MarkdownBody(
              data: segment.text,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
              selectable: true,
            ),
          if (segment != segments.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// Splits text into ordered segments: pcui components, code blocks, and
  /// plain text. A ```pcui block that parses becomes a [pcuiSpec] segment;
  /// one that fails to parse falls through as a normal code segment.
  List<_ContentSegment> _splitSegments(String value) {
    final pattern = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
    final segments = <_ContentSegment>[];
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        segments.add(_ContentSegment(value.substring(cursor, match.start)));
      }
      final tag = (match.group(1) ?? '').trim().toLowerCase();
      final inner = match.group(2) ?? '';
      if (tag == 'pcui') {
        final spec = DynamicUiService.instance.parse(inner);
        if (spec != null) {
          segments.add(_ContentSegment('', pcuiSpec: spec));
        } else {
          segments.add(_ContentSegment(inner, isCode: true));
        }
      } else {
        segments.add(_ContentSegment(inner, isCode: true));
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      segments.add(_ContentSegment(value.substring(cursor)));
    }
    return segments.isEmpty ? [_ContentSegment(value)] : segments;
  }
}

class _ContentSegment {
  _ContentSegment(this.text, {this.isCode = false, this.pcuiSpec});

  final String text;
  final bool isCode;
  final ComponentSpec? pcuiSpec;
}

class _复制ableCodeBlock extends StatelessWidget {
  const _复制ableCodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: PocketClawTheme.panel(
        color: PocketClawTheme.bg,
        border: PocketClawTheme.mint,
        radius: 8,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 42, 12),
            child: SelectableText(
              code.trimRight(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: PocketClawTheme.text,
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: '复制代码',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code.trimRight()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('代码已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
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
    final bg = onPrimary ? PocketClawTheme.bg3 : PocketClawTheme.bg;
    final fg = PocketClawTheme.text;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
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
