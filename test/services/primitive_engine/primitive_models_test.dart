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
