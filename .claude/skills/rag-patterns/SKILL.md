# Skill: RAG Patterns

Use this skill when implementing document indexing, retrieval-augmented
generation, or any feature that reads from the knowledge base.

## 1. Full Indexing Flow

```dart
// Step 1: Pick a file
final result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['pdf', 'txt'],
);
if (result == null) return;

// Step 2: Extract text (in a service, not widget)
final file = File(result.files.single.path!);
String text;
if (file.path.endsWith('.pdf')) {
  text = await _extractPdfText(file);  // using syncfusion_flutter_pdf
} else {
  text = await file.readAsString();
}

// Step 3: Index (shows RagState.indexing while running)
setState(() => _isIndexing = true);
try {
  final doc = await RagService.instance.indexDocument(
    text: text,
    name: result.files.single.name,
    conversationId: _currentConversationId,
    onProgress: (done, total) => setState(() => _indexProgress = done / total),
  );
  await DocumentStore.instance.save(doc);
} finally {
  if (mounted) setState(() => _isIndexing = false);
}
```

## 2. Retrieval + Prompt Injection

```dart
Future<String> _buildRagPrompt(String userMessage, String conversationId) async {
  // Try semantic retrieval first
  final chunks = await RagService.instance.retrieve(
    query: userMessage,
    conversationId: conversationId,
  );

  if (chunks.isEmpty) {
    // Fallback: use document starts for broad/generic queries
    final starts = await RagService.instance.getDocStarts(
      conversationId: conversationId,
    );
    if (starts.isEmpty) return userMessage;  // no docs — plain prompt
    final context = starts.map((c) => c.content).join('\n\n---\n\n');
    return 'Context from your documents:\n$context\n\nUser: $userMessage';
  }

  final context = chunks.map((c) => '${c.docName}:\n${c.content}').join('\n\n---\n\n');
  return 'Context from your documents:\n$context\n\nUser: $userMessage';
}
```

## 3. Delete Document

```dart
Future<void> _deleteDoc(Document doc) async {
  await RagService.instance.deleteDocument(doc);
  await DocumentStore.instance.delete(doc.id);
  if (mounted) setState(() => _docs.remove(doc));
}
```

## 4. Watching RAG State

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

## 5. When to Use RAG

Only inject RAG context when:
1. The user has indexed at least one document in the current conversation
2. The user's message is likely a question about document content
3. `RagService.instance.state.value == RagState.ready`

Don't auto-retrieve for every message — it's slow and burns context window.
Check `await DocumentStore.instance.listForConversation(conversationId)` to
know if any documents exist before calling `retrieve()`.
