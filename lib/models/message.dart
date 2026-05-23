import 'dart:convert';
import 'dart:typed_data';

/// Who sent the message in a conversation.
enum MessageRole { user, assistant, system }

/// A single message in a conversation thread.
///
/// Can carry optional attachment metadata:
///   - imageBytes: an image, sent ALONG with text as a multimodal prompt
///     to Gemma in the same turn. Older image bytes are removed after
///     context compaction, while imageSummary remains for future prompts.
///   - imageName/imageSummary: durable image memory used after the raw bytes
///     are no longer sent to the model.
///   - attachedDocName: a document the user uploaded for RAG. The doc
///     itself is chunked + embedded into the vector store and stays
///     active for retrieval across the entire conversation. This field
///     on the message just records "here's where the user attached it"
///     so we can render an attachment card in chat history.
class Message {
  Message({
    required this.role,
    required this.text,
    this.imageBytes,
    this.imageName,
    this.imageSummary,
    this.attachedDocId,
    this.attachedDocName,
    this.attachedDocChunkCount,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final MessageRole role;
  final String text;
  final Uint8List? imageBytes;
  final String? imageName;
  final String? imageSummary;

  // Document attachment metadata. Always set together or all-null.
  // The doc itself lives in the vector store + DocumentStore — these
  // fields are just for rendering the in-chat attachment card.
  final String? attachedDocId;
  final String? attachedDocName;
  final int? attachedDocChunkCount;

  final DateTime timestamp;

  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
  bool get hasImageSummary =>
      imageSummary != null && imageSummary!.trim().isNotEmpty;
  bool get hasDoc => attachedDocId != null && attachedDocName != null;
  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  /// Convenience copy with a different text (used while streaming the
  /// assistant's response token by token).
  Message copyWith({
    String? text,
    Uint8List? imageBytes,
    bool clearImage = false,
    String? imageName,
    String? imageSummary,
  }) => Message(
    role: role,
    text: text ?? this.text,
    imageBytes: clearImage ? null : imageBytes ?? this.imageBytes,
    imageName: imageName ?? this.imageName,
    imageSummary: imageSummary ?? this.imageSummary,
    attachedDocId: attachedDocId,
    attachedDocName: attachedDocName,
    attachedDocChunkCount: attachedDocChunkCount,
    timestamp: timestamp,
  );

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    'image': imageBytes != null ? base64Encode(imageBytes!) : null,
    'imageName': imageName,
    'imageSummary': imageSummary,
    'docId': attachedDocId,
    'docName': attachedDocName,
    'docChunks': attachedDocChunkCount,
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
    imageName: json['imageName'] as String?,
    imageSummary: json['imageSummary'] as String?,
    attachedDocId: json['docId'] as String?,
    attachedDocName: json['docName'] as String?,
    attachedDocChunkCount: json['docChunks'] as int?,
    timestamp: DateTime.tryParse(json['ts'] as String? ?? '') ?? DateTime.now(),
  );
}
