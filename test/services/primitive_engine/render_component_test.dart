import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_engine.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

const _channel = MethodChannel('pocketclaw/accessibility');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('render_component primitive', () {
    test('fromJson accepts render_component with a spec', () {
      final step = PrimitiveStep.fromJson({
        'primitive': 'render_component',
        'args': {
          'spec': {'type': 'card', 'title': 'Hi'},
        },
      });
      expect(step.primitive, 'render_component');
      expect(step.args['spec'], isA<Map>());
    });

    test('fromJson rejects render_component without a typed spec', () {
      expect(
        () => PrimitiveStep.fromJson({
          'primitive': 'render_component',
          'args': {'spec': {}},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('localPrimitives contains render_component', () {
      expect(PrimitiveStep.localPrimitives.contains('render_component'), isTrue);
    });

    test('execute runs a render_component-only skill WITHOUT accessibility', () async {
      // No accessibility MethodChannel mock is registered, so isEnabled would
      // return false. A local-only step list must still succeed.
      final step = PrimitiveStep.fromJson({
        'primitive': 'render_component',
        'args': {
          'spec': {'type': 'card', 'title': 'Done', 'body': 'ok'},
        },
      });
      final result = await PrimitiveEngine.instance.execute([step]);
      expect(result.ok, isTrue);
      expect(result.stepResults.single.ok, isTrue);

      final pcui = result.stepResults.single.data['pcui'] as String;
      final decoded = jsonDecode(pcui) as Map<String, dynamic>;
      expect(decoded['type'], 'card');
      expect(result.stepResults.single.message, contains('```pcui'));
    });

    test('mixed list (render_component + tap) STILL requires accessibility', () async {
      // Accessibility reports disabled. Because the list contains a non-local
      // primitive (tap), the gate must fire and the whole list must be
      // refused before any step runs.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'isEnabled') return false;
        return null;
      });
      final steps = [
        PrimitiveStep.fromJson({
          'primitive': 'render_component',
          'args': {
            'spec': {'type': 'card', 'title': 'Hi'},
          },
        }),
        PrimitiveStep.fromJson({
          'primitive': 'tap',
          'args': {'selector': 'OK button'},
        }),
      ];
      final result = await PrimitiveEngine.instance.execute(steps);
      expect(result.ok, isFalse);
      expect(result.errorMessage, 'Accessibility permission required');
      expect(result.stepResults, isEmpty);
    });
  });
}
