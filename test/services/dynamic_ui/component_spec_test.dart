import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/dynamic_ui/component_spec.dart';

void main() {
  group('ComponentSpec.fromJson', () {
    test('parses a card', () {
      final s = ComponentSpec.fromJson({
        'type': 'card',
        'title': 'Done',
        'body': 'Created 12 cards.',
      });
      expect(s.type, 'card');
      expect(s.title, 'Done');
      expect(s.body, 'Created 12 cards.');
    });

    test('parses a list with items', () {
      final s = ComponentSpec.fromJson({
        'type': 'list',
        'items': [
          {'title': 'Morning', 'subtitle': '3 skills'},
          {'title': 'Invoices'},
        ],
      });
      expect(s.type, 'list');
      expect(s.items!.length, 2);
      expect(s.items![0].title, 'Morning');
      expect(s.items![0].subtitle, '3 skills');
      expect(s.items![1].subtitle, isNull);
    });

    test('parses key_value rows', () {
      final s = ComponentSpec.fromJson({
        'type': 'key_value',
        'title': 'Invoice',
        'rows': [
          {'label': 'Vendor', 'value': 'Acme'},
        ],
      });
      expect(s.rows!.single.label, 'Vendor');
      expect(s.rows!.single.value, 'Acme');
    });

    test('parses buttons', () {
      final s = ComponentSpec.fromJson({
        'type': 'buttons',
        'buttons': [
          {'label': 'Run', 'command': 'run workflow x'},
        ],
      });
      expect(s.buttons!.single.label, 'Run');
      expect(s.buttons!.single.command, 'run workflow x');
    });

    test('throws on unknown type', () {
      expect(
        () => ComponentSpec.fromJson({'type': 'chart'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing type', () {
      expect(
        () => ComponentSpec.fromJson({'title': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when list item lacks title', () {
      expect(
        () => ComponentSpec.fromJson({
          'type': 'list',
          'items': [
            {'subtitle': 'no title'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when buttons entry lacks command', () {
      expect(
        () => ComponentSpec.fromJson({
          'type': 'buttons',
          'buttons': [
            {'label': 'x'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when key_value row lacks value', () {
      expect(
        () => ComponentSpec.fromJson({
          'type': 'key_value',
          'rows': [
            {'label': 'x'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
