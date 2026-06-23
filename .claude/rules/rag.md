# Rule: RagService Usage

## State Machine

```
notReady → ready ⇄ indexing
              ↓
           retrieving
              ↓
           error
```

## Indexing a Document

```dart
// 1. Extract text from file (PDF or TXT) — in service, not widget
// 2. Call indexDocument
final doc = await RagService.instance.indexDocument(
  text: extractedText,
  name: fileName,
  conversationId: currentConversationId,
  onProgress: (done, total) => setState(() => _progress = done / total),
);
// Returns Document object — save to DocumentStore
await DocumentStore.instance.save(doc);
```

Never call `indexDocument` from `build()` or directly in a widget tap handler
without a loading state guard. Set `RagState.indexing` is surfaced via
`RagService.instance.state`.

## Retrieval

```dart
final chunks = await RagService.instance.retrieve(
  query: userMessage,
  conversationId: conversationId,
  // topK defaults to 3 — do not override without profiling
);

// Inject into prompt as system context — never concatenate into user message
final context = chunks.map((c) => c.content).join('\n\n---\n\n');
final prompt = 'Context:\n$context\n\nUser: $userMessage';
```

Constants (do not change without testing):
- `topK = 3` (default in `RagService._defaultTopK`)
- `threshold = 0.4` (default in `RagService._defaultThreshold`)
- Chunk size: ~1200 chars (~300 tokens), minimum 80 chars

## Chunking

`RagService.instance.chunk(text)` returns `List<String>`. You don't need to call
this directly — `indexDocument` calls it internally. Only use it for testing.

## Document Starts (Fallback Retrieval)

For generic queries that don't match any chunk:
```dart
final starts = await RagService.instance.getDocStarts(
  conversationId: conversationId,
  perDocLimit: 3,  // first 3 chunks per document
);
```

## Deleting a Document

```dart
await RagService.instance.deleteDocument(doc);
await DocumentStore.instance.delete(doc.id);
```

## Watching RAG State in Widgets

```dart
ValueListenableBuilder<RagState>(
  valueListenable: RagService.instance.state,
  builder: (context, state, _) => switch (state) {
    RagState.notReady => const CircularProgressIndicator(),
    RagState.indexing => const Text('Indexing document...'),
    RagState.retrieving => const Text('Searching knowledge base...'),
    RagState.error => Text(
        'RAG error: ${RagService.instance.lastError}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: PocketClawTheme.error),
      ),
    RagState.ready => DocumentListWidget(),
  },
)
```

## What NOT to Do

- Never embed on the main thread outside of RagService — embedder calls are async and slow
- Never call `RagService.instance.init()` from a widget — it's called in `main.dart`
- Never concatenate retrieved chunks directly into the user message — inject as system context
- Never call `retrieve()` for every keypress — debounce or call on final message send only
