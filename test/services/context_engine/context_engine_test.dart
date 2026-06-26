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
          return {'ok': true, 'tree': 'Button: Order Now'};
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
        if (call.method == 'readScreen') {
          return {'ok': true};
        }
        return null;
      });

      final snap = await ContextEngine.instance.capture();

      expect(snap.foregroundPackage, 'com.test.app');
      expect(snap.screenTree, isEmpty);
    });

    test(
      'never throws — returns empty snapshot on channel exception',
      () async {
        mockChannel((call) async {
          throw PlatformException(code: 'ERROR', message: 'channel error');
        });

        final snap = await ContextEngine.instance.capture();

        expect(snap.accessibilityAvailable, isFalse);
        expect(snap.hasContext, isFalse);
      },
    );
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
