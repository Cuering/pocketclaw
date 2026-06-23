# Primitive Engine (Phase 1a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PrimitiveEngine Dart singleton and PocketClawAccessibilityService Kotlin service that execute 9 JSON-driven UI primitives (tap, type, scroll, swipe, back, read_screen, open_app, read_clipboard, take_screenshot) on Android.

**Architecture:** PrimitiveEngine parses a `List<PrimitiveStep>` from JSON and executes each step via `MethodChannel('pocketclaw/accessibility')`. The channel is registered in `MainActivity.configureFlutterEngine()` — same pattern as the existing `pocketclaw/device` channel. The Kotlin `PocketClawAccessibilityService` holds a static `instance` reference; the channel handler in MainActivity checks `instance != null` for `isEnabled` and delegates all primitive calls to `instance.handleCall()`.

**Tech Stack:** Flutter/Dart, Kotlin, Android AccessibilityService API, MethodChannel, flutter_test with `TestDefaultBinaryMessengerBinding` for MethodChannel mocking.

## Global Constraints

- Kotlin package: `com.pocketclaw.pocketclaw` (matches existing `MainActivity.kt`)
- Accessibility channel name: `pocketclaw/accessibility` (separate from existing `pocketclaw/device`)
- Singleton pattern: `XxxService._()` private constructor, `static final XxxService instance = XxxService._()`
- State exposed as: `ValueListenable<PrimitiveState> get state => _state`
- Per-step timeout: `Duration(seconds: 5)` — Dart side enforces via `Future.timeout()`
- `execute()` not re-entrant: set `_state.value = PrimitiveState.running` before the first `await`; return `ok: false, errorMessage: 'Already running'` if already running
- `PrimitiveStep.fromJson()` throws `ArgumentError` on unknown primitive or missing required arg
- `PrimitiveEngine.fromJson()` throws `ArgumentError` if `steps` key is missing
- `flutter test` must pass before any commit — run from the project root

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/services/primitive_engine/primitive_models.dart` | Create | `PrimitiveState`, `PrimitiveStep`, `PrimitiveResult`, `PrimitiveExecutionResult` |
| `lib/services/primitive_engine/primitive_engine.dart` | Create | Dart singleton: JSON executor, state machine, MethodChannel calls |
| `test/services/primitive_engine/primitive_models_test.dart` | Create | Unit tests for model parsing and validation |
| `test/services/primitive_engine/primitive_engine_test.dart` | Create | Integration tests with mocked `pocketclaw/accessibility` channel |
| `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt` | Create | Kotlin AccessibilityService — all 9 primitives + static `instance` |
| `android/app/src/main/res/xml/accessibility_service_config.xml` | Create | AccessibilityService capabilities declaration |
| `android/app/src/main/res/values/strings.xml` | Create | `accessibility_service_description` string (file does not exist yet) |
| `android/app/src/main/AndroidManifest.xml` | Modify | Register `PocketClawAccessibilityService` inside `<application>` |
| `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/MainActivity.kt` | Modify | Register `pocketclaw/accessibility` channel in `configureFlutterEngine()` |

---

### Task 1: Primitive Data Models

**Files:**
- Create: `lib/services/primitive_engine/primitive_models.dart`
- Create: `test/services/primitive_engine/primitive_models_test.dart`

**Interfaces:**
- Produces:
  - `enum PrimitiveState { idle, running, error }`
  - `class PrimitiveStep { final String primitive; final Map<String, dynamic> args; factory PrimitiveStep.fromJson(Map<String, dynamic> json); }`
  - `class PrimitiveResult { final bool ok; final String message; final Map<String, dynamic> data; }`
  - `class PrimitiveExecutionResult { final bool ok; final List<PrimitiveResult> stepResults; final String? errorMessage; final int? failedAtStep; }`
- Consumed by: Task 2 (`primitive_engine.dart`)

---

- [ ] **Step 1: Write the failing tests**

Create `test/services/primitive_engine/primitive_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  group('PrimitiveStep.fromJson', () {
    test('parses open_app', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'open_app',
        'args': {'package': 'com.example.app'},
      });
      expect(step.primitive, 'open_app');
      expect(step.args['package'], 'com.example.app');
    });

    test('parses tap with selector', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'tap',
        'args': {'selector': 'Search'},
      });
      expect(step.primitive, 'tap');
      expect(step.args['selector'], 'Search');
    });

    test('parses tap with coordinates', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'tap',
        'args': {'x': 100, 'y': 200},
      });
      expect(step.args['x'], 100);
      expect(step.args['y'], 200);
    });

    test('parses type', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'type',
        'args': {'text': 'hello world'},
      });
      expect(step.args['text'], 'hello world');
    });

    test('parses scroll', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'scroll',
        'args': {'direction': 'down'},
      });
      expect(step.args['direction'], 'down');
    });

    test('parses swipe', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'swipe',
        'args': {'fromX': 100, 'fromY': 200, 'toX': 300, 'toY': 400},
      });
      expect(step.args['fromX'], 100);
      expect(step.args['toY'], 400);
    });

    test('parses back with no args', () {
      final step = PrimitiveStep.fromJson({'primitive': 'back'});
      expect(step.primitive, 'back');
      expect(step.args, isEmpty);
    });

    test('parses read_screen with no args', () {
      final step = PrimitiveStep.fromJson({'primitive': 'read_screen'});
      expect(step.primitive, 'read_screen');
    });

    test('parses read_clipboard with no args', () {
      final step = PrimitiveStep.fromJson({'primitive': 'read_clipboard'});
      expect(step.primitive, 'read_clipboard');
    });

    test('parses take_screenshot with no args', () {
      final step = PrimitiveStep.fromJson({'primitive': 'take_screenshot'});
      expect(step.primitive, 'take_screenshot');
    });

    test('throws ArgumentError for unknown primitive', () {
      expect(
        () => PrimitiveStep.fromJson({'primitive': 'fly', 'args': {}}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for missing primitive key', () {
      expect(
        () => PrimitiveStep.fromJson({'args': {}}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: open_app without package', () {
      expect(
        () => PrimitiveStep.fromJson({'primitive': 'open_app', 'args': {}}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: tap without selector or coords', () {
      expect(
        () => PrimitiveStep.fromJson({'primitive': 'tap', 'args': {}}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: tap with x but no y', () {
      expect(
        () => PrimitiveStep.fromJson({
          'primitive': 'tap',
          'args': {'x': 100},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: type without text', () {
      expect(
        () => PrimitiveStep.fromJson({'primitive': 'type', 'args': {}}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: scroll with invalid direction', () {
      expect(
        () => PrimitiveStep.fromJson({
          'primitive': 'scroll',
          'args': {'direction': 'diagonal'},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: scroll without direction', () {
      expect(
        () => PrimitiveStep.fromJson({'primitive': 'scroll', 'args': {}}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError: swipe missing fromX', () {
      expect(
        () => PrimitiveStep.fromJson({
          'primitive': 'swipe',
          'args': {'fromY': 200, 'toX': 300, 'toY': 400},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PrimitiveResult', () {
    test('ok result has ok: true', () {
      const result = PrimitiveResult(ok: true, message: 'done');
      expect(result.ok, isTrue);
      expect(result.data, isEmpty);
    });

    test('read_screen result carries tree in data', () {
      const result = PrimitiveResult(
        ok: true,
        message: 'Screen read',
        data: {'tree': 'Button: Search\nEditText: [search_box]'},
      );
      expect(result.data['tree'], contains('Button'));
    });
  });

  group('PrimitiveExecutionResult', () {
    test('ok: false when failedAtStep is set', () {
      const result = PrimitiveExecutionResult(
        ok: false,
        stepResults: [PrimitiveResult(ok: false, message: 'timeout')],
        errorMessage: 'timeout',
        failedAtStep: 0,
      );
      expect(result.ok, isFalse);
      expect(result.failedAtStep, 0);
      expect(result.errorMessage, 'timeout');
      expect(result.stepResults, hasLength(1));
    });

    test('ok: true when all steps succeeded', () {
      const result = PrimitiveExecutionResult(
        ok: true,
        stepResults: [
          PrimitiveResult(ok: true),
          PrimitiveResult(ok: true),
        ],
      );
      expect(result.ok, isTrue);
      expect(result.failedAtStep, isNull);
      expect(result.stepResults, hasLength(2));
    });
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL (file not found)**

```bash
cd /Users/manoj_shetty/workspace/manojs_workspace/challenges/ai/mobile_apps/pocketclaw
flutter test test/services/primitive_engine/primitive_models_test.dart
```

Expected: Error — `Target of URI doesn't exist: 'package:pocketclaw/services/primitive_engine/primitive_models.dart'`

- [ ] **Step 3: Implement the models**

Create `lib/services/primitive_engine/primitive_models.dart`:

```dart
import 'package:flutter/foundation.dart';

enum PrimitiveState { idle, running, error }

class PrimitiveStep {
  final String primitive;
  final Map<String, dynamic> args;

  const PrimitiveStep({required this.primitive, this.args = const {}});

  factory PrimitiveStep.fromJson(Map<String, dynamic> json) {
    final primitive = json['primitive'] as String?;
    if (primitive == null || primitive.isEmpty) {
      throw ArgumentError('Missing required field: primitive');
    }
    const supported = {
      'open_app', 'tap', 'type', 'scroll', 'swipe',
      'back', 'read_screen', 'read_clipboard', 'take_screenshot',
    };
    if (!supported.contains(primitive)) {
      throw ArgumentError('Unknown primitive: $primitive');
    }
    final args = Map<String, dynamic>.from(
      (json['args'] as Map<String, dynamic>?) ?? const {},
    );
    _validateArgs(primitive, args);
    return PrimitiveStep(primitive: primitive, args: args);
  }

  static void _validateArgs(String primitive, Map<String, dynamic> args) {
    switch (primitive) {
      case 'open_app':
        if (args['package'] is! String) {
          throw ArgumentError("open_app requires 'package': String");
        }
      case 'tap':
        final hasSelector = args['selector'] is String;
        final hasCoords = args['x'] is int && args['y'] is int;
        if (!hasSelector && !hasCoords) {
          throw ArgumentError(
            "tap requires 'selector': String or 'x': int + 'y': int",
          );
        }
      case 'type':
        if (args['text'] is! String) {
          throw ArgumentError("type requires 'text': String");
        }
      case 'scroll':
        const dirs = {'up', 'down', 'left', 'right'};
        if (!dirs.contains(args['direction'])) {
          throw ArgumentError(
            "scroll requires 'direction': up|down|left|right",
          );
        }
      case 'swipe':
        for (final field in ['fromX', 'fromY', 'toX', 'toY']) {
          if (args[field] is! int) {
            throw ArgumentError("swipe requires '$field': int");
          }
        }
    }
  }
}

class PrimitiveResult {
  final bool ok;
  final String message;
  final Map<String, dynamic> data;

  const PrimitiveResult({
    required this.ok,
    this.message = '',
    this.data = const {},
  });
}

class PrimitiveExecutionResult {
  final bool ok;
  final List<PrimitiveResult> stepResults;
  final String? errorMessage;
  final int? failedAtStep;

  const PrimitiveExecutionResult({
    required this.ok,
    required this.stepResults,
    this.errorMessage,
    this.failedAtStep,
  });
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
flutter test test/services/primitive_engine/primitive_models_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/primitive_engine/primitive_models.dart \
        test/services/primitive_engine/primitive_models_test.dart
git commit -m "feat(primitive-engine): add data models and validation"
```

---

### Task 2: PrimitiveEngine Dart Service

**Files:**
- Create: `lib/services/primitive_engine/primitive_engine.dart`
- Create: `test/services/primitive_engine/primitive_engine_test.dart`

**Interfaces:**
- Consumes (from Task 1): `PrimitiveState`, `PrimitiveStep`, `PrimitiveResult`, `PrimitiveExecutionResult`
- Produces:
  - `PrimitiveEngine.instance` — singleton
  - `ValueListenable<PrimitiveState> get state`
  - `PrimitiveExecutionResult? get lastResult`
  - `Future<PrimitiveExecutionResult> execute(List<PrimitiveStep> steps)`
  - `static List<PrimitiveStep> fromJson(Map<String, dynamic> json)`
  - `Future<bool> isAccessibilityEnabled()`
  - `Future<void> openAccessibilitySettings()`

The MethodChannel calls:
- Channel `pocketclaw/accessibility`, method `isEnabled` → returns `bool`
- Channel `pocketclaw/accessibility`, method `openAccessibilitySettings` → returns `null`
- Channel `pocketclaw/accessibility`, method `tap` → args: `{selector?, x?, y?}` → `{ok, message}`
- Channel `pocketclaw/accessibility`, method `type` → args: `{text}` → `{ok, message}`
- Channel `pocketclaw/accessibility`, method `scroll` → args: `{direction, amount?}` → `{ok, message}`
- Channel `pocketclaw/accessibility`, method `swipe` → args: `{fromX, fromY, toX, toY}` → `{ok, message}`
- Channel `pocketclaw/accessibility`, method `back` → `{ok, message}`
- Channel `pocketclaw/accessibility`, method `readScreen` → `{ok, message, tree}`
- Channel `pocketclaw/accessibility`, method `readClipboard` → `{ok, message, text}`
- Channel `pocketclaw/accessibility`, method `takeScreenshot` → `{ok, message, path}`
- Channel `pocketclaw/accessibility`, method `openApp` → args: `{package}` → `{ok, message}`

---

- [ ] **Step 1: Write the failing tests**

Create `test/services/primitive_engine/primitive_engine_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_engine.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

// Shorthand to register mock handler on the accessibility channel
const _channel = MethodChannel('pocketclaw/accessibility');

void _mockChannel(Future<Object?> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void _clearChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Default: accessibility disabled so execute() returns early,
    // keeping state idle between tests.
    _mockChannel((call) async {
      if (call.method == 'isEnabled') return false;
      return null;
    });
  });

  tearDown(_clearChannel);

  group('isAccessibilityEnabled', () {
    test('returns true when channel returns true', () async {
      _mockChannel((call) async => true);
      expect(await PrimitiveEngine.instance.isAccessibilityEnabled(), isTrue);
    });

    test('returns false when channel returns false', () async {
      _mockChannel((call) async => false);
      expect(await PrimitiveEngine.instance.isAccessibilityEnabled(), isFalse);
    });

    test('returns false when channel throws PlatformException', () async {
      _mockChannel((_) async =>
          throw PlatformException(code: 'UNAVAILABLE'));
      expect(await PrimitiveEngine.instance.isAccessibilityEnabled(), isFalse);
    });
  });

  group('fromJson', () {
    test('parses steps array', () {
      final steps = PrimitiveEngine.fromJson({
        'steps': [
          {'primitive': 'back'},
          {'primitive': 'type', 'args': {'text': 'hi'}},
        ],
      });
      expect(steps, hasLength(2));
      expect(steps[0].primitive, 'back');
      expect(steps[1].primitive, 'type');
    });

    test('throws ArgumentError when steps key is missing', () {
      expect(
        () => PrimitiveEngine.fromJson({'primitive': 'back'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('propagates ArgumentError from PrimitiveStep.fromJson', () {
      expect(
        () => PrimitiveEngine.fromJson({
          'steps': [
            {'primitive': 'unknown_thing'},
          ],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('execute() — accessibility not enabled', () {
    test('returns ok: false with Accessibility permission required', () async {
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(result.ok, isFalse);
      expect(result.errorMessage, 'Accessibility permission required');
      expect(result.stepResults, isEmpty);
    });

    test('state remains idle after accessibility-not-enabled return', () async {
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(PrimitiveEngine.instance.state.value, PrimitiveState.idle);
    });
  });

  group('execute() — success path', () {
    setUp(() {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        return {'ok': true, 'message': 'done'};
      });
    });

    test('returns ok: true for back step', () async {
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(result.ok, isTrue);
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults[0].ok, isTrue);
    });

    test('state is idle after successful execution', () async {
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(PrimitiveEngine.instance.state.value, PrimitiveState.idle);
    });

    test('dispatches tap with selector args', () async {
      final calls = <MethodCall>[];
      _mockChannel((call) async {
        calls.add(call);
        if (call.method == 'isEnabled') return true;
        return {'ok': true, 'message': 'done'};
      });
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'tap', args: {'selector': 'Search'}),
      ]);
      final tapCall = calls.firstWhere((c) => c.method == 'tap');
      expect(tapCall.arguments['selector'], 'Search');
    });

    test('dispatches type with text arg', () async {
      final calls = <MethodCall>[];
      _mockChannel((call) async {
        calls.add(call);
        if (call.method == 'isEnabled') return true;
        return {'ok': true, 'message': 'done'};
      });
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'type', args: {'text': 'coffee'}),
      ]);
      final typeCall = calls.firstWhere((c) => c.method == 'type');
      expect(typeCall.arguments['text'], 'coffee');
    });

    test('dispatches scroll with direction', () async {
      final calls = <MethodCall>[];
      _mockChannel((call) async {
        calls.add(call);
        if (call.method == 'isEnabled') return true;
        return {'ok': true, 'message': 'done'};
      });
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'scroll', args: {'direction': 'down'}),
      ]);
      final scrollCall = calls.firstWhere((c) => c.method == 'scroll');
      expect(scrollCall.arguments['direction'], 'down');
    });

    test('dispatches readScreen and returns tree in data', () async {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        if (call.method == 'readScreen') {
          return {'ok': true, 'message': 'Screen read', 'tree': 'Button: OK'};
        }
        return {'ok': true, 'message': 'done'};
      });
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'read_screen'),
      ]);
      expect(result.ok, isTrue);
      expect(result.stepResults[0].data['tree'], 'Button: OK');
    });

    test('dispatches readClipboard and returns text in data', () async {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        if (call.method == 'readClipboard') {
          return {'ok': true, 'message': 'done', 'text': 'copied text'};
        }
        return {'ok': true, 'message': 'done'};
      });
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'read_clipboard'),
      ]);
      expect(result.stepResults[0].data['text'], 'copied text');
    });

    test('dispatches takeScreenshot and returns path in data', () async {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        if (call.method == 'takeScreenshot') {
          return {'ok': true, 'message': 'done', 'path': '/data/cache/shot.png'};
        }
        return {'ok': true, 'message': 'done'};
      });
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'take_screenshot'),
      ]);
      expect(result.stepResults[0].data['path'], '/data/cache/shot.png');
    });

    test('dispatches openApp with package arg', () async {
      final calls = <MethodCall>[];
      _mockChannel((call) async {
        calls.add(call);
        if (call.method == 'isEnabled') return true;
        return {'ok': true, 'message': 'done'};
      });
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(
          primitive: 'open_app',
          args: {'package': 'com.swiggy.android'},
        ),
      ]);
      final appCall = calls.firstWhere((c) => c.method == 'openApp');
      expect(appCall.arguments['package'], 'com.swiggy.android');
    });

    test('dispatches swipe with coord args', () async {
      final calls = <MethodCall>[];
      _mockChannel((call) async {
        calls.add(call);
        if (call.method == 'isEnabled') return true;
        return {'ok': true, 'message': 'done'};
      });
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(
          primitive: 'swipe',
          args: {'fromX': 100, 'fromY': 200, 'toX': 300, 'toY': 400},
        ),
      ]);
      final swipeCall = calls.firstWhere((c) => c.method == 'swipe');
      expect(swipeCall.arguments['fromX'], 100);
      expect(swipeCall.arguments['toY'], 400);
    });

    test('stores successful result in lastResult', () async {
      await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(PrimitiveEngine.instance.lastResult, isNotNull);
      expect(PrimitiveEngine.instance.lastResult!.ok, isTrue);
    });
  });

  group('execute() — failure path', () {
    test('stops at first failed step and sets state to error', () async {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        return {'ok': false, 'message': 'Element not found: Foo'};
      });
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'tap', args: {'selector': 'Foo'}),
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(result.ok, isFalse);
      expect(result.failedAtStep, 0);
      expect(result.errorMessage, 'Element not found: Foo');
      expect(result.stepResults, hasLength(1));
      expect(PrimitiveEngine.instance.state.value, PrimitiveState.error);
    });

    test('maps PlatformException to ok: false step result', () async {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        throw PlatformException(code: 'ERROR', message: 'crash');
      });
      final result = await PrimitiveEngine.instance.execute([
        const PrimitiveStep(primitive: 'back'),
      ]);
      expect(result.ok, isFalse);
      expect(result.stepResults[0].message, 'crash');
    });

    test('returns timeout result when step exceeds 5s', () async {
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        await Future.delayed(const Duration(seconds: 6));
        return {'ok': true, 'message': 'done'};
      });
      final result = await PrimitiveEngine.instance
          .execute([const PrimitiveStep(primitive: 'back')]);
      expect(result.ok, isFalse);
      expect(result.stepResults[0].message, 'timeout');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('execute() — already running guard', () {
    test('returns Already running if called while state is running', () async {
      // First call: slow, holds execution open
      final completer = Completer<Map<Object?, Object?>?>();
      _mockChannel((call) async {
        if (call.method == 'isEnabled') return true;
        return completer.future;
      });

      final steps = [const PrimitiveStep(primitive: 'back')];
      final future1 = PrimitiveEngine.instance.execute(steps);

      // Yield to let first execute() reach the running state
      await Future<void>.microtask(() {});

      final result2 = await PrimitiveEngine.instance.execute(steps);
      expect(result2.ok, isFalse);
      expect(result2.errorMessage, 'Already running');

      // Release first call to clean up
      completer.complete({'ok': true, 'message': 'done'});
      await future1;
    });
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL (file not found)**

```bash
flutter test test/services/primitive_engine/primitive_engine_test.dart
```

Expected: Error — `Target of URI doesn't exist: 'package:pocketclaw/services/primitive_engine/primitive_engine.dart'`

- [ ] **Step 3: Implement PrimitiveEngine**

Create `lib/services/primitive_engine/primitive_engine.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'primitive_models.dart';

class PrimitiveEngine {
  PrimitiveEngine._();
  static final PrimitiveEngine instance = PrimitiveEngine._();

  static const _channel = MethodChannel('pocketclaw/accessibility');

  final ValueNotifier<PrimitiveState> _state =
      ValueNotifier(PrimitiveState.idle);
  ValueListenable<PrimitiveState> get state => _state;

  PrimitiveExecutionResult? _lastResult;
  PrimitiveExecutionResult? get lastResult => _lastResult;

  static List<PrimitiveStep> fromJson(Map<String, dynamic> json) {
    final raw = json['steps'] as List<dynamic>?;
    if (raw == null) throw ArgumentError("Missing 'steps' array");
    return raw.cast<Map<String, dynamic>>().map(PrimitiveStep.fromJson).toList();
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException {
      // best-effort
    }
  }

  Future<PrimitiveExecutionResult> execute(List<PrimitiveStep> steps) async {
    if (_state.value == PrimitiveState.running) {
      return const PrimitiveExecutionResult(
        ok: false,
        stepResults: [],
        errorMessage: 'Already running',
      );
    }
    _state.value = PrimitiveState.running;

    final enabled = await isAccessibilityEnabled();
    if (!enabled) {
      _state.value = PrimitiveState.idle;
      return const PrimitiveExecutionResult(
        ok: false,
        stepResults: [],
        errorMessage: 'Accessibility permission required',
      );
    }

    final results = <PrimitiveResult>[];
    for (var i = 0; i < steps.length; i++) {
      PrimitiveResult stepResult;
      try {
        stepResult = await _executeStep(steps[i]).timeout(
          const Duration(seconds: 5),
          onTimeout: () => const PrimitiveResult(ok: false, message: 'timeout'),
        );
      } on PlatformException catch (e) {
        stepResult = PrimitiveResult(
          ok: false,
          message: e.message ?? 'platform error',
        );
      }

      results.add(stepResult);
      if (!stepResult.ok) {
        final executionResult = PrimitiveExecutionResult(
          ok: false,
          stepResults: List.unmodifiable(results),
          errorMessage: stepResult.message,
          failedAtStep: i,
        );
        _lastResult = executionResult;
        _state.value = PrimitiveState.error;
        return executionResult;
      }
    }

    final executionResult = PrimitiveExecutionResult(
      ok: true,
      stepResults: List.unmodifiable(results),
    );
    _lastResult = executionResult;
    _state.value = PrimitiveState.idle;
    return executionResult;
  }

  Future<PrimitiveResult> _executeStep(PrimitiveStep step) async {
    final method = switch (step.primitive) {
      'read_screen' => 'readScreen',
      'read_clipboard' => 'readClipboard',
      'take_screenshot' => 'takeScreenshot',
      'open_app' => 'openApp',
      _ => step.primitive,
    };

    final raw = await _channel.invokeMapMethod<String, Object?>(
      method,
      step.args.isNotEmpty ? step.args : null,
    );

    final data = <String, dynamic>{};
    if (step.primitive == 'read_screen') {
      data['tree'] = raw?['tree'] as String? ?? '';
    } else if (step.primitive == 'read_clipboard') {
      data['text'] = raw?['text'] as String? ?? '';
    } else if (step.primitive == 'take_screenshot') {
      data['path'] = raw?['path'] as String? ?? '';
    }

    return PrimitiveResult(
      ok: raw?['ok'] == true,
      message: raw?['message'] as String? ?? '',
      data: data,
    );
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
flutter test test/services/primitive_engine/primitive_engine_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Run the full test suite to confirm no regressions**

```bash
flutter test
```

Expected: All tests pass (includes `test/widget_test.dart` and both new test files).

- [ ] **Step 6: Commit**

```bash
git add lib/services/primitive_engine/primitive_engine.dart \
        test/services/primitive_engine/primitive_engine_test.dart
git commit -m "feat(primitive-engine): add PrimitiveEngine Dart service"
```

---

### Task 3: Kotlin AccessibilityService + Android Config

**Files:**
- Create: `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt`
- Create: `android/app/src/main/res/xml/accessibility_service_config.xml`
- Create: `android/app/src/main/res/values/strings.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/MainActivity.kt`

**Interfaces:**
- Consumes: `PrimitiveEngine.isAccessibilityEnabled()` calls `pocketclaw/accessibility` `isEnabled`
  → `MainActivity` handler returns `PocketClawAccessibilityService.instance != null`
- The `handleCall()` method is called from `MainActivity`'s channel handler for all primitive methods.
- No new Flutter unit tests in this task — the Kotlin side is verified by the mock in Task 2 and by `isEnabled` returning `true` on a real device once the service is granted permission.

---

- [ ] **Step 1: Create PocketClawAccessibilityService.kt**

Create `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt`:

```kotlin
package com.pocketclaw.pocketclaw

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PocketClawAccessibilityService : AccessibilityService() {

    companion object {
        var instance: PocketClawAccessibilityService? = null
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openApp" -> {
                val pkg = call.argument<String>("package").orEmpty()
                val launch = packageManager.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    result.success(ok("Opened $pkg"))
                } else {
                    result.success(fail("App not found: $pkg"))
                }
            }
            // tap and swipe call result.success() themselves (gesture callbacks are async)
            "tap" -> handleTap(call, result)
            "type" -> result.success(handleType(call))
            "scroll" -> result.success(handleScroll(call))
            "swipe" -> handleSwipe(call, result)
            "back" -> {
                val performed = performGlobalAction(GLOBAL_ACTION_BACK)
                result.success(if (performed) ok("Back") else fail("Back failed"))
            }
            "readScreen" -> result.success(handleReadScreen())
            "readClipboard" -> result.success(handleReadClipboard())
            "takeScreenshot" -> handleTakeScreenshot(result)
            else -> result.notImplemented()
        }
    }

    // Always calls result.success() exactly once — either directly or via gesture callback.
    private fun handleTap(call: MethodCall, result: MethodChannel.Result) {
        val selector = call.argument<String>("selector")
        val x = call.argument<Int>("x")
        val y = call.argument<Int>("y")

        if (selector != null) {
            val node = findNode(selector)
            if (node == null) {
                result.success(fail("Element not found: $selector"))
                return
            }
            val performed = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            node.recycle()
            result.success(if (performed) ok("Tapped $selector") else fail("Tap failed: $selector"))
            return
        }
        if (x != null && y != null) {
            tapAtCoords(x.toFloat(), y.toFloat(), result)
            return
        }
        result.success(fail("tap requires selector or x+y"))
    }

    private fun tapAtCoords(x: Float, y: Float, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
            result.success(fail("Coordinate tap requires Android 7+"))
            return
        }
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 50L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription) {
                result.success(ok("Tapped ($x, $y)"))
            }
            override fun onCancelled(g: GestureDescription) {
                result.success(fail("Tap gesture cancelled"))
            }
        }, null)
    }

    private fun handleType(call: MethodCall): Map<String, Any> {
        val text = call.argument<String>("text").orEmpty()
        val focused = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: return fail("No focused input field")
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text,
            )
        }
        val performed = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        focused.recycle()
        return if (performed) ok("Typed text") else fail("Type failed — no editable field focused")
    }

    private fun handleScroll(call: MethodCall): Map<String, Any> {
        val direction = call.argument<String>("direction")
            ?: return fail("scroll requires 'direction'")
        val amount = call.argument<Int>("amount") ?: 1
        val root = rootInActiveWindow ?: return fail("No active window")
        val action = when (direction) {
            "down", "right" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            "up", "left" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            else -> { root.recycle(); return fail("Unknown direction: $direction") }
        }
        repeat(amount) { root.performAction(action) }
        root.recycle()
        return ok("Scrolled $direction x$amount")
    }

    private fun handleSwipe(call: MethodCall, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
            result.success(fail("Swipe requires Android 7+"))
            return
        }
        val fromX = call.argument<Int>("fromX")?.toFloat()
        val fromY = call.argument<Int>("fromY")?.toFloat()
        val toX   = call.argument<Int>("toX")?.toFloat()
        val toY   = call.argument<Int>("toY")?.toFloat()
        if (fromX == null || fromY == null || toX == null || toY == null) {
            result.success(fail("swipe requires fromX, fromY, toX, toY"))
            return
        }
        val path = Path().apply {
            moveTo(fromX, fromY)
            lineTo(toX, toY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 300L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription) {
                result.success(ok("Swipe completed"))
            }
            override fun onCancelled(g: GestureDescription) {
                result.success(fail("Swipe cancelled"))
            }
        }, null)
    }

    private fun handleReadScreen(): Map<String, Any> {
        val root = rootInActiveWindow ?: return fail("No active window")
        val sb = StringBuilder()
        serializeNode(root, sb, 0)
        root.recycle()
        return mapOf("ok" to true, "message" to "Screen read", "tree" to sb.toString())
    }

    private fun serializeNode(node: AccessibilityNodeInfo, sb: StringBuilder, depth: Int) {
        val indent = "  ".repeat(depth)
        val className = node.className?.toString()?.substringAfterLast('.') ?: "View"
        val text = node.text?.toString().orEmpty()
        val desc = node.contentDescription?.toString().orEmpty()
        val resId = node.viewIdResourceName?.substringAfterLast('/').orEmpty()
        val label = when {
            text.isNotBlank() -> text
            desc.isNotBlank() -> desc
            resId.isNotBlank() -> "[$resId]"
            else -> ""
        }
        if (label.isNotBlank()) {
            sb.appendLine("$indent$className: $label")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            serializeNode(child, sb, depth + 1)
            child.recycle()
        }
    }

    private fun handleReadClipboard(): Map<String, Any> {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return fail("Clipboard service unavailable")
        val clip = cm.primaryClip
            ?: return mapOf("ok" to true, "message" to "Clipboard empty", "text" to "")
        val text = clip.getItemAt(0)?.coerceToText(this)?.toString() ?: ""
        return mapOf("ok" to true, "message" to "Clipboard read", "text" to text)
    }

    private fun handleTakeScreenshot(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            result.success(fail("Screenshot requires Android 11+"))
            return
        }
        @Suppress("NewApi")
        takeScreenshot(
            android.view.Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    try {
                        val bitmap = Bitmap.wrapHardwareBuffer(
                            screenshot.hardwareBuffer,
                            screenshot.colorSpace,
                        )!!
                        val file = java.io.File(
                            cacheDir,
                            "screenshot_${System.currentTimeMillis()}.png",
                        )
                        java.io.FileOutputStream(file).use { out ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                        }
                        bitmap.recycle()
                        screenshot.hardwareBuffer.close()
                        result.success(
                            mapOf("ok" to true, "message" to "Screenshot saved",
                                  "path" to file.absolutePath),
                        )
                    } catch (e: Exception) {
                        result.success(fail("Screenshot encode failed: ${e.message}"))
                    }
                }

                override fun onFailure(errorCode: Int) {
                    result.success(fail("Screenshot failed: $errorCode"))
                }
            },
        )
    }

    private fun findNode(selector: String): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return (root.findAccessibilityNodeInfosByText(selector)?.firstOrNull()
            ?: root.findAccessibilityNodeInfosByViewId(selector)?.firstOrNull())
    }

    private fun ok(message: String): Map<String, Any> =
        mapOf("ok" to true, "message" to message)

    private fun fail(message: String): Map<String, Any> =
        mapOf("ok" to false, "message" to message)
}
```

- [ ] **Step 2: Create accessibility_service_config.xml**

Create directory `android/app/src/main/res/xml/` (it doesn't exist), then create `android/app/src/main/res/xml/accessibility_service_config.xml`:

```xml
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeAllMask"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagRetrieveInteractiveWindows|flagReportViewIds"
    android:canPerformGestures="true"
    android:canRetrieveWindowContent="true"
    android:canTakeScreenshot="true"
    android:description="@string/accessibility_service_description"
    android:notificationTimeout="100" />
```

- [ ] **Step 3: Create strings.xml**

`android/app/src/main/res/values/strings.xml` does not exist. Create it:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="accessibility_service_description">
        PocketClaw uses accessibility to read the screen and perform actions on your behalf.
        No data leaves your device.
    </string>
</resources>
```

- [ ] **Step 4: Register service in AndroidManifest.xml**

In `android/app/src/main/AndroidManifest.xml`, add the `<service>` block inside `<application>`, after the existing `ScreenshotService` entry and before the closing `</application>` tag.

Before (excerpt around the ScreenshotService):
```xml
        <service
            android:name="com.liasica.media_projection_screenshot.ScreenshotService"
            android:exported="false"
            android:foregroundServiceType="mediaProjection"/>
        <!-- Don't delete the meta-data below.
```

After:
```xml
        <service
            android:name="com.liasica.media_projection_screenshot.ScreenshotService"
            android:exported="false"
            android:foregroundServiceType="mediaProjection"/>
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
        <!-- Don't delete the meta-data below.
```

- [ ] **Step 5: Register pocketclaw/accessibility channel in MainActivity.kt**

In `android/app/src/main/kotlin/com/pocketclaw/pocketclaw/MainActivity.kt`, add the accessibility channel registration inside `configureFlutterEngine()`, immediately after the `deviceChannelName` registration block.

Find this block in `configureFlutterEngine`:
```kotlin
        // Register on main engine
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
            .setMethodCallHandler(deviceCallHandler)
```

Add immediately after it:
```kotlin
        // Register accessibility channel — routes to PocketClawAccessibilityService.instance
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocketclaw/accessibility")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(PocketClawAccessibilityService.instance != null)
                    "openAccessibilitySettings" -> {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS,
                        ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> {
                        val service = PocketClawAccessibilityService.instance
                        if (service == null) {
                            result.success(
                                mapOf("ok" to false,
                                      "message" to "Accessibility service not enabled"),
                            )
                        } else {
                            service.handleCall(call, result)
                        }
                    }
                }
            }
```

- [ ] **Step 6: Run flutter test — must pass before commit**

```bash
flutter test
```

Expected output: All tests pass. (The Kotlin changes don't break Flutter tests because channels are mocked in tests.)

- [ ] **Step 7: Commit**

```bash
git add \
  android/app/src/main/kotlin/com/pocketclaw/pocketclaw/PocketClawAccessibilityService.kt \
  android/app/src/main/res/xml/accessibility_service_config.xml \
  android/app/src/main/res/values/strings.xml \
  android/app/src/main/AndroidManifest.xml \
  android/app/src/main/kotlin/com/pocketclaw/pocketclaw/MainActivity.kt
git commit -m "feat(primitive-engine): add Kotlin AccessibilityService and Android config"
```

---

## Manual Verification (after all tasks complete)

On a physical Android device:

1. `flutter run`
2. Open Android Settings → Accessibility → Installed services → PocketClaw → Enable
3. From the chat screen (or a debug widget), call:
   ```dart
   final enabled = await PrimitiveEngine.instance.isAccessibilityEnabled();
   // expect: true
   
   final result = await PrimitiveEngine.instance.execute([
     PrimitiveEngine.fromJson({
       'steps': [
         {'primitive': 'back'},
       ],
     })[0],
   ]);
   // expect: result.ok == true
   ```
4. Verify the Back action executed on the device.
