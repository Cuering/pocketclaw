# Rule: Widgets

## build() is Pure

`build()` must have no side effects. These are bugs:

```dart
// WRONG — side effect in build
Widget build(BuildContext context) {
  GemmaService.instance.generate(prompt);  // side effect
  return Text('...');
}

// WRONG — async in build
Widget build(BuildContext context) {
  Future.delayed(...);  // side effect
  return Text('...');
}
```

All async work belongs in event handlers (`onTap`, `onPressed`, `initState`,
`didChangeDependencies`) or `initState`/`didUpdateWidget`.

## 3 States — Always

Every widget backed by async data must handle all three states:

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) {
    // 1. Loading
    if (state == GemmaState.loading || state == GemmaState.installing) {
      return const CircularProgressIndicator();
    }
    // 2. Error
    if (state == GemmaState.error) {
      return Column(children: [
        Text('Something went wrong', style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ]);
    }
    // 3. Data
    return ChatView();
  },
)
```

## Disposal

Always dispose in `dispose()`:

```dart
final TextEditingController _inputController = TextEditingController();
final ScrollController _scrollController = ScrollController();
StreamSubscription<String>? _streamSub;

@override
void dispose() {
  _inputController.dispose();
  _scrollController.dispose();
  _streamSub?.cancel();
  super.dispose();
}
```

## Mounted Check

After every `await`, check `mounted` before using `context` or calling `setState`:

```dart
await someAsyncOperation();
if (!mounted) return;
setState(() { ... });
```

## const Everywhere

```dart
// CORRECT
const SizedBox(height: 16)
const Icon(Icons.mic)
const Text('PocketClaw')

// WRONG — missing const when possible
SizedBox(height: 16)
```

Run `dart fix --apply` to add missing `const` automatically.

## ListView

```dart
// CORRECT
ListView.builder(
  itemCount: messages.length,
  itemBuilder: (context, i) => MessageBubble(message: messages[i]),
)

// WRONG — builds all items upfront
ListView(children: messages.map((m) => MessageBubble(message: m)).toList())
```

## Empty State

Any list/data view needs an empty state:

```dart
if (conversations.isEmpty) {
  return Center(
    child: Column(children: [
      Icon(Icons.chat_bubble_outline, color: PocketClawTheme.muted, size: 48),
      const SizedBox(height: 12),
      Text('No conversations yet', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 8),
      FilledButton(onPressed: onNewChat, child: const Text('Start a chat')),
    ]),
  );
}
```

## Widget Type Hierarchy

- Use `StatelessWidget` when there is no mutable state
- Use `StatefulWidget` when managing local UI state (input, scroll position, etc.)
- Use `ValueListenableBuilder` (not `setState`) for service state observation
