import 'package:uuid/uuid.dart';

import 'message.dart';

/// A persisted chat thread. Stored as JSON in Hive.
///
/// Title is auto-generated from the first user message. Messages list
/// is the full conversation in chronological order. updatedAt drives
/// the sort order in the conversation list (most-recent first).
class Conversation {
  Conversation({
    String? id,
    this.title = '新建聊天',
    List<Message>? messages,
    this.contextSummary,
    this.contextSummaryMessageCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<Message> messages;
  String? contextSummary;
  int contextSummaryMessageCount;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Derive a title from the first non-empty user message.
  /// 若还没有用户消息，则回退为「新建聊天」。
  /// Capped at 60 characters; newlines collapsed to spaces.
  String deriveTitleFromMessages() {
    final firstUser = messages.firstWhere(
      (m) => m.isUser && m.text.trim().isNotEmpty,
      orElse: () => Message(role: MessageRole.user, text: ''),
    );
    if (firstUser.text.trim().isEmpty) {
      // If only an image was sent, use a generic title.
      if (messages.any((m) => m.hasImage)) return '图片会话';
      return '新建聊天';
    }
    final cleaned = firstUser.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.length > 60 ? '${cleaned.substring(0, 60)}…' : cleaned;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'contextSummary': contextSummary,
    'contextSummaryMessageCount': contextSummaryMessageCount,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String?,
    title: json['title'] as String? ?? '新建聊天',
    messages: (json['messages'] as List? ?? [])
        .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
    contextSummary: json['contextSummary'] as String?,
    contextSummaryMessageCount: json['contextSummaryMessageCount'] as int? ?? 0,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}
