# Rule: Hive Persistence

## Box Opening — Order Matters

TypeAdapters MUST be registered before any box is opened. In `init()`:

```dart
// CORRECT
Hive.registerAdapter(ConversationAdapter());
Hive.registerAdapter(MessageAdapter());
await Hive.openBox<Conversation>('conversations');

// WRONG — crashes with HiveError: Cannot write, unknown type
await Hive.openBox<Conversation>('conversations');
Hive.registerAdapter(ConversationAdapter());
```

## Boxes in PocketClaw

| Box | Type | Service |
|---|---|---|
| `'conversations'` | `Box<Conversation>` | `ConversationStore` |
| `'documents'` | `Box<Document>` | `DocumentStore` |
| Prefs | `SharedPreferences` (not Hive) | `PrefsService` |

Open boxes only inside `XxxStore.init()` — never open boxes directly in widgets or other services.

## Reactive Reads

```dart
// Hive reactive pattern — re-builds when box changes
ValueListenableBuilder<Box<Conversation>>(
  valueListenable: ConversationStore.instance.box.listenable(),
  builder: (context, box, _) {
    final convs = box.values.toList();
    if (convs.isEmpty) return EmptyStateWidget();
    return ConversationListView(convs);
  },
)
```

## Writing Data

```dart
// Always use typed methods on the Store, not raw box.put()
await ConversationStore.instance.save(conversation);
await ConversationStore.instance.delete(conversation.id);
```

## Never Store Raw Maps

```dart
// WRONG
await box.put(key, {'title': 'Chat', 'messages': [...]});

// CORRECT
await box.put(key, Conversation(title: 'Chat', messages: []));
```

All stored types must have a registered `TypeAdapter<T>`.

## Closing Boxes

Boxes are closed in `main.dart` teardown (or app close). Never call
`Hive.close()` from a service or widget.

## TypeAdapter IDs

Each adapter needs a unique `typeId`. Check existing adapters before adding one
to avoid ID collisions:
- `Conversation` — check `ConversationAdapter.typeId`
- `Message` — check `MessageAdapter.typeId`
- `Document` — check `DocumentAdapter.typeId`
