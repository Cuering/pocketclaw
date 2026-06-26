# Phase 1b — Overlay + Context Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the pre-scaffolded floating overlay bubble and build a ContextEngine service that captures the foreground app and screen tree, injecting this context into voice commands so Gemma gives context-aware responses from the overlay.

**Architecture:** `ContextEngine` (new singleton) calls `PrimitiveEngine.execute([read_screen])` + a new `getContext` Kotlin method in parallel, produces a `ContextSnapshot`, and `VoiceService._processCommand` prepends a `[Device Context]` block to the Gemma prompt. The overlay is already fully UI-scaffolded inside a `/* */` block in `main.dart`; activation is primarily uncommenting pubspec, imports, `OverlayControllerService`, and `AndroidManifest` entries.

**Tech Stack:** Flutter/Dart, Kotlin, `flutter_overlay_window ^0.5.0`, `MethodChannel('pocketclaw/accessibility')`, `PrimitiveEngine` (Phase 1a, already built and tested)

## Global Constraints

- Flutter/Dart + Kotlin, Android only — no iOS
- Singleton pattern: `static final XxxService instance = XxxService._();`
- `ValueListenable<T>` state — never Riverpod, Provider, or BLoC
- Colors/typography from `PocketClawTheme` tokens only — never `Color(0xFF...)` inline
- `flutter test` must pass before every commit
- Android package name: `com.pocketclaw.pocketclaw`
- Accessibility MethodChannel name: `'pocketclaw/accessibility'`
- `ContextEngine.capture()` must never throw — all error paths return an empty `ContextSnapshot`
- `getContext` Kotlin method added to `PocketClawAccessibilityService.handleCall()` — `MainActivity` already routes unknown methods there via its `else` branch, no `MainActivity` change needed

---

### Task 1: ContextSnapshot model + ContextEngine service + unit tests

**Files:**
- Create: `lib/services/context_engine/context_snapshot.dart`
- Create: `lib/services/context_engine/context_engine.dart`
- Create: `test/services/context_engine/context_engine_test.dart`

**Interfaces:**
- Produces (consumed by Task 4): `ContextEngine.instance.capture() → Future<ContextSnapshot>` and `ContextEngine.instance.formatForPrompt(ContextSnapshot) → String`
- Consumes (already built): `PrimitiveEngine.instance.isAccessibilityEnabled() → Future<bool>` and `PrimitiveEngine.instance.execute(List<PrimitiveStep>) → Future<PrimitiveExecutionResult>`
- Consumes (built in Task 2): `MethodChannel('pocketclaw/accessibility').invokeMethod('getContext')` returns `Map<dynamic, dynamic>` with nullable-String values for keys `'package'` and `'appName'`

- [ ] **Step 1: Write failing tests**

Create `test/services/context_engine/context_engine_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/context_engine/context_engine.dart';
import 'package:pocketclaw/services/context_engine/context_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('pocketclaw/accessibility'),
      null,
    );
  });

  void mockChannel(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('pocketclaw/accessibility'),
      handler,
    );
  }

  // ── ContextSnapshot ────────────────────────────────────────────────────

  group('ContextSnapshot', () {
    test('hasContext is false when all fields null', () {
      final snap = ContextSnapshot(
        accessibilityAvailable: false,
        capturedAt: DateTime.now(),
      );
      expect(snap.hasContext, isFalse);
    });

    test('hasContext is true when foregroundPackage is set', () {
      final snap = ContextSnapshot(
        foregroundPackage: 'com.test.app',
        accessibilityAvailable: true,
        capturedAt: DateTime.now(),
      );
      expect(snap.hasContext, isTrue);
    });

    test('hasContext is true when screenTree is set', () {
      final snap = ContextSnapshot(
        screenTree: 'some tree',
        accessibilityAvailable: true,
        capturedAt: DateTime.now(),
      );
      expect(snap.hasContext, isTrue);
    });
  });

  // ── ContextEngine.capture() ────────────────────────────────────────────

  group('ContextEngine.capture()', () {
    test('returns all-null snapshot when accessibility disabled', () async {
      mockChannel((call) async {
        if (call.method == 'isEnabled') return false;
        return null;
      });

      final snap = await ContextEngine.instance.capture();

      expect(snap.accessibilityAvailable, isFalse);
      expect(snap.foregroundPackage, isNull);
      expect(snap.foregroundAppName, isNull);
      expect(snap.screenTree, isNull);
    });

    test('returns full snapshot when accessibility enabled', () async {
      mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        if (call.method == 'getContext') {
          return {'package': 'com.swiggy.android', 'appName': 'Swiggy'};
        }
        if (call.method == 'readScreen') {
          return {'tree': 'Button: Order Now'};
        }
        return null;
      });

      final snap = await ContextEngine.instance.capture();

      expect(snap.accessibilityAvailable, isTrue);
      expect(snap.foregroundPackage, 'com.swiggy.android');
      expect(snap.foregroundAppName, 'Swiggy');
      expect(snap.screenTree, contains('Button'));
    });

    test('snapshot has null screenTree when readScreen returns null', () async {
      mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        if (call.method == 'getContext') {
          return {'package': 'com.test.app', 'appName': 'TestApp'};
        }
        if (call.method == 'readScreen') return null;
        return null;
      });

      final snap = await ContextEngine.instance.capture();

      expect(snap.foregroundPackage, 'com.test.app');
      expect(snap.screenTree, isNull);
    });

    test('never throws — returns empty snapshot on channel exception', () async {
      mockChannel((call) async {
        throw PlatformException(code: 'ERROR', message: 'channel error');
      });

      final snap = await ContextEngine.instance.capture();

      expect(snap.accessibilityAvailable, isFalse);
      expect(snap.hasContext, isFalse);
    });
  });

  // ── ContextEngine.formatForPrompt() ───────────────────────────────────

  group('ContextEngine.formatForPrompt()', () {
    test('returns empty string when no context', () {
      final snap = ContextSnapshot(
        accessibilityAvailable: false,
        capturedAt: DateTime.now(),
      );
      expect(ContextEngine.instance.formatForPrompt(snap), isEmpty);
    });

    test('formats full snapshot with app name and screen tree', () {
      final snap = ContextSnapshot(
        foregroundPackage: 'com.swiggy.android',
        foregroundAppName: 'Swiggy',
        screenTree: 'Button: Order Now',
        accessibilityAvailable: true,
        capturedAt: DateTime.now(),
      );
      final result = ContextEngine.instance.formatForPrompt(snap);
      expect(result, contains('[Device Context]'));
      expect(result, contains('Swiggy'));
      expect(result, contains('com.swiggy.android'));
      expect(result, contains('Button: Order Now'));
    });

    test('formats snapshot with package only — no screen content section', () {
      final snap = ContextSnapshot(
        foregroundPackage: 'com.test.app',
        foregroundAppName: 'TestApp',
        accessibilityAvailable: true,
        capturedAt: DateTime.now(),
      );
      final result = ContextEngine.instance.formatForPrompt(snap);
      expect(result, contains('TestApp'));
      expect(result, isNot(contains('Screen content')));
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
flutter test test/services/context_engine/context_engine_test.dart
```

Expected: FAIL — `'package:pocketclaw/services/context_engine/context_engine.dart'` not found.

- [ ] **Step 3: Create ContextSnapshot**

Create `lib/services/context_engine/context_snapshot.dart`:

```dart
class ContextSnapshot {
  final String? foregroundPackage;
  final String? foregroundAppName;
  final String? screenTree;
  final bool accessibilityAvailable;
  final DateTime capturedAt;

  const ContextSnapshot({
    this.foregroundPackage,
    this.foregroundAppName,
    this.screenTree,
    required this.accessibilityAvailable,
    required this.capturedAt,
  });

  bool get hasContext => foregroundPackage != null || screenTree != null;
}
```

- [ ] **Step 4: Create ContextEngine**

Create `lib/services/context_engine/context_engine.dart`:

```dart
import 'dart:async';

import 'package:flutter/services.dart';

import '../primitive_engine/primitive_engine.dart';
import '../primitive_engine/primitive_models.dart';
import 'context_snapshot.dart';

class ContextEngine {
  ContextEngine._();
  static final ContextEngine instance = ContextEngine._();

  static const _channel = MethodChannel('pocketclaw/accessibility');

  /// Captures foreground app + screen tree with fallback.
  ///   Accessibility enabled  → foregroundPackage + foregroundAppName + screenTree
  ///   Accessibility disabled → all-null snapshot, accessibilityAvailable: false
  /// Never throws.
  Future<ContextSnapshot> capture() async {
    try {
      final accessible =
          await PrimitiveEngine.instance.isAccessibilityEnabled();
      if (!accessible) {
        return ContextSnapshot(
          accessibilityAvailable: false,
          capturedAt: DateTime.now(),
        );
      }

      final results = await Future.wait([
        PrimitiveEngine.instance.execute([
          const PrimitiveStep(primitive: 'read_screen'),
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

  Future<Map<String, String?>> _getContext() async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getContext')
          .timeout(const Duration(seconds: 3));
      if (raw == null) return {};
      return {
        'package': raw['package'] as String?,
        'appName': raw['appName'] as String?,
      };
    } on PlatformException {
      return {};
    } on TimeoutException {
      return {};
    }
  }

  /// Produces a `[Device Context]…[/Device Context]` block for Gemma.
  /// Returns empty string if snapshot has no context.
  String formatForPrompt(ContextSnapshot snapshot) {
    if (!snapshot.hasContext) return '';

    final buf = StringBuffer('[Device Context]\n');
    if (snapshot.foregroundAppName != null) {
      buf.writeln(
        'Current app: ${snapshot.foregroundAppName} (${snapshot.foregroundPackage})',
      );
    }
    if (snapshot.screenTree != null && snapshot.screenTree!.isNotEmpty) {
      buf.writeln('Screen content:\n${snapshot.screenTree}');
    }
    buf.write('[/Device Context]');
    return buf.toString();
  }
}
```

- [ ] **Step 5: Run tests — expect all 10 to pass**

```bash
flutter test test/services/context_engine/context_engine_test.dart
```

Expected: `+10: All tests passed!`

- [ ] **Step 6: Run full suite**

```bash
flutter test
```

Expected: all tests pass (includes the 47 from Phase 1a).

- [ ] **Step 7: Commit**

```bash
git add lib/services/context_engine/ test/services/context_engine/
git commit -m "feat(context-engine): add ContextSnapshot model and ContextEngine service"
```

---

### Task 2: Kotlin getContext handler

**Files:**
- Modify: `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt`

**Interfaces:**
- Produces: channel method `getContext` — returns `Map<String, String?>` with keys `'package'` (app package name) and `'appName'` (human-readable label from PackageManager); both nullable
- `MainActivity` already routes unknown methods via its `else` branch to `service.handleCall()` — no `MainActivity.kt` change required

There are no Dart unit tests for Kotlin. The compile check is `flutter test`. Device verification happens after Task 3.

- [ ] **Step 1: Verify imports in PocketClawAccessibilityService.kt**

Open `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt`.

Ensure these imports are present (add if missing):

```kotlin
import android.content.pm.PackageManager
import android.os.Build
```

- [ ] **Step 2: Add handleGetContext private method**

Add the following private method after `handleTakeScreenshot` (or any other `handle*` method at the end of the class):

```kotlin
private fun handleGetContext(result: MethodChannel.Result) {
    val root = rootInActiveWindow
    if (root == null) {
        result.success(mapOf("package" to null, "appName" to null))
        return
    }
    val packageName = root.packageName?.toString()
    root.recycle()
    val appName: String? = try {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getApplicationInfo(
                packageName ?: "",
                PackageManager.ApplicationInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getApplicationInfo(packageName ?: "", 0)
        }
        packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        packageName
    }
    result.success(mapOf("package" to packageName, "appName" to appName))
}
```

- [ ] **Step 3: Route getContext in handleCall**

Inside `handleCall(call: MethodCall, result: MethodChannel.Result)`, add the new case inside the `when(call.method)` block — place it before the final `else ->` branch:

```kotlin
"getContext" -> handleGetContext(result)
```

- [ ] **Step 4: Run flutter test (compile + Dart check)**

```bash
flutter test
```

Expected: all tests pass. (Kotlin compilation is verified on device build; `flutter test` confirms no Dart regressions.)

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt
git commit -m "feat(context-engine): add getContext handler to Kotlin AccessibilityService"
```

---

### Task 3: Activate overlay

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/services/overlay_controller_service.dart`
- Modify: `lib/main.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/screens/onboarding_screen.dart`
- Modify: `lib/screens/chat_screen.dart`

**Interfaces:**
- Produces: working `FlutterOverlayWindow` bubble — appears when app goes to background (if user enabled it in settings)
- Produces: `OverlayControllerService.instance.setEnabled(bool)` — fully functional (was no-op stub)
- Produces: `OverlayControllerService.instance.showIfEnabled()` — shows bubble
- Produces: `OverlayControllerService.instance.hide()` — hides bubble and collapses it

- [ ] **Step 1: Uncomment flutter_overlay_window in pubspec.yaml**

Open `pubspec.yaml`. Change:
```yaml
  # flutter_overlay_window: ^0.5.0
```
to:
```yaml
  flutter_overlay_window: ^0.5.0
```

Then run:
```bash
flutter pub get
```

Expected: resolves without error, `flutter_overlay_window` appears in the package graph.

- [ ] **Step 2: Restore OverlayControllerService**

Open `lib/services/overlay_controller_service.dart`. Replace the entire file content with:

```dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';

import 'prefs_service.dart';

class OverlayControllerService {
  OverlayControllerService._();
  static final OverlayControllerService instance = OverlayControllerService._();

  Future<void> writeState(bool enabled) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/overlay_enabled.json');
      await file.writeAsString(enabled ? 'true' : 'false');
      debugPrint('🐾 OVERLAY: wrote cross-isolate state: $enabled');
    } catch (e, stack) {
      debugPrint('🐾 OVERLAY: failed to write state: $e\n$stack');
    }
  }

  Future<bool> readState() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/overlay_enabled.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return content.trim() == 'true';
      }
    } catch (e, stack) {
      debugPrint('🐾 OVERLAY: failed to read state: $e\n$stack');
    }
    return false;
  }

  Future<bool> ensurePermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (granted) return true;
    await FlutterOverlayWindow.requestPermission();
    return FlutterOverlayWindow.isPermissionGranted();
  }

  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      final granted = await ensurePermission();
      if (!granted) return false;
    } else {
      await hide();
    }
    await writeState(enabled);
    final current = PrefsService.instance.current;
    await PrefsService.instance.update(
      current.copyWith(overlayEnabled: enabled),
    );
    return enabled;
  }

  Future<void> showIfEnabled() async {
    final fileEnabled = await readState();
    if (!fileEnabled) return;
    try {
      if (await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        height: 80,
        width: 80,
        alignment: OverlayAlignment.centerRight,
        overlayTitle: 'PocketClaw',
        overlayContent: 'Claw is ready',
        flag: OverlayFlag.focusPointer,
        positionGravity: PositionGravity.auto,
        visibility: NotificationVisibility.visibilityPublic,
      );
      debugPrint('🐾 OVERLAY: showed bubble in collapsed 80x80 mode');
    } catch (e, stack) {
      debugPrint('🐾 OVERLAY: show failed: $e\n$stack');
    }
  }

  Future<void> hide() async {
    try {
      final port =
          IsolateNameServer.lookupPortByName('pocketclaw_overlay_port');
      port?.send({'command': 'collapse'});

      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (e, stack) {
      debugPrint('🐾 OVERLAY: hide failed: $e\n$stack');
    }
  }

  Future<void> markDisabledFromOverlay() async {
    await hide();
    await writeState(false);
    final current = PrefsService.instance.current;
    await PrefsService.instance.update(
      current.copyWith(overlayEnabled: false),
    );
  }
}
```

- [ ] **Step 3: Activate overlay isolate in main.dart**

Open `lib/main.dart`.

**3a — Uncomment four import lines** (remove the leading `//`):

```dart
import 'dart:isolate';
import 'dart:ui';
```
and:
```dart
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
```
and:
```dart
import 'services/device_actions_service.dart';
```
and:
```dart
import 'services/overlay_controller_service.dart';
```

**3b — Remove the block-comment markers.** Find `/*` on the line just before the `// ─── OVERLAY ISOLATE ───` section header, and the matching `*/` at the very end of the `_OverlayIconButton` class. Delete just those two markers, leaving all the code inside intact.

**3c — Add the missing `_buildExpanded()` method.** Inside `_ClawBubbleState`, after the `_buildBubbleIcon()` method and before `_voicePanel()`, insert:

```dart
Widget _buildExpanded() {
  if (_listening || _thinking || _responseSpeechText != null) {
    return _voicePanel();
  }
  return _expandedPanel();
}
```

- [ ] **Step 4: Uncomment AndroidManifest entries**

Open `android/app/src/main/AndroidManifest.xml`.

**4a — Uncomment SYSTEM_ALERT_WINDOW** (remove `<!-- ` and ` -->`):
```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```

**4b — Uncomment the OverlayService block** (remove `<!-- ` and ` -->`):
```xml
<service
    android:name="flutter.overlay.window.flutter_overlay_window.OverlayService"
    android:exported="false"
    android:foregroundServiceType="specialUse|microphone">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="PocketClaw's floating assistant overlay — provides a draggable bubble for quick on-device AI access over other apps."/>
</service>
```

- [ ] **Step 5: Uncomment overlay permission in OnboardingScreen**

Open `lib/screens/onboarding_screen.dart`.

**5a —** Uncomment the two commented imports at the top:
```dart
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
```
```dart
import '../services/overlay_controller_service.dart';
```

**5b —** In `_checkPermissions()`, replace:
```dart
    // final overlay = await FlutterOverlayWindow.isPermissionGranted();
    const overlay = false;
```
with:
```dart
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
```

**5c —** Remove the `// ignore: unused_field` comment above `bool _overlayGranted = false;` (it is now used).

**5d —** Uncomment `_grantOverlay()`:
```dart
Future<void> _grantOverlay() async {
  await OverlayControllerService.instance.ensurePermission();
  await _checkPermissions();
}
```

**5e —** Uncomment the Display Over Apps `_PermissionRow` in `build()`. Place it as the **first** row (above Microphone), and add a `SizedBox(height: 12)` between it and the next row:
```dart
_PermissionRow(
  icon: Icons.open_in_new,
  title: 'Display Over Apps',
  description: 'Draw the floating bubble overlay.',
  granted: _overlayGranted,
  onGrant: _grantOverlay,
),
const SizedBox(height: 12),
```

- [ ] **Step 6: Uncomment overlay toggle in ChatScreen**

Open `lib/screens/chat_screen.dart`.

**6a —** Uncomment the FlutterOverlayWindow import near the top:
```dart
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
```

**6b —** Uncomment `_setOverlayEnabled` in `_ChatScreenState`. Find the commented block around line 1276 and restore it as:
```dart
Future<void> _setOverlayEnabled(bool enabled) async {
  final applied = await OverlayControllerService.instance.setEnabled(enabled);
  if (!mounted) return;
  setState(() {});
  if (!applied && enabled) {
    _showSnack('Display Over Apps permission required.');
  }
}
```

**6c —** In the body `Column` (around line 1329), uncomment the `_OverlayPreferenceCard` usage:
```dart
_OverlayPreferenceCard(
  enabled: PrefsService.instance.current.overlayEnabled,
  onChanged: _setOverlayEnabled,
),
```

**6d —** Find the `_OverlayPreferenceCard` class definition (around line 1597, currently inside a `//` block) and uncomment the entire class.

- [ ] **Step 7: Run full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml \
    lib/main.dart \
    lib/services/overlay_controller_service.dart \
    android/app/src/main/AndroidManifest.xml \
    lib/screens/onboarding_screen.dart \
    lib/screens/chat_screen.dart
git commit -m "feat(overlay): activate FlutterOverlayWindow bubble and wire permissions"
```

---

### Task 4: Wire ContextEngine into VoiceService

**Files:**
- Modify: `lib/services/voice_service.dart`

**Interfaces:**
- Consumes (Task 1): `ContextEngine.instance.capture() → Future<ContextSnapshot>`
- Consumes (Task 1): `ContextEngine.instance.formatForPrompt(ContextSnapshot) → String`

- [ ] **Step 1: Add ContextEngine import**

Open `lib/services/voice_service.dart`. Add with the other service imports:

```dart
import 'context_engine/context_engine.dart';
```

- [ ] **Step 2: Inject context in _processCommand**

Find `_processCommand(String commandText)` and replace its entire body with the following (keep the method signature unchanged):

```dart
Future<void> _processCommand(String commandText) async {
  try {
    debugPrint('🐾 VOICE SERVICE: processing command: "$commandText"');

    final snapshot = await ContextEngine.instance.capture();
    final contextPrefix = ContextEngine.instance.formatForPrompt(snapshot);

    final executionReport =
        await ChatCommandService.instance.tryHandleWithGemma(commandText);

    String reply;
    if (executionReport != null) {
      reply = executionReport;
    } else {
      final now = DateTime.now();
      final localContext =
          'Today is ${now.day}/${now.month}/${now.year}. Standard time: ${now.hour}:${now.minute}. '
          'The user asked you a voice command outside the app. Give a brief, direct answer (under 2 sentences) suitable for a voice readout.';

      final fullPrompt = contextPrefix.isNotEmpty
          ? '$contextPrefix\n\n$localContext\n\nUser: "$commandText"'
          : '$localContext\n\nUser request: "$commandText"';

      reply = await GemmaService.instance.generate(
        fullPrompt,
        userName: PrefsService.instance.current.name,
      );
    }

    await _persistVoiceTurn(commandText, reply);

    _sendToOverlay({'command': 'response', 'text': reply});
    _state = VoiceState.speaking;
    _notify();

    await Future<void>.delayed(const Duration(seconds: 5));
    _sendToOverlay({'command': 'done'});

    _state = VoiceState.checkingWakeWord;
    _notify();
    _handleSttStopped();
  } catch (e, stack) {
    debugPrint('🐾 VOICE SERVICE: process failed: $e\n$stack');
    _sendToOverlay({
      'command': 'response',
      'text': 'Sorry, something went wrong offline.',
    });
    await Future<void>.delayed(const Duration(seconds: 4));
    _sendToOverlay({'command': 'done'});
    _state = VoiceState.checkingWakeWord;
    _notify();
    _handleSttStopped();
  }
}
```

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/services/voice_service.dart
git commit -m "feat(context-engine): inject screen context into overlay voice commands"
```
