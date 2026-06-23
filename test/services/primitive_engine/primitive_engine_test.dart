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
