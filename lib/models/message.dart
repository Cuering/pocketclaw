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
}
