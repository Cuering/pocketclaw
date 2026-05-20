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
    this.title = 'New chat',
    List<Message>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<Message> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Derive a title from the first non-empty user message.
  /// Falls back to 'New chat' if there are no user messages yet.
  /// Capped at 60 characters; newlines collapsed to spaces.
  String deriveTitleFromMessages() {
    final firstUser = messages.firstWhere(
      (m) => m.isUser && m.text.trim().isNotEmpty,
      orElse: () => Message(role: MessageRole.user, text: ''),
    );
    if (firstUser.text.trim().isEmpty) {
      // If only an image was sent, use a generic title.
      if (messages.any((m) => m.hasImage)) return 'Image chat';
      return 'New chat';
    }
    final cleaned = firstUser.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.length > 60 ? '${cleaned.substring(0, 60)}…' : cleaned;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String?,
    title: json['title'] as String? ?? 'New chat',
    messages: (json['messages'] as List? ?? [])
        .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}
