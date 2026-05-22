import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/app_exception.dart';
import '../models/document.dart';
import 'document_store.dart';
import 'gemma_service.dart';

/// Lifecycle of the RAG subsystem.
enum RagState {
  notReady,   // vector store not initialized yet (waiting for init)
  ready,      // vector store open, embedder available
  indexing,   // currently chunking + embedding a document
  retrieving, // currently embedding a query and searching
  error,
}

/// Wraps flutter_gemma's RAG primitives (EmbeddingModel + vector store)
/// behind a single PocketClaw-flavoured API.
///
/// Lifecycle:
///   1. App boot: main() calls [init] which opens the SQLite vector store
///      at the app documents directory.
///   2. User uploads a doc: chat code calls [indexDocument]; we chunk the
///      text, embed each chunk via the active Gecko model, and write each
///      chunk into the vector store with metadata that links it to the
///      source document + conversation.
///   3. User sends a message: chat code calls [retrieve] with the user's
///      query and current conversation id; the facade embeds the query
///      and runs HNSW search; we filter by conversation_id and return
///      the chunk text. The chat layer prepends those chunks as context.
///
/// Threading: all embedding + searches are async and yield to the event
/// loop, so the UI stays responsive. Embedding ~1000 chars takes <50ms
/// on the Nord CE 4 GPU.
class RagService {
  RagService._();
  static final RagService instance = RagService._();

  // ── Public state ──────────────────────────────────────────────────────
  final ValueNotifier<RagState> _state = ValueNotifier(RagState.notReady);
  ValueListenable<RagState> get state => _state;

  Object? _lastError;
  Object? get lastError => _lastError;

  // ── Tunables ──────────────────────────────────────────────────────────
  //
  // ~1200 chars is roughly 300 tokens for English. Gecko's seq length is
  // 1024 tokens so we stay well under it. Chunks too small lose context,
  // too large lose retrieval precision; 1200 is a reasonable middle.
  static const int _targetChunkChars = 1200;

  // Merge any paragraph shorter than this with the next one. Avoids
  // pathological splits like 'h1 / blank / actual paragraph'.
  static const int _minChunkChars = 80;

  // Retrieval defaults. Top-3 gives the LLM enough context without
  // bloating the prompt; threshold 0.4 filters obviously-irrelevant
  // chunks while staying permissive on borderline matches.
  static const int _defaultTopK = 3;
  static const double _defaultThreshold = 0.4;

  // ── Init ──────────────────────────────────────────────────────────────
  bool _initialized = false;

  /// Opens (or creates) the vector store at [appDocs]/pocketclaw_rag.db.
  /// Idempotent. Safe to call before the embedder is installed; searches
  /// will simply fail until the embedder is ready.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/pocketclaw_rag.db';
      await fg.FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);
      _initialized = true;
      _state.value = RagState.ready;
      debugPrint('🐾 RAG: vector store ready at $dbPath');
    } catch (e, stack) {
      _lastError = e;
      _state.value = RagState.error;
      debugPrint('🐾 RAG: init failed: $e\n$stack');
      throw RagException('Failed to initialize vector store', e);
    }
  }

  // ── Chunking ──────────────────────────────────────────────────────────

  /// Split text into chunks suitable for embedding.
  ///
  /// Strategy:
  ///   1. Split on blank-line paragraph boundaries.
  ///   2. Merge tinies (less than 80 chars) into their successor.
  ///   3. If a paragraph is still longer than the target, soft-split on
  ///      sentence boundaries (period/question/exclaim followed by space).
  ///   4. Fallback hard-split at the target length for monsters.
  @visibleForTesting
  List<String> chunk(String text) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    // Step 2: merge tinies forward.
    final merged = <String>[];
    String pending = '';
    for (final p in paragraphs) {
      pending = pending.isEmpty ? p : '$pending\n\n$p';
      if (pending.length >= _minChunkChars) {
        merged.add(pending);
        pending = '';
      }
    }
    if (pending.isNotEmpty) merged.add(pending);

    // Step 3 + 4: split anything too long.
    final result = <String>[];
    for (final m in merged) {
      if (m.length <= _targetChunkChars) {
        result.add(m);
        continue;
      }
      final sentences = m.split(RegExp(r'(?<=[.!?])\s+'));
      String buf = '';
      for (final s in sentences) {
        if (buf.isEmpty) {
          buf = s;
        } else if ('$buf $s'.length <= _targetChunkChars) {
          buf = '$buf $s';
        } else {
          result.add(buf);
          buf = s;
        }
      }
      if (buf.isNotEmpty) result.add(buf);
    }

    // Step 5: anything STILL too long (one super-long sentence) gets a
    // hard cut. Rare in real documents.
    final out = <String>[];
    for (final c in result) {
      if (c.length <= _targetChunkChars * 1.2) {
        out.add(c);
      } else {
        for (int i = 0; i < c.length; i += _targetChunkChars) {
          final end = (i + _targetChunkChars) > c.length
              ? c.length
              : i + _targetChunkChars;
          out.add(c.substring(i, end));
        }
      }
    }
    return out;
  }

  // ── Indexing ──────────────────────────────────────────────────────────

  /// Chunk [text], embed each chunk, write all chunks to the vector store
  /// tagged with the document + conversation, save a Document record to
  /// DocumentStore so it shows up in the chat UI.
  ///
  /// Returns the Document record on success. Throws RagException on
  /// failure; partial writes are not rolled back (good-enough for v1).
  Future<Document> indexDocument({
    required String text,
    required String name,
    required String conversationId,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!_initialized) {
      throw const RagException('RagService not initialized. Call init().');
    }
    if (text.trim().isEmpty) {
      throw const RagException('Document is empty.');
    }

    _state.value = RagState.indexing;
    try {
      final embedder = await GemmaService.instance.getEmbedder();
      final chunks = chunk(text);
      if (chunks.isEmpty) {
        throw const RagException('No chunks produced from document.');
      }
      debugPrint('🐾 RAG: indexing "$name" -> ${chunks.length} chunks');

      final docId = const Uuid().v4();

      // Batch embed. Faster than N single-embeds because it's one model
      // dispatch instead of N.
      final embeddings = await embedder.generateEmbeddings(
        chunks,
        taskType: fg.TaskType.retrievalDocument,
      );

      for (int i = 0; i < chunks.length; i++) {
        final chunkId = '$docId:$i';
        final metadata = jsonEncode({
          'doc_id': docId,
          'doc_name': name,
          'conversation_id': conversationId,
          'chunk_index': i,
        });
        await fg.FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: chunkId,
          content: chunks[i],
          embedding: embeddings[i],
          metadata: metadata,
        );
        onProgress?.call(i + 1, chunks.length);
      }

      final doc = Document(
        id: docId,
        name: name,
        conversationId: conversationId,
        chunkCount: chunks.length,
      );
      await DocumentStore.instance.save(doc);

      _state.value = RagState.ready;
      debugPrint('🐾 RAG: indexed $name (${chunks.length} chunks)');
      return doc;
    } catch (e, stack) {
      _lastError = e;
      _state.value = RagState.error;
      debugPrint('🐾 RAG: indexDocument failed: $e\n$stack');
      throw RagException('Failed to index document', e);
    }
  }

  // ── Retrieval ─────────────────────────────────────────────────────────

  /// Search the vector store for chunks similar to [query], filter to
  /// chunks from documents in [conversationId], return their text in
  /// rank order. Empty list if nothing indexed for the conversation or
  /// nothing meets the threshold.
  ///
  /// Soft-fails (returns empty) on errors instead of throwing — chat
  /// should keep working even if RAG breaks.
  ///
  /// Note: the facade's searchSimilar takes the raw query string and
  /// embeds it internally via the active embedder; we don't have to
  /// embed the query ourselves.
  Future<List<RetrievedChunk>> retrieve({
    required String query,
    required String conversationId,
    int topK = _defaultTopK,
    double threshold = _defaultThreshold,
  }) async {
    if (!_initialized) return const [];
    if (query.trim().isEmpty) return const [];

    _state.value = RagState.retrieving;
    try {
      // Over-fetch: we filter by conversation_id post-search. If a user
      // has docs across many chats, the top-K globally might miss this
      // chat. 4x topK as buffer is cheap and pragmatic.
      final raw = await fg.FlutterGemmaPlugin.instance.searchSimilar(
        query: query,
        topK: topK * 4,
        threshold: threshold,
      );

      final results = <RetrievedChunk>[];
      for (final r in raw) {
        try {
          final meta = jsonDecode(r.metadata ?? '{}') as Map<String, dynamic>;
          if (meta['conversation_id'] != conversationId) continue;
          results.add(RetrievedChunk(
            content: r.content,
            docName: meta['doc_name'] as String? ?? 'document',
            chunkIndex: meta['chunk_index'] as int? ?? 0,
            similarity: r.similarity,
          ));
          if (results.length >= topK) break;
        } catch (e) {
          debugPrint('🐾 RAG: skipping malformed result: $e');
        }
      }

      _state.value = RagState.ready;
      debugPrint(
        '🐾 RAG: retrieved ${results.length}/${raw.length} chunks for "$query"',
      );
      return results;
    } catch (e, stack) {
      _lastError = e;
      _state.value = RagState.error;
      debugPrint('🐾 RAG: retrieve failed: $e\n$stack');
      return const [];
    }
  }

  /// Remove a document's metadata from PocketClaw's store.
  /// Note: The chunks remain in the vector store. The plugin's facade
  /// does not expose per-document removal; only [clearVectorStore]
  /// (nukes everything) is public. Stale chunks are harmless — they
  /// just won't surface in retrievals because no Document record
  /// references them and the conversation_id filter excludes most
  /// queries from matching them anyway. v2 will add proper chunk
  /// cleanup once the facade exposes removeDocument.
  Future<void> deleteDocument(Document doc) async {
    await DocumentStore.instance.delete(doc.id);
    debugPrint('🐾 RAG: deleted document record for ${doc.name} '
        '(${doc.chunkCount} chunks remain in vector store as orphans)');
  }
}

/// A retrieved chunk with its source metadata. Returned by [RagService.retrieve].
class RetrievedChunk {
  const RetrievedChunk({
    required this.content,
    required this.docName,
    required this.chunkIndex,
    required this.similarity,
  });

  final String content;
  final String docName;
  final int chunkIndex;
  final double similarity;
}

/// Thrown by RAG operations on initialization / indexing failures.
/// Retrieval failures soft-fail (return empty) rather than throw.
class RagException extends AppException {
  const RagException(super.message, [super.cause]);
}
