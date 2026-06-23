# Primitive Engine — Design Spec (Phase 1a)

**Date:** 2026-06-23
**Phase:** 1a of 5 (further_plan.md)
**Owner:** Manoj Shetty (personal side project)
**Status:** Ready for implementation

---

## Goal

Build the Primitive Engine — the foundational execution layer that sits between the Skill Engine and the Android UI. Skills are JSON step lists; the Primitive Engine parses and executes them via Android's AccessibilityService. This is the layer that makes PocketClaw an agent, not just a chatbot.

---

## Scope

**In scope (Phase 1a):**
- `PrimitiveEngine` Dart singleton — JSON step executor
- `PrimitiveStep`, `PrimitiveResult`, `PrimitiveExecutionResult`, `PrimitiveState` data models
- `PocketClawAccessibilityService` Kotlin — AccessibilityService wired via MethodChannel
- 9 primitives: `open_app`, `tap`, `type`, `scroll`, `swipe`, `back`, `read_screen`, `read_clipboard`, `take_screenshot`
- AndroidManifest registration + accessibility_service_config.xml
- Unit + integration tests

**Out of scope (later phases):**
- `store_memory`, `search_memory` — Memory Engine (Phase 2+)
- `render_component`, `create_workflow` — Dynamic UI / Workflow Engine (Phase 4)
- Overlay integration — Phase 1b
- Context Engine — Phase 1b
- Agent Loop (observe-plan-act cycles) — Phase 3

---

## Architecture

```
Chat / Skill Engine
       ↓  List<PrimitiveStep>
PrimitiveEngine (Dart singleton)
  lib/services/primitive_engine/primitive_engine.dart
  lib/services/primitive_engine/primitive_models.dart
       ↓  MethodChannel('pocketclaw/accessibility')
PocketClawAccessibilityService (Kotlin)
  android/app/src/main/kotlin/.../PocketClawAccessibilityService.kt
       ↓  AccessibilityNodeInfo API + GestureDescription
Android UI / running apps
```

**Channel name:** `pocketclaw/accessibility` (separate from existing `pocketclaw/device`)

**Existing `pocketclaw/device` channel is unchanged.** `open_app`, `read_clipboard`, and `take_screenshot` primitives delegate to it internally so there is no duplication.

---

## Data Models

### PrimitiveStep

```dart
class PrimitiveStep {
  final String primitive;          // e.g. "tap", "type", "read_screen"
  final Map<String, dynamic> args; // primitive-specific arguments

  const PrimitiveStep({required this.primitive, this.args = const {}});

  factory PrimitiveStep.fromJson(Map<String, dynamic> json) {
    return PrimitiveStep(
      primitive: json['primitive'] as String,
      args: (json['args'] as Map<String, dynamic>?) ?? {},
    );
  }
}
```

### PrimitiveResult

```dart
class PrimitiveResult {
  final bool ok;
  final String message;
  final Map<String, dynamic> data; // output: {"tree": "...", "text": "...", "path": "..."}

  const PrimitiveResult({
    required this.ok,
    this.message = '',
    this.data = const {},
  });
}
```

### PrimitiveExecutionResult

```dart
class PrimitiveExecutionResult {
  final bool ok;                        // false if any step failed
  final List<PrimitiveResult> stepResults;
  final String? errorMessage;           // set if execution aborted mid-run
  final int? failedAtStep;              // 0-indexed step index that failed
}
```

### PrimitiveState

```dart
enum PrimitiveState { idle, running, error }
```

---

## Primitive Inventory

| Primitive | Required args | Optional args | Returns (in `data`) |
|---|---|---|---|
| `open_app` | `package: String` | — | — |
| `tap` | one of `selector` or `x`+`y` | `selector: String`, `x: int`, `y: int` | — |
| `type` | `text: String` | — | — |
| `scroll` | `direction: up\|down\|left\|right` | `amount: int` (default 3 swipes) | — |
| `swipe` | `fromX: int`, `fromY: int`, `toX: int`, `toY: int` | — | — |
| `back` | — | — | — |
| `read_screen` | — | — | `tree: String` (text representation of accessibility node tree) |
| `read_clipboard` | — | — | `text: String` |
| `take_screenshot` | — | — | `path: String` (absolute path to PNG in app cache dir) |

**Tap selector resolution order:**
1. `findAccessibilityNodeInfosByText(selector)` — exact or partial text match
2. `findAccessibilityNodeInfosByViewId(selector)` — resource ID match
3. `findAccessibilityNodeInfosByContentDescription(selector)` — content description match
4. Fail with `ok: false, message: "Element not found: <selector>"`

---

## PrimitiveEngine Service API

```dart
class PrimitiveEngine {
  PrimitiveEngine._();
  static final PrimitiveEngine instance = PrimitiveEngine._();

  final ValueNotifier<PrimitiveState> _state =
      ValueNotifier(PrimitiveState.idle);
  ValueListenable<PrimitiveState> get state => _state;

  PrimitiveExecutionResult? _lastResult;
  PrimitiveExecutionResult? get lastResult => _lastResult;

  // Execute steps in order. Stops on first failure.
  // Returns immediately with error if accessibility is not enabled.
  Future<PrimitiveExecutionResult> execute(List<PrimitiveStep> steps) async { ... }

  // Parse a raw skill JSON map into a step list.
  // Throws ArgumentError on unknown primitive or missing required arg.
  static List<PrimitiveStep> fromJson(Map<String, dynamic> json) { ... }

  // Returns true if PocketClawAccessibilityService is running.
  Future<bool> isAccessibilityEnabled() async { ... }

  // Opens Android Settings > Accessibility so user can enable the service.
  Future<void> openAccessibilitySettings() async { ... }
}
```

**Execution contract:**
- Sets `PrimitiveState.running` at start, `PrimitiveState.idle` on success, `PrimitiveState.error` on failure
- Per-step timeout: **5 seconds** (Kotlin must respond within 5s or step fails with `"timeout"`)
- On step failure: stops execution, sets `PrimitiveState.error`, stores result in `lastResult`
- `execute()` is **not re-entrant** — returns `PrimitiveExecutionResult(ok: false, errorMessage: "Already running")` if called while `state.value == PrimitiveState.running`

---

## Kotlin: PocketClawAccessibilityService

**File:** `android/app/src/main/kotlin/com/manuraksh/pocketclaw/PocketClawAccessibilityService.kt`

Extends `AccessibilityService`. Registers a `MethodChannel` handler in `onServiceConnected()`.

```kotlin
class PocketClawAccessibilityService : AccessibilityService() {
  companion object {
    const val CHANNEL = "pocketclaw/accessibility"
    var instance: PocketClawAccessibilityService? = null  // set in onServiceConnected
  }

  override fun onServiceConnected() {
    instance = this
    // MethodChannel registered here via FlutterEngine stored in MainActivity
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent) { /* required override */ }
  override fun onInterrupt() { instance = null }
}
```

**MethodChannel handlers:**

| Method | Kotlin implementation |
|---|---|
| `tap` | Resolve node via selector or coords → `performAction(ACTION_CLICK)` or `GestureDescription` tap |
| `type` | `findFocus(FOCUS_INPUT)` → `ACTION_SET_TEXT` with `Bundle(ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)` |
| `scroll` | Root node → `ACTION_SCROLL_FORWARD` or `ACTION_SCROLL_BACKWARD` |
| `swipe` | `GestureDescription.Builder().addStroke(...)` → `dispatchGesture()` |
| `back` | `performGlobalAction(GLOBAL_ACTION_BACK)` |
| `read_screen` | Walk `rootInActiveWindow`, serialize to text (`className: text [resourceId]` per node) |
| `isEnabled` | Return `instance != null` |

`open_app`, `read_clipboard`, `take_screenshot` are handled by the existing `pocketclaw/device` channel in `MainActivity.kt` — the Dart `PrimitiveEngine` routes these calls there directly.

---

## AndroidManifest Changes

```xml
<!-- In AndroidManifest.xml -->
<service
  android:name=".PocketClawAccessibilityService"
  android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
  android:exported="true">
  <intent-filter>
    <action android:name="android.accessibilityservice.AccessibilityService" />
  </intent-filter>
  <meta-data
    android:name="android.accessibilityservice"
    android:resource="@xml/accessibility_service_config" />
</service>
```

**New file:** `android/app/src/main/res/xml/accessibility_service_config.xml`

```xml
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
  android:accessibilityEventTypes="typeAllMask"
  android:accessibilityFeedbackType="feedbackGeneric"
  android:accessibilityFlags="flagRetrieveInteractiveWindows|flagReportViewIds"
  android:canPerformGestures="true"
  android:canRetrieveWindowContent="true"
  android:description="@string/accessibility_service_description"
  android:notificationTimeout="100" />
```

Add to `strings.xml`:
```xml
<string name="accessibility_service_description">
  PocketClaw uses accessibility to read the screen and perform actions on your behalf.
</string>
```

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| AccessibilityService not enabled | `execute()` returns `ok: false, errorMessage: "Accessibility permission required"`. Widget shows prompt + "Enable now" CTA calling `openAccessibilitySettings()`. |
| Step times out (>5s) | Step result: `ok: false, message: "timeout"`. Execution stops. |
| Selector not found | Step result: `ok: false, message: "Element not found: <selector>"`. Execution stops. |
| Unknown primitive in JSON | `fromJson()` throws `ArgumentError`. Caller must handle before calling `execute()`. |
| Missing required arg | `fromJson()` throws `ArgumentError` with field name. |
| `execute()` called while running | Returns immediately: `ok: false, errorMessage: "Already running"`. |
| Kotlin throws PlatformException | Caught in Dart; maps to `ok: false, message: exception.message`. |

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `lib/services/primitive_engine/primitive_models.dart` | Create | Data types: PrimitiveStep, PrimitiveResult, PrimitiveExecutionResult, PrimitiveState |
| `lib/services/primitive_engine/primitive_engine.dart` | Create | Dart singleton service |
| `android/app/src/main/kotlin/com/manuraksh/pocketclaw/PocketClawAccessibilityService.kt` | Create | Kotlin AccessibilityService |
| `android/app/src/main/res/xml/accessibility_service_config.xml` | Create | Accessibility config |
| `android/app/src/main/res/values/strings.xml` | Modify | Add accessibility_service_description |
| `android/app/src/main/AndroidManifest.xml` | Modify | Register PocketClawAccessibilityService |
| `test/services/primitive_engine/primitive_models_test.dart` | Create | Model parsing + validation tests |
| `test/services/primitive_engine/primitive_engine_test.dart` | Create | Executor + MethodChannel mock tests |

---

## Testing

### Unit tests — `primitive_models_test.dart`
- `fromJson()` parses all 9 primitives correctly
- `fromJson()` throws `ArgumentError` on unknown primitive
- `fromJson()` throws `ArgumentError` on missing required arg (e.g. `tap` with no selector or coords)
- `PrimitiveExecutionResult` correctly reports `ok: false` when any step failed

### Integration tests — `primitive_engine_test.dart`
Using `TestDefaultBinaryMessengerBinding` to mock `pocketclaw/accessibility` channel:

- `execute()` dispatches correct channel call for each of the 9 primitives
- `execute()` sets `PrimitiveState.running` during execution, `idle` after success
- `execute()` sets `PrimitiveState.error` and stops on first failed step
- `execute()` returns early with error if `isAccessibilityEnabled()` returns false
- `execute()` returns early with error if called while already running
- Timeout: step returning after 5s threshold produces `ok: false, message: "timeout"`

---

## Usage Example (from ChatCommandService / future SkillEngine)

```dart
// 1. Check accessibility is enabled
if (!await PrimitiveEngine.instance.isAccessibilityEnabled()) {
  // Show prompt — widget calls openAccessibilitySettings()
  return 'Please enable PocketClaw in Accessibility Settings first.';
}

// 2. Parse skill JSON (from Gemma output or hardcoded skill)
final steps = PrimitiveEngine.fromJson({
  "steps": [
    {"primitive": "open_app", "args": {"package": "com.swiggy.android"}},
    {"primitive": "tap",      "args": {"selector": "Search for restaurants"}},
    {"primitive": "type",     "args": {"text": "coffee"}},
    {"primitive": "read_screen"}
  ]
});

// 3. Execute
final result = await PrimitiveEngine.instance.execute(steps);

if (!result.ok) {
  return 'Action failed at step ${result.failedAtStep}: ${result.errorMessage}';
}

// 4. Use the screen tree from read_screen
final tree = result.stepResults[3].data['tree'] as String;
// pass tree back to Gemma for next decision in Agent Loop
```

---

## What This Unlocks

With Phase 1a complete:
- Any skill can be expressed as a JSON step list
- Gemma can generate skill steps natively (it outputs JSON)
- Phase 1b (Overlay + Context Engine) can invoke `PrimitiveEngine.instance.execute()` directly
- Phase 2 (Skill DSL + Registry) is just structured storage of step lists
- Phase 3 (Agent Loop) wraps `execute()` + `read_screen` in an observe-act loop

---

## Out of Scope (flagged in CLAUDE.md)

Per `CLAUDE.md` Universal Don'ts and out-of-scope list: do not implement Memory Engine, Workflow Engine, Agent Loop, Dynamic UI, or Skill Marketplace as part of this spec. The `services/primitive_engine/` directory exists and is no longer empty after this phase.
