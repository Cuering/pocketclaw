# Rule: GemmaService Usage

## State Machine

```
notInstalled → installing → installed → loading → ready ⇄ generating
                                                     ↓
                                                   error
```

`EmbedderState` is independent: `notInstalled → installing → installed | error`

## Access Pattern

Always use the singleton:
```dart
GemmaService.instance   // correct
new GemmaService()      // NEVER — private constructor
```

## Before Generating

Always check state before calling `generate()`:
```dart
if (GemmaService.instance.state.value != GemmaState.ready) return;
final reply = await GemmaService.instance.generate(
  prompt,
  imageBytes: imageBytes,   // null for text-only
  onToken: (chunk) => setState(() => _partial += chunk),
);
```

`generate()` is NOT re-entrant. A second call while `generating` will throw
or silently fail. Disable the send button and voice trigger while
`state.value == GemmaState.generating`.

## Watching State in Widgets

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) {
    if (state == GemmaState.error) {
      return ErrorWidget(GemmaService.instance.lastError?.toString() ?? 'Unknown error');
    }
    if (state != GemmaState.ready) {
      return LoadingWidget();
    }
    return ChatWidget();
  },
)
```

## Download Progress

```dart
ValueListenableBuilder<int>(
  valueListenable: GemmaService.instance.downloadProgress,
  builder: (context, progress, _) => LinearProgressIndicator(value: progress / 100),
)
```

## Error Handling

Services catch their own errors. Widgets react to `GemmaState.error`:
```dart
// CORRECT — react to state
if (state == GemmaState.error) showErrorBanner(GemmaService.instance.lastError);

// WRONG — widget catching service internals
try { await GemmaService.instance.generate(...); } catch (e) { ... }
```

## StreamSubscription

If you hold a `StreamSubscription` from an inference stream, cancel it in `dispose()`:
```dart
StreamSubscription<String>? _sub;

@override
void dispose() {
  _sub?.cancel();
  super.dispose();
}
```

## Embedder

The embedder is needed for RAG only. `RagService` calls `GemmaService.instance.getEmbedder()` internally — you don't need to call it directly from a screen.

## What NOT to Do

- Never call `GemmaService.instance.dispose()` from a widget or service
- Never call `GemmaService.instance.load()` or `install()` directly — use `ensureInstalled()` / `ensureLoaded()`
- Never instantiate `FlutterGemma` directly — always go through `GemmaService`
