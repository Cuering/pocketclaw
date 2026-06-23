# Rule: Performance

## RAM Budget

Gemma 4 E2B INT4 occupies ~1.5 GB. App overhead adds ~200–400 MB.
**Peak RAM: ~2 GB.** Mid-range Android devices may OOM. Keep widget trees lean.

Rules:
- No `Image.network` — all images are local assets
- No `Image.asset` inside `ListView.builder` without `cacheWidth`/`cacheHeight`
- No `Column` inside `SingleChildScrollView` with an inner `ListView` — use `CustomScrollView` with slivers

## Main Thread

GemmaService runs `flutter_gemma` inference on a native thread, but the
`generate()` call still occupies a Dart Future slot. While generating:

- The UI stays responsive (inference is off the main thread natively)
- `GemmaState.generating` is set — respect it, disable inputs
- The `onToken` callback fires on the main thread — keep it fast

```dart
// CORRECT — onToken just updates local state
await GemmaService.instance.generate(
  prompt,
  onToken: (chunk) {
    if (!mounted) return;
    setState(() => _buffer += chunk);  // fast, no heavy work
  },
);

// WRONG — heavy work in onToken
await GemmaService.instance.generate(
  prompt,
  onToken: (chunk) {
    parseMarkdown(chunk);     // slow
    saveToDatabase(chunk);    // I/O in hot path
  },
);
```

## StreamSubscription Lifecycle

Always cancel subscriptions in `dispose()`:

```dart
StreamSubscription<String>? _genSub;

void _startGeneration() {
  _genSub?.cancel();
  // assign new subscription
}

@override
void dispose() {
  _genSub?.cancel();
  super.dispose();
}
```

Failing to cancel leaves inference running in the background after the screen is gone.

## const Everywhere

`const` prevents widget rebuilds:

```dart
// CORRECT — rebuilt only when parent explicitly passes new data
const SizedBox(height: 16)
const Padding(padding: EdgeInsets.all(8))
const Icon(Icons.mic)

// WRONG — creates new object on every build()
SizedBox(height: 16)
```

Run `flutter analyze` — it flags missing `const`.

## ListView

```dart
// CORRECT — builds only visible items
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => ItemWidget(item: items[i]),
)

// WRONG — builds ALL items immediately
ListView(children: items.map((i) => ItemWidget(item: i)).toList())
```

## Context Compaction

For long conversations, inject a compact summary instead of the full history.
`chat_screen.dart` already has compaction logic. Don't bypass it by passing
the full message list to `generate()`.
