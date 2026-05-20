import 'dart:convert';
import 'dart:typed_data';

/// Who sent the message in a conversation.
enum MessageRole { user, assistant, system }

/// A single message in a conversation thread.
///
/// Optionally carries an image attachment (PNG bytes). When an image is
/// attached, the text field is treated as the prompt/question about the
/// image; together they form one multimodal message to Gemma.
class Message {
  Message({
    required this.role,
    required this.text,
    this.imageBytes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final MessageRole role;
  final String text;
  final Uint8List? imageBytes;
  final DateTime timestamp;

  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  /// Convenience copy with a different text (used while streaming the
  /// assistant's response token by token).
  Message copyWith({String? text, Uint8List? imageBytes}) => Message(
    role: role,
    text: text ?? this.text,
    imageBytes: imageBytes ?? this.imageBytes,
    timestamp: timestamp,
  );

  // ── Serialization ─────────────────────────────────────────────────────
  //
  // We serialize via plain JSON-compatible Maps rather than Hive TypeAdapters
  // to avoid the build_runner codegen dependency. The Conversation store
  // writes the resulting Map as a JSON string into a Hive box.
  //
  // Image bytes go in as base64 strings. For a screenshot ~1 MB this
  // means ~1.3 MB in JSON; fine for a phone, but B3 can switch to writing
  // bytes to disk + storing a path instead if it becomes a problem.

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    'image': imageBytes != null ? base64Encode(imageBytes!) : null,
    'ts': timestamp.toIso8601String(),
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    role: MessageRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => MessageRole.user,
    ),
    text: json['text'] as String? ?? '',
    imageBytes: json['image'] != null
        ? base64Decode(json['image'] as String)
        : null,
    timestamp:
        DateTime.tryParse(json['ts'] as String? ?? '') ?? DateTime.now(),
  );
}
