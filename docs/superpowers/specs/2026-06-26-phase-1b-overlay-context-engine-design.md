# Phase 1b — Overlay + Context Engine Design Spec

**Date:** 2026-06-26
**Phase:** 1b of 5 (further_plan.md)
**Owner:** Manoj Shetty (personal side project)
**Status:** Ready for implementation

---

## Goal

Activate the floating overlay bubble (already scaffolded but commented out) and build a Context Engine that captures what app the user is in and what's on screen — so Gemma can give context-aware responses from the overlay without the user needing to switch apps.

---

## Scope

**In scope (Phase 1b):**
- Activate `FlutterOverlayWindow` overlay (uncomment all scaffolding)
- `ContextEngine` Dart singleton — captures foreground app + screen tree (Option C: full tree with fallback)
- `ContextSnapshot` data model
- Wire context into `VoiceService._processCommand` so overlay voice gets screen-aware Gemma responses
- Kotlin: `getContext` method on `pocketclaw/accessibility` channel — returns package name + app name
- Tests: ContextEngine unit tests (mocked channel)

**Out of scope:**
- Wake word continuous listening (VoiceService already handles this)
- Chat screen text input changes
- Phase 2+ features (Skill DSL, Registry, Memory Engine)

---

## Architecture

```
Overlay Bubble (separate isolate)
  ↓  'manual_voice_listen' via IsolateNameServer
VoiceService._processCommand (main isolate)
  ↓  capture() — runs in parallel during recording
ContextEngine
  ├─ PrimitiveEngine.instance.execute([read_screen])  ← if accessibility enabled
  └─ pocketclaw/accessibility → getContext (package + appName)
  ↓  ContextSnapshot
ContextEngine.formatForPrompt(snapshot) → String
  ↓  contextPrefix + commandText
GemmaService.instance.generate(prompt)
  ↓  reply
VoiceService._sendToOverlay({'command': 'response', 'text': reply})
```

**Key constraint:** The overlay runs in a **separate Dart isolate** — it cannot access any singleton (ContextEngine, PrimitiveEngine, GemmaService). All context capture and inference happens in the main isolate, triggered by the IsolateNameServer message.

---

## Data Model

### ContextSnapshot

```dart
// lib/services/context_engine/context_snapshot.dart

class ContextSnapshot {
  final String? foregroundPackage;    // e.g. "com.swiggy.android" — null if unavailable
  final String? foregroundAppName;    // e.g. "Swiggy" — null if unavailable
  final String? screenTree;          // accessibility UI tree text — null if unavailable
  final bool accessibilityAvailable;
  final DateTime capturedAt;

  const ContextSnapshot({
    this.foregroundPackage,
    this.foregroundAppName,
    this.screenTree,
    required this.accessibilityAvailable,
    required this.capturedAt,
  });

  bool get hasContext =>
      foregroundPackage != null || screenTree != null;
}
```

---

## ContextEngine Service API

```dart
// lib/services/context_engine/context_engine.dart

class ContextEngine {
  ContextEngine._();
  static final ContextEngine instance = ContextEngine._();

  static const _channel = MethodChannel('pocketclaw/accessibility');

  /// Captures foreground app + screen tree with fallback.
  /// - Accessibility enabled: returns package, appName, screenTree
  /// - Accessibility disabled: returns all-null snapshot
  /// Never throws — errors produce an empty snapshot.
  Future<ContextSnapshot> capture() async { ... }

  /// Returns a system-context prefix for injection into Gemma prompts.
  /// Returns empty string if snapshot has no context.
  String formatForPrompt(ContextSnapshot snapshot) { ... }
}
```

### capture() logic

```dart
Future<ContextSnapshot> capture() async {
  try {
    final accessible = await PrimitiveEngine.instance.isAccessibilityEnabled();
    if (!accessible) {
      return ContextSnapshot(
        accessibilityAvailable: false,
        capturedAt: DateTime.now(),
      );
    }

    // Run both in parallel: screen tree read + app context
    final results = await Future.wait([
      PrimitiveEngine.instance.execute([
        PrimitiveStep(primitive: 'read_screen'),
      ]),
      _getContext(),
    ]);

    final execResult = results[0] as PrimitiveExecutionResult;
    final contextMap = results[1] as Map<String, String?>;
    final tree = execResult.ok
        ? execResult.stepResults.first.data['tree'] as String?
        : null;

    return ContextSnapshot(
      foregroundPackage: contextMap['package'],
      foregroundAppName: contextMap['appName'],
      screenTree: tree,
      accessibilityAvailable: true,
      capturedAt: DateTime.now(),
    );
  } catch (_) {
    return ContextSnapshot(
      accessibilityAvailable: false,
      capturedAt: DateTime.now(),
    );
  }
}
```

### formatForPrompt() logic

```dart
String formatForPrompt(ContextSnapshot snapshot) {
  if (!snapshot.hasContext) return '';

  final buf = StringBuffer('[Device Context]\n');
  if (snapshot.foregroundAppName != null) {
    buf.writeln('Current app: ${snapshot.foregroundAppName} (${snapshot.foregroundPackage})');
  }
  if (snapshot.screenTree != null && snapshot.screenTree!.isNotEmpty) {
    buf.writeln('Screen content:\n${snapshot.screenTree}');
  }
  buf.write('[/Device Context]');
  return buf.toString();
}
```

### _getContext() helper

Calls `pocketclaw/accessibility` channel method `getContext`:

```dart
Future<Map<String, String?>> _getContext() async {
  try {
    final result = await _channel
        .invokeMapMethod<String, String>('getContext')
        .timeout(const Duration(seconds: 3));
    return result?.map((k, v) => MapEntry(k, v as String?)) ?? {};
  } on PlatformException {
    return {};
  } on TimeoutException {
    return {};
  }
}
```

---

## Kotlin: getContext

Add to `PocketClawAccessibilityService.handleCall()`:

```kotlin
"getContext" -> {
    val root = rootInActiveWindow
    if (root == null) {
        result.success(mapOf("package" to null, "appName" to null))
        return
    }
    val packageName = root.packageName?.toString()
    root.recycle()
    val appName = try {
        packageManager.getApplicationLabel(
            packageManager.getApplicationInfo(packageName ?: "", 0)
        ).toString()
    } catch (_: Exception) {
        packageName
    }
    result.success(mapOf("package" to packageName, "appName" to appName))
}
```

Add to `MainActivity.configureFlutterEngine()`, inside the `pocketclaw/accessibility` channel handler — routes to `service.handleCall(call, result)` like all other primitives (already covered by the existing `else` branch that delegates to `handleCall`).

---

## Context Injection into VoiceService

Modify `VoiceService._processCommand`:

```dart
Future<void> _processCommand(String commandText) async {
  try {
    // Capture context (runs quickly, accessibility service already warm)
    final snapshot = await ContextEngine.instance.capture();
    final contextPrefix = ContextEngine.instance.formatForPrompt(snapshot);

    final executionReport = await ChatCommandService.instance
        .tryHandleWithGemma(commandText);

    String reply;
    if (executionReport != null) {
      reply = executionReport;
    } else {
      final now = DateTime.now();
      final localContext =
          'Today is ${now.day}/${now.month}/${now.year}. '
          'Time: ${now.hour}:${now.minute}. '
          'The user asked via voice overlay. Give a brief, direct answer '
          '(under 2 sentences) suitable for a voice readout.';

      final fullPrompt = contextPrefix.isNotEmpty
          ? '$contextPrefix\n\n$localContext\n\nUser: "$commandText"'
          : '$localContext\n\nUser request: "$commandText"';

      reply = await GemmaService.instance.generate(
        fullPrompt,
        userName: PrefsService.instance.current.name,
      );
    }
    // ... rest unchanged
  }
}
```

---

## Overlay Activation

### pubspec.yaml
Uncomment: `flutter_overlay_window: ^0.5.0`

### lib/main.dart
1. Uncomment imports: `dart:isolate`, `dart:ui`, `flutter_overlay_window`
2. Uncomment the entire `/* ... */` block containing `overlayMain()` and `_ClawBubble`
3. The `_buildExpanded()` method is missing from the scaffold — add it:
   ```dart
   Widget _buildExpanded() {
     if (_listening || _thinking || _responseSpeechText != null) {
       return _voicePanel();
     }
     return _expandedPanel();
   }
   ```
4. Import `DeviceActionsService` (already needed by `_openApp`)
5. Import `OverlayControllerService` (needed by `_destroy`)

### lib/services/overlay_controller_service.dart
Uncomment all method bodies (currently all are `return false` / empty stubs).

### lib/screens/onboarding_screen.dart
Uncomment the `_PermissionRow` for Display Over Apps (currently commented out as `_grantOverlay`).

### lib/screens/chat_screen.dart
- Uncomment `import 'package:flutter_overlay_window/flutter_overlay_window.dart'`
- Uncomment overlay toggle in settings panel (`overlayEnabled` toggle)
- The `_onOverlayEvent` already handles `manual_voice_listen` correctly — no changes needed there

### android/app/src/main/AndroidManifest.xml
1. Uncomment `SYSTEM_ALERT_WINDOW` permission
2. Uncomment the `OverlayService` service declaration

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `lib/services/context_engine/context_snapshot.dart` | Create | ContextSnapshot data model |
| `lib/services/context_engine/context_engine.dart` | Create | ContextEngine singleton service |
| `test/services/context_engine/context_engine_test.dart` | Create | Unit tests (mocked channel) |
| `lib/main.dart` | Modify | Uncomment overlay isolate block + add `_buildExpanded()` |
| `lib/services/overlay_controller_service.dart` | Modify | Uncomment all method bodies |
| `lib/services/voice_service.dart` | Modify | Import + call ContextEngine in `_processCommand` |
| `pubspec.yaml` | Modify | Uncomment `flutter_overlay_window: ^0.5.0` |
| `android/app/src/main/AndroidManifest.xml` | Modify | Uncomment SYSTEM_ALERT_WINDOW + OverlayService |
| `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt` | Modify | Add `getContext` handler |
| `lib/screens/onboarding_screen.dart` | Modify | Uncomment Display Over Apps permission row |
| `lib/screens/chat_screen.dart` | Modify | Uncomment overlay toggle in settings |

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Accessibility not enabled | `capture()` returns all-null snapshot; voice responds without context prefix |
| `getContext` times out (>3s) | Returns `{}` map; snapshot has null package/appName but may still have tree |
| `read_screen` fails (PlatformException) | `execResult.ok = false`; screenTree = null; continue with whatever we have |
| Overlay permission not granted | `OverlayControllerService.setEnabled()` returns false; user sees snackbar |
| `ContextEngine.capture()` throws | Top-level catch returns empty snapshot — voice always continues |

---

## Tests

### context_engine_test.dart

Using `TestDefaultBinaryMessengerBinding` to mock `pocketclaw/accessibility`:

- `capture()` with accessibility enabled, `getContext` returning package + appName, `read_screen` returning tree → full snapshot
- `capture()` with accessibility disabled → all-null snapshot, `accessibilityAvailable = false`
- `capture()` with `read_screen` failing → snapshot has package/appName but screenTree = null
- `formatForPrompt()` with full snapshot → contains `[Device Context]`, app name, screen content
- `formatForPrompt()` with all-null snapshot → returns empty string
- `formatForPrompt()` with package only (no tree) → contains app name, no screen content section
- `capture()` throws exception mid-flight → returns empty snapshot (never throws)

---

## What This Unlocks

- Overlay is active: users can access Claw from any app via the floating bubble
- Voice commands are context-aware: Gemma knows what app is open and what's on screen
- Phase 2 (Skill Engine) can use `ContextEngine.capture()` to decide which skill to run
- Phase 3 (Agent Loop) wraps context capture in its observe step
