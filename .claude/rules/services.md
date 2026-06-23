# Rule: Service Layer

## Singleton Pattern

Every service uses the same pattern:

```dart
class XxxService {
  XxxService._();
  static final XxxService instance = XxxService._();

  Future<void> init() async { ... }
  Future<void> dispose() async { ... }
}
```

## Init Sequence (main.dart)

Services init in this order (do not reorder without checking dependencies):

```dart
await ConversationStore.instance.init();  // Hive: conversations box
await DocumentStore.instance.init();      // Hive: documents box
await PrefsService.instance.init();       // SharedPreferences
await GemmaService.instance.init();       // Model detection
RagService.instance.init();              // sqlite-vec store (fire-and-forget)
// VoiceService — lazy init, called from onboarding or chat
```

## Rules

1. **Never instantiate a service in a widget:** `new XxxService()` is a bug.
   Always use `XxxService.instance`.

2. **Services own their error handling.** A service method either:
   - Returns a typed result: `Future<DeviceActionResult>`
   - Sets its own error state: `_state.value = GemmaState.error`
   - Throws only for programming errors (misuse of the API)
   
   Widgets react to state — they do not `try/catch` service calls.

3. **Services are app-lifetime singletons.** `dispose()` is called only in
   `main.dart` teardown (or not at all for services that don't need it).
   Never call `dispose()` from a widget or another service.

4. **No service imports another service's constructor.** Cross-service
   communication goes through method calls on `instance` — never by
   passing a service as a constructor parameter.

5. **Services expose state via `ValueListenable<T>`.** Widgets observe state
   with `ValueListenableBuilder` — they do not poll or use `Timer`.

## Adding a New Service

```dart
// lib/services/my_new_service.dart
class MyNewService {
  MyNewService._();
  static final MyNewService instance = MyNewService._();

  // State (if needed)
  final ValueNotifier<MyState> _state = ValueNotifier(MyState.idle);
  ValueListenable<MyState> get state => _state;

  Future<void> init() async {
    // initialize resources
  }

  // Public API methods here

  Future<void> dispose() async {
    // clean up resources
    _state.dispose();
  }
}
```

Then add to `main.dart` init sequence in the correct order.
