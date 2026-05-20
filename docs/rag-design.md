# RAG design (Day 7 evening, committed plan for Day 8)

flutter_gemma 0.15.1 ships first-party RAG support on Android. We use it.

## Embedding model — Gecko 110M (English)

- URL: https://huggingface.co/litert-community/Gecko-110m-en
- Verified public (no HF token needed) on 2026-05-20
- Files we'll use:
  - Model: `Gecko_1024_quant.tflite` (~110 MB, quantized for mobile)
  - Tokenizer: `sentencepiece.model`
- Dimension: 768

We picked Gecko over EmbeddingGemma 300M because:
- EmbeddingGemma's litert-community mirror is `gated: auto` (HF token required)
- Gecko is open with no auth
- 110 MB vs 75–150 MB — comparable footprint
- Same `litert-community` org as our Gemma 4 install — matching public-mirror story

The plugin's hardcoded `EmbeddingModel.gecko110M` URL is stale (404). We bypass
the enum and call `installEmbedder().modelFromNetwork(<our URL>)` directly.

## Vector store

flutter_gemma exposes `FlutterGemmaPlugin.instance` with:
- `initializeVectorStore(dbPath)` — sqlite3 dart:ffi backend, HNSW above 100 docs
- `addDocumentWithEmbedding({id, content, embedding, metadata})`
- vector store repository's `searchSimilar({queryEmbedding, topK, threshold})`
- `getVectorStoreStats()`

DB lives at `<appDocs>/pocketclaw_rag.db`.

## Chunking strategy

- Split documents on paragraph boundaries (double newline)
- Target ~300 tokens per chunk (≈1200 chars)
- Merge tiny paragraphs (< 80 chars) with the next one
- ID format: `<doc_id>:<chunk_index>`
- Metadata JSON: `{"doc_id": ..., "doc_name": ..., "chunk": ...}`
- We tag chunks with `conversation_id` so retrieval is scoped per-chat

## Retrieval into prompt

Before each `GemmaService.generate`, if the conversation has indexed docs:

1. Embed the user query with the active embedder.
2. Call `searchSimilar(topK=3, threshold=0.5)` against the vector store.
3. Build a synthetic context block by concatenating each retrieved chunk,
   each prefixed with a "[Reference from <doc_name>]" header and separated
   by a triple-dash line. Prepend this block to the system preamble.
4. Append the actual user message after that.
5. Send the full assembled prompt to Gemma.

The intent is that Gemma sees the relevant snippets before it sees the
question, so it answers using the document content. We're not doing
inline citations Day 8 — just trust-the-context. Citations are Day 9+.

## Service surface (to build Day 8)

- `lib/services/rag_service.dart`
  - singleton
  - `init()` — install + load embedder, init vector store
  - `indexDocument(text, docId, docName, conversationId)`
  - `retrieve(query, conversationId, topK)`
  - state: `ValueListenable<RagState>` (idle / installing / indexing / ready / error)
- `lib/models/document.dart` — id, filename, chunkCount, conversationId, createdAt
- `lib/services/document_store.dart` — Hive box of Document metadata

## UI surface (Day 8)

- New 📄 button in ChatInput next to 🖼️
- `file_picker` for text files (.txt only Day 8; PDF Day 9 via syncfusion_flutter_pdf)
- Indexed-document chips above input bar (tap to remove from conversation context)
- Banner "Indexing N pages…" with progress during chunking + embedding
- Tokens used / chunks indexed shown in conversation info screen (later)

## Scope for Day 8 (Wed evening, ~4 hrs fresh)

1. Extend GemmaConfig with embeddingModelUrl + tokenizerUrl
2. Extend GemmaService.init() to also install embedder (parallel with inference where possible)
3. rag_service.dart with chunking + indexing + retrieval
4. document.dart + document_store.dart
5. ChatInput 📄 button + file_picker integration
6. ChatScreen retrieval before generate
7. Test on Nord with a real .txt file: index, query, verify retrieval improves answer quality
8. Commit "Day 8: RAG on-device with Gecko 110M + vector store"

PDF support, citations, multi-doc chips, etc. → Day 9.
