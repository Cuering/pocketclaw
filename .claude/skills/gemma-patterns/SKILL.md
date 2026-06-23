# Skill: Gemma Patterns

Use this skill whenever working with inference, streaming, model lifecycle, or
context management in PocketClaw.

## 1. Basic Inference (text-only)

```dart
if (GemmaService.instance.state.value != GemmaState.ready) {
  // show "Model not ready" message
  return;
}

String response = '';
try {
  response = await GemmaService.instance.generate(
    prompt,
    onToken: (chunk) {
      if (!mounted) return;
      setState(() => _streamBuffer += chunk);
    },
  );
} catch (e) {
  if (!mounted) return;
  setState(() => _error = e.toString());
}
```

## 2. Multimodal Inference (image + text)

```dart
final bytes = await imageFile.readAsBytes();
final response = await GemmaService.instance.generate(
  prompt,
  imageBytes: bytes,
  onToken: (chunk) {
    if (!mounted) return;
    setState(() => _streamBuffer += chunk);
  },
);
```

## 3. Context Window Management

Gemma 4 E2B has a ~4096-token context window. For long conversations, compact
old messages before sending. `chat_screen.dart` contains `_buildCompactedPrompt()`
— use it rather than building prompts manually:

```dart
// Inside chat_screen.dart — already implemented
final prompt = _buildCompactedPrompt(messages, newUserMessage);
```

Do NOT pass the full `messages` list to `generate()` for conversations longer
than ~15 messages. Compaction is already wired — don't bypass it.

## 4. Loading State Pattern

Show the model lifecycle state in the UI:

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) => switch (state) {
    GemmaState.notInstalled => InstallPromptWidget(),
    GemmaState.installing => ValueListenableBuilder<int>(
        valueListenable: GemmaService.instance.downloadProgress,
        builder: (_, progress, __) => DownloadProgressWidget(progress: progress),
      ),
    GemmaState.installed || GemmaState.loading => const ModelLoadingWidget(),
    GemmaState.ready || GemmaState.generating => ChatWidget(),
    GemmaState.error => ErrorWidget(
        error: GemmaService.instance.lastError?.toString() ?? 'Unknown error',
        onRetry: () => GemmaService.instance.resumeIfInstalled(),
      ),
  },
)
```

## 5. Embedder State (for RAG)

```dart
ValueListenableBuilder<EmbedderState>(
  valueListenable: GemmaService.instance.embedderState,
  builder: (context, state, _) {
    if (state == EmbedderState.installing) {
      return ValueListenableBuilder<int>(
        valueListenable: GemmaService.instance.embedderDownloadProgress,
        builder: (_, p, __) => Text('Downloading embedder: $p%'),
      );
    }
    if (state == EmbedderState.installed) return const Icon(Icons.check, color: PocketClawTheme.mint);
    if (state == EmbedderState.error) return Text('Embedder error', style: TextStyle(color: PocketClawTheme.error));
    return const SizedBox.shrink();
  },
)
```

## 6. Disabling Inputs During Generation

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) {
    final isGenerating = state == GemmaState.generating;
    return IconButton(
      onPressed: isGenerating ? null : _sendMessage,
      icon: isGenerating
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send),
    );
  },
)
```
