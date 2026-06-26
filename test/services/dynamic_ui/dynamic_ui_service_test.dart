// test/services/dynamic_ui/dynamic_ui_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/dynamic_ui/dynamic_ui_service.dart';

void main() {
  final svc = DynamicUiService.instance;

  group('parse', () {
    test('parses a valid card spec', () {
      final spec = svc.parse('{"type":"card","title":"Hi","body":"there"}');
      expect(spec, isNotNull);
      expect(spec!.type, 'card');
    });

    test('returns null on malformed JSON', () {
      expect(svc.parse('{not json'), isNull);
    });

    test('returns null on unknown type', () {
      expect(svc.parse('{"type":"chart"}'), isNull);
    });

    test('returns null on non-object JSON', () {
      expect(svc.parse('[1,2,3]'), isNull);
    });
  });

  group('extractBlocks', () {
    test('extracts a single pcui block', () {
      const text = 'Here you go:\n```pcui\n{"type":"card"}\n```\nDone.';
      final blocks = svc.extractBlocks(text);
      expect(blocks.length, 1);
      expect(blocks.first.trim(), '{"type":"card"}');
    });

    test('extracts multiple blocks in order', () {
      const text =
          '```pcui\n{"type":"card","title":"A"}\n```\n'
          'mid\n'
          '```pcui\n{"type":"card","title":"B"}\n```';
      final blocks = svc.extractBlocks(text);
      expect(blocks.length, 2);
      expect(blocks[0].contains('"A"'), isTrue);
      expect(blocks[1].contains('"B"'), isTrue);
    });

    test('returns empty when no pcui block', () {
      expect(svc.extractBlocks('just text and ```dart\ncode\n```'), isEmpty);
    });

    test('is case-insensitive on the fence tag', () {
      const text = '```PCUI\n{"type":"card"}\n```';
      expect(svc.extractBlocks(text).length, 1);
    });
  });
}
