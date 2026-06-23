# Skill: Device Actions Patterns

Use this skill when adding new device actions, modifying intent parsing, or
working with the `ChatCommandService` / `DeviceActionsService` layer.

## Architecture

```
User message (text)
    ↓
ChatCommandService.tryHandleWithGemma(text)
    │   Uses GemmaService to parse intent → JSON function call
    │   Falls back to ChatCommandService.tryHandle(text)  (regex-based)
    ↓
DeviceActionsService.instance.<action>(args)
    │   Sends via MethodChannel('pocketclaw/device')
    ↓
Kotlin (android/app/src/main/kotlin/.../MainActivity.kt)
```

## Calling from Chat

```dart
// In the message send handler (already in chat_screen.dart)
final reply = await ChatCommandService.instance.tryHandleWithGemma(userMessage);
if (reply != null) {
  // Device command was handled — reply is the user-facing response string
  _addAssistantMessage(reply);
  return;
}
// Fall through to normal Gemma inference
```

## DeviceActionsService API

```dart
// Flashlight
final result = await DeviceActionsService.instance.setTorch(true);
if (!result.ok) showError(result.message);

// Alarm
await DeviceActionsService.instance.openAlarm(label: 'Wake up', hour: 7, minute: 30);

// SMS
await DeviceActionsService.instance.openSms(phone: '+1234567890', body: 'On my way');

// Calendar event
await DeviceActionsService.instance.openCalendar(
  title: 'Team standup',
  dateTime: DateTime(2026, 7, 1, 9, 0),
);

// Web search
await DeviceActionsService.instance.openWebSearch('flutter isolates tutorial');

// All return DeviceActionResult(ok: bool, message: String)
```

## Adding a New Device Action

**Step 1 — Dart side** (`lib/services/device_actions_service.dart`):
```dart
Future<DeviceActionResult> myNewAction(String param) =>
    _invoke('myNewAction', {'param': param});
```

**Step 2 — Kotlin side** (`android/app/src/main/.../MainActivity.kt`):
```kotlin
"myNewAction" -> {
    val param = call.argument<String>("param") ?: ""
    // perform action
    result.success(mapOf("ok" to true, "message" to "Done"))
}
```

**Step 3 — Register in `ChatCommandService.tryHandle()`**:
```dart
if (_containsAny(lower, ['my trigger phrase', 'alternate trigger'])) {
  final param = _stripCommand(trimmed, ['my trigger phrase', 'alternate trigger']);
  return await DeviceActionsService.instance.myNewAction(param)
      .then((r) => r.message);
}
```

**Step 4 — Add to Gemma prompt** in `ChatCommandService.tryHandleWithGemma()`:
Add to the numbered list of available functions in the system prompt:
```
6. "myNewAction" args: {"param": "string"} (e.g. "trigger phrase example")
```

## Handling DeviceActionResult

```dart
final result = await DeviceActionsService.instance.setTorch(enabled);
if (result.ok) {
  _addAssistantMessage('Done! ${result.message}');
} else {
  _addAssistantMessage('Sorry, I couldn\'t do that: ${result.message}');
}
```

Never throw on `!result.ok` — these are user-facing failures (permission denied,
feature unavailable) not programming errors.
