import 'package:uuid/uuid.dart';

/// Metadata for a document the user has indexed into RAG for a conversation.
///
/// The actual chunks + embeddings live in flutter_gemma's vector store
/// (sqlite_vec via FlutterGemmaPlugin.instance). This model is just the
/// user-facing record: which file, which conversation, how many chunks,
/// when it was added.
class Document {
  Document({
    String? id,
    required this.name,
    required this.conversationId,
    required this.chunkCount,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name; // e.g. 'lease_agreement.txt'
  final String conversationId;
  final int chunkCount;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'conversationId': conversationId,
        'chunkCount': chunkCount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'unnamed',
        conversationId: json['conversationId'] as String? ?? '',
        chunkCount: json['chunkCount'] as int? ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
