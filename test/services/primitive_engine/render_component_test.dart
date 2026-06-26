import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_engine.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}
