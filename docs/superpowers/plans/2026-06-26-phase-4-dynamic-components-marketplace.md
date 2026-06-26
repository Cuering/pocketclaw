# Phase 4: Dynamic Components + Skill Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add JSON-driven rich UI components (card/list/key_value/buttons) that Gemma or skills can emit into chat, plus export/import of skills and workflows as self-contained `.pcskill` bundle files.

**Architecture:** One renderer fed by two sources — model-emitted ```` ```pcui``` ```` blocks in chat text, and a `render_component` primitive that emits the same block as its step output. A pure `ComponentSpec` model + `DynamicUiService` parser feed a `DynamicComponentWidget`, slotted into the existing `_AssistantMessageContent` segment splitter in `message_bubble.dart`. Marketplace is a pure `PcSkillCodec` (encode/decode + ID re-mint + workflow-ref rewire) behind a `MarketplaceService` that exports via `share_plus` and imports via the existing `file_picker`.

**Tech Stack:** Flutter/Dart (Android), Hive `Box<String>` stores, `ValueListenable` state, `PocketClawTheme` tokens, `file_picker ^11.0.2` + `path_provider ^2.1.5` (present), `share_plus` (new), `flutter_markdown` (present).

## Global Constraints

- 100% on-device; no network calls in any Phase 4 service. Verbatim from spec.
- All UI from `PocketClawTheme` tokens only — never `Color(0xFF...)` inline. Neobrutalism: 2px hard borders, `hardShadow`, cyan primary.
- All text styles from `Theme.of(context).textTheme.*` (with `.copyWith(color:)` for color overrides) — never raw `TextStyle(color: ...)`.
- Services are singletons (`static final X instance = X._();`), initialized only in `main.dart`.
- `ValueListenable<T>` + `ValueListenableBuilder` for service state; no Riverpod/Provider/BLoC.
- Hive `Box<String>` + `jsonEncode`/`jsonDecode`; NO TypeAdapters.
- `build()` is pure; `if (!mounted) return;` after every `await`; dispose every controller.
- Component rendering must degrade to raw text on a bad spec — never crash.
- Bundle format string is exactly `pcskill/1`.
- Skill id scheme: `skill-<ts>-<rand>` (`skill-<millis>-<5digit>`). Workflow id scheme: `wf-<millis>-<5digit>`.
- `flutter test` must pass before any commit. 97 tests currently green on `dev`.
- Branch: create `feature/phase-4-dynamic-components-marketplace` off `dev` before Task 1.

---

### Task 1: ComponentSpec model + strict fromJson

**Files:**
- Create: `lib/services/dynamic_ui/component_spec.dart`
- Test: `test/services/dynamic_ui/component_spec_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces:
  - `class ComponentSpec { final String type; final String? title; final String? body; final List<ListItem>? items; final List<KvRow>? rows; final List<UiButton>? buttons; }`
  - `ComponentSpec.fromJson(Map<String, dynamic>) → ComponentSpec` — throws `FormatException` on invalid/unknown spec.
  - `class ListItem { final String title; final String? subtitle; }`
  - `class KvRow { final String label; final String value; }`
  - `class UiButton { final String label; final String command; }`
  - Supported types: `'card'`, `'list'`, `'key_value'`, `'buttons'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/dynamic_ui/component_spec_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/dynamic_ui/component_spec_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pocketclaw/services/dynamic_ui/component_spec.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/services/dynamic_ui/component_spec.dart

/// A typed, validated dynamic-UI component. Built from a `pcui` JSON block
/// emitted by Gemma or by the render_component primitive.
///
/// Supported types: card, list, key_value, buttons.
class ComponentSpec {
  final String type;
  final String? title;
  final String? body; // card
  final List<ListItem>? items; // list
  final List<KvRow>? rows; // key_value
  final List<UiButton>? buttons; // buttons

  const ComponentSpec({
    required this.type,
    this.title,
    this.body,
    this.items,
    this.rows,
    this.buttons,
  });

  static const supportedTypes = {'card', 'list', 'key_value', 'buttons'};

  /// Builds a spec from decoded JSON. Throws [FormatException] on any
  /// malformed or unknown spec — callers (DynamicUiService) catch this and
  /// degrade to plain text.
  factory ComponentSpec.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || !supportedTypes.contains(type)) {
      throw FormatException('Unknown component type: $type');
    }

    switch (type) {
      case 'card':
        return ComponentSpec(
          type: type,
          title: json['title'] as String?,
          body: json['body'] as String?,
        );
      case 'list':
        final raw = json['items'];
        if (raw is! List) {
          throw const FormatException("list requires 'items': array");
        }
        return ComponentSpec(
          type: type,
          title: json['title'] as String?,
          items: raw
              .map((e) => ListItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'key_value':
        final raw = json['rows'];
        if (raw is! List) {
          throw const FormatException("key_value requires 'rows': array");
        }
        return ComponentSpec(
          type: type,
          title: json['title'] as String?,
          rows: raw
              .map((e) => KvRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'buttons':
        final raw = json['buttons'];
        if (raw is! List) {
          throw const FormatException("buttons requires 'buttons': array");
        }
        return ComponentSpec(
          type: type,
          buttons: raw
              .map((e) => UiButton.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      default:
        throw FormatException('Unknown component type: $type');
    }
  }
}

class ListItem {
  final String title;
  final String? subtitle;
  const ListItem({required this.title, this.subtitle});

  factory ListItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    if (title is! String || title.isEmpty) {
      throw const FormatException("list item requires 'title': String");
    }
    return ListItem(title: title, subtitle: json['subtitle'] as String?);
  }
}

class KvRow {
  final String label;
  final String value;
  const KvRow({required this.label, required this.value});

  factory KvRow.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final value = json['value'];
    if (label is! String || value is! String) {
      throw const FormatException("key_value row requires 'label' + 'value'");
    }
    return KvRow(label: label, value: value);
  }
}

class UiButton {
  final String label;
  final String command;
  const UiButton({required this.label, required this.command});

  factory UiButton.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final command = json['command'];
    if (label is! String || label.isEmpty || command is! String || command.isEmpty) {
      throw const FormatException("button requires 'label' + 'command'");
    }
    return UiButton(label: label, command: command);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/dynamic_ui/component_spec_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/dynamic_ui/component_spec.dart test/services/dynamic_ui/component_spec_test.dart
git commit -m "feat(dynamic-ui): add ComponentSpec model with strict fromJson"
```

---

### Task 2: DynamicUiService — parse + extractBlocks

**Files:**
- Create: `lib/services/dynamic_ui/dynamic_ui_service.dart`
- Test: `test/services/dynamic_ui/dynamic_ui_service_test.dart`

**Interfaces:**
- Consumes: `ComponentSpec.fromJson` (Task 1).
- Produces:
  - `DynamicUiService.instance` (singleton).
  - `ComponentSpec? parse(String json)` — decodes JSON then `ComponentSpec.fromJson`; returns `null` on any failure (never throws).
  - `List<String> extractBlocks(String text)` — returns the inner JSON of every ```` ```pcui … ``` ```` fenced block, in order. Empty list if none.
  - `Future<void> init()` (no-op; for main.dart symmetry).

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/dynamic_ui/dynamic_ui_service_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/services/dynamic_ui/dynamic_ui_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'component_spec.dart';

/// Parses `pcui` JSON blocks into [ComponentSpec]s. Stateless and pure —
/// a singleton only for pattern consistency.
class DynamicUiService {
  DynamicUiService._();
  static final DynamicUiService instance = DynamicUiService._();

  Future<void> init() async {}
  Future<void> dispose() async {}

  /// Matches ```pcui … ``` fenced blocks (case-insensitive tag).
  /// Group 1 is the inner JSON.
  static final RegExp _blockPattern =
      RegExp(r'```pcui[ \t]*\n([\s\S]*?)```', caseSensitive: false);

  /// Returns null on any decode/validation failure — never throws.
  ComponentSpec? parse(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return ComponentSpec.fromJson(decoded);
    } catch (e) {
      debugPrint('🐾 DYNAMIC UI: parse failed: $e');
      return null;
    }
  }

  /// Extracts the inner JSON of every pcui fenced block, in order.
  List<String> extractBlocks(String text) {
    return _blockPattern
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/dynamic_ui/dynamic_ui_service_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/dynamic_ui/dynamic_ui_service.dart test/services/dynamic_ui/dynamic_ui_service_test.dart
git commit -m "feat(dynamic-ui): add DynamicUiService parse + extractBlocks"
```

---

### Task 3: DynamicComponentWidget — renders the Core 4

**Files:**
- Create: `lib/widgets/dynamic_component_widget.dart`
- Test: `test/widgets/dynamic_component_widget_test.dart`

**Interfaces:**
- Consumes: `ComponentSpec`, `ListItem`, `KvRow`, `UiButton` (Task 1); `PocketClawTheme`.
- Produces:
  - `class DynamicComponentWidget extends StatelessWidget { const DynamicComponentWidget({super.key, required this.spec, this.onCommand}); final ComponentSpec spec; final void Function(String command)? onCommand; }`
  - Renders card/list/key_value/buttons. Button taps call `onCommand(button.command)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/dynamic_component_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/core/pocketclaw_theme.dart';
import 'package:pocketclaw/services/dynamic_ui/component_spec.dart';
import 'package:pocketclaw/widgets/dynamic_component_widget.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: PocketClawTheme.dark(), home: Scaffold(body: child));

void main() {
  testWidgets('card renders title and body', (tester) async {
    await tester.pumpWidget(_wrap(const DynamicComponentWidget(
      spec: ComponentSpec(type: 'card', title: 'Hello', body: 'World'),
    )));
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets('list renders item titles and subtitles', (tester) async {
    await tester.pumpWidget(_wrap(const DynamicComponentWidget(
      spec: ComponentSpec(type: 'list', items: [
        ListItem(title: 'A', subtitle: 'sub-a'),
        ListItem(title: 'B'),
      ]),
    )));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('sub-a'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('key_value renders label and value', (tester) async {
    await tester.pumpWidget(_wrap(const DynamicComponentWidget(
      spec: ComponentSpec(type: 'key_value', rows: [
        KvRow(label: 'Vendor', value: 'Acme'),
      ]),
    )));
    expect(find.text('Vendor'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
  });

  testWidgets('button tap invokes onCommand', (tester) async {
    String? captured;
    await tester.pumpWidget(_wrap(DynamicComponentWidget(
      spec: const ComponentSpec(type: 'buttons', buttons: [
        UiButton(label: 'Run it', command: 'run workflow x'),
      ]),
      onCommand: (c) => captured = c,
    )));
    await tester.tap(find.text('Run it'));
    await tester.pump();
    expect(captured, 'run workflow x');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/dynamic_component_widget_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/widgets/dynamic_component_widget.dart
import 'package:flutter/material.dart';

import '../core/pocketclaw_theme.dart';
import '../services/dynamic_ui/component_spec.dart';

/// Renders a validated [ComponentSpec] using neobrutalism theme tokens.
/// Button taps forward their command string via [onCommand].
class DynamicComponentWidget extends StatelessWidget {
  const DynamicComponentWidget({super.key, required this.spec, this.onCommand});

  final ComponentSpec spec;
  final void Function(String command)? onCommand;

  @override
  Widget build(BuildContext context) {
    return switch (spec.type) {
      'card' => _card(context),
      'list' => _list(context),
      'key_value' => _keyValue(context),
      'buttons' => _buttons(context),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _panel(BuildContext context, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: PocketClawTheme.panel(
          color: PocketClawTheme.bg,
          border: PocketClawTheme.cyan,
          radius: 8,
        ),
        child: child,
      );

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null && spec.title!.isNotEmpty)
            Text(spec.title!, style: theme.textTheme.titleMedium),
          if (spec.title != null && spec.body != null)
            const SizedBox(height: 6),
          if (spec.body != null && spec.body!.isNotEmpty)
            Text(spec.body!, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final items = spec.items ?? const [];
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null && spec.title!.isNotEmpty) ...[
            Text(spec.title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 14, color: PocketClawTheme.bg3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(items[i].title, style: theme.textTheme.bodyMedium),
                if (items[i].subtitle != null && items[i].subtitle!.isNotEmpty)
                  Text(
                    items[i].subtitle!,
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _keyValue(BuildContext context) {
    final theme = Theme.of(context);
    final rows = spec.rows ?? const [];
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null && spec.title!.isNotEmpty) ...[
            Text(spec.title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(r.label, style: theme.textTheme.labelSmall),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(r.value, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    final buttons = spec.buttons ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final b in buttons)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: PocketClawTheme.cyan, width: 2),
                foregroundColor: PocketClawTheme.cyan,
              ),
              onPressed: onCommand == null ? null : () => onCommand!(b.command),
              child: Text(b.label),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/dynamic_component_widget_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/dynamic_component_widget.dart test/widgets/dynamic_component_widget_test.dart
git commit -m "feat(dynamic-ui): add DynamicComponentWidget for the Core 4"
```

---

### Task 4: render_component primitive (local, no accessibility)

**Files:**
- Modify: `lib/services/primitive_engine/primitive_models.dart`
- Modify: `lib/services/primitive_engine/primitive_engine.dart`
- Test: `test/services/primitive_engine/render_component_test.dart`

**Context — current behavior you must preserve:** `PrimitiveStep.fromJson` (primitive_models.dart:9-35) validates against a `supported` set and calls `_validateArgs`. `PrimitiveEngine.execute` (primitive_engine.dart:45-100) gates the WHOLE step list on `isAccessibilityEnabled()` returning true, then dispatches each step via `_executeStep` over the `pocketclaw/accessibility` MethodChannel.

`render_component` is a **local** primitive — it produces a `pcui` block string and must NOT touch the MethodChannel or require accessibility.

**Interfaces:**
- Consumes: existing `PrimitiveStep`, `PrimitiveResult`, `PrimitiveExecutionResult`.
- Produces:
  - `render_component` added to `supported` set and `_validateArgs` (requires `spec` map with a String `type`).
  - `PrimitiveEngine` recognizes `render_component` as local: execution returns `PrimitiveResult(ok: true, message: '```pcui\n<json>\n```', data: {'pcui': <json>})` without the channel.
  - Accessibility gate only fires when at least one NON-local primitive is present.
  - `static const localPrimitives = {'render_component'};` on `PrimitiveStep`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/primitive_engine/render_component_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/primitive_engine/render_component_test.dart`
Expected: FAIL — `Unknown primitive: render_component` (and `localPrimitives` getter missing).

- [ ] **Step 3a: Update primitive_models.dart**

Add `'render_component'` to the `supported` set (primitive_models.dart:14-24) and add a `localPrimitives` constant + validation. Replace the `supported` set and add the constant + a `render_component` case in `_validateArgs`:

```dart
// in PrimitiveStep, above fromJson:
  static const localPrimitives = {'render_component'};

// inside fromJson, the supported set becomes:
    const supported = {
      'open_app',
      'tap',
      'type',
      'scroll',
      'swipe',
      'back',
      'read_screen',
      'read_clipboard',
      'take_screenshot',
      'render_component',
    };
```

Add to `_validateArgs`'s switch (after the `swipe` case):

```dart
      case 'render_component':
        final spec = args['spec'];
        if (spec is! Map || spec['type'] is! String || (spec['type'] as String).isEmpty) {
          throw ArgumentError(
            "render_component requires 'spec': {'type': String, ...}",
          );
        }
```

- [ ] **Step 3b: Update primitive_engine.dart**

Make the accessibility gate conditional, and short-circuit local primitives in `_executeStep`.

Replace the gate block (primitive_engine.dart:56-64) so it only checks accessibility when a non-local primitive is present:

```dart
    final needsAccessibility =
        steps.any((s) => !PrimitiveStep.localPrimitives.contains(s.primitive));
    if (needsAccessibility) {
      final enabled = await isAccessibilityEnabled();
      if (!enabled) {
        _state.value = PrimitiveState.idle;
        return const PrimitiveExecutionResult(
          ok: false,
          stepResults: [],
          errorMessage: 'Accessibility permission required',
        );
      }
    }
```

(Delete the old unconditional `final enabled = ...` block that this replaces.)

At the TOP of `_executeStep` (before the `method` switch), short-circuit local primitives:

```dart
  Future<PrimitiveResult> _executeStep(PrimitiveStep step) async {
    if (step.primitive == 'render_component') {
      final spec = step.args['spec'] as Map;
      final json = jsonEncode(spec);
      return PrimitiveResult(
        ok: true,
        message: '```pcui\n$json\n```',
        data: {'pcui': json},
      );
    }

    final method = switch (step.primitive) {
      // ... unchanged
```

Add `import 'dart:convert';` to the top of `primitive_engine.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/primitive_engine/render_component_test.dart`
Expected: PASS (4 tests)

Then run the existing primitive suite to confirm no regression:

Run: `flutter test test/services/primitive_engine/primitive_engine_test.dart`
Expected: PASS (all existing tests still green — the gate change is a no-op when any accessibility primitive is present).

- [ ] **Step 5: Commit**

```bash
git add lib/services/primitive_engine/primitive_models.dart lib/services/primitive_engine/primitive_engine.dart test/services/primitive_engine/render_component_test.dart
git commit -m "feat(primitive-engine): add local render_component primitive"
```

---

### Task 5: Render pcui blocks in chat + onCommand + system-prompt guide

**Files:**
- Modify: `lib/widgets/message_bubble.dart`
- Modify: `lib/screens/chat_screen.dart`

**Context — current behavior:** `MessageBubble` (message_bubble.dart:14) renders assistant text via `_AssistantMessageContent` (line 303), which already splits fenced code blocks into `_ContentSegment`s in `_splitMarkdownCodeBlocks` (line 336). `MessageBubble` is built in `chat_screen.dart:1452`. The user-send path: `chat_screen.dart` builds a prompt via `_buildPromptFromHistory` (line 409) and there is a send handler that appends a user `Message` and calls generation.

**Interfaces:**
- Consumes: `DynamicUiService.instance` (Task 2), `DynamicComponentWidget` (Task 3).
- Produces:
  - `MessageBubble` gains `final void Function(String command)? onCommand;` forwarded to `_AssistantMessageContent`.
  - `_AssistantMessageContent` renders a `DynamicComponentWidget` for any segment that is a valid `pcui` block; other code/text segments render as today.
  - `chat_screen.dart` passes `onCommand: _handleComponentCommand` where `_handleComponentCommand(String command)` submits the command as a new user message through the existing send path.
  - System prompt gains a concise pcui guide.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/message_bubble_pcui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/core/pocketclaw_theme.dart';
import 'package:pocketclaw/models/message.dart';
import 'package:pocketclaw/widgets/message_bubble.dart';
import 'package:pocketclaw/widgets/dynamic_component_widget.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: PocketClawTheme.dark(), home: Scaffold(body: child));

void main() {
  testWidgets('assistant bubble renders a pcui card block', (tester) async {
    final msg = Message(
      role: MessageRole.assistant,
      text: 'Here:\n```pcui\n{"type":"card","title":"Boo","body":"yah"}\n```',
    );
    await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
    expect(find.byType(DynamicComponentWidget), findsOneWidget);
    expect(find.text('Boo'), findsOneWidget);
  });

  testWidgets('button command routes through onCommand', (tester) async {
    String? captured;
    final msg = Message(
      role: MessageRole.assistant,
      text: '```pcui\n{"type":"buttons","buttons":[{"label":"Go","command":"run workflow x"}]}\n```',
    );
    await tester.pumpWidget(_wrap(
      MessageBubble(message: msg, onCommand: (c) => captured = c),
    ));
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(captured, 'run workflow x');
  });

  testWidgets('malformed pcui block falls back to text (no crash)', (tester) async {
    final msg = Message(
      role: MessageRole.assistant,
      text: '```pcui\n{not valid}\n```',
    );
    await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
    expect(find.byType(DynamicComponentWidget), findsNothing);
    // The raw block is shown as a code segment instead — no exception thrown.
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/message_bubble_pcui_test.dart`
Expected: FAIL — `DynamicComponentWidget` not found in tree (and `onCommand` param missing on `MessageBubble`).

- [ ] **Step 3a: Update message_bubble.dart**

Add imports at the top:

```dart
import '../services/dynamic_ui/dynamic_ui_service.dart';
import 'dynamic_component_widget.dart';
```

Add the `onCommand` field to `MessageBubble`:

```dart
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDocTap,
    this.loadingText,
    this.onCommand,
  });

  // ... existing fields ...
  final void Function(String command)? onCommand;
```

Pass it into `_AssistantMessageContent` (around line 134):

```dart
                      : _AssistantMessageContent(
                          text: message.text,
                          textColor: textColor,
                          onCommand: onCommand,
                        ),
```

Update `_AssistantMessageContent` to accept `onCommand` and render pcui segments. Replace the class (lines 303-352) with:

```dart
class _AssistantMessageContent extends StatelessWidget {
  const _AssistantMessageContent({
    required this.text,
    required this.textColor,
    this.onCommand,
  });

  final String text;
  final Color textColor;
  final void Function(String command)? onCommand;

  @override
  Widget build(BuildContext context) {
    final segments = _splitSegments(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final segment in segments) ...[
          if (segment.pcuiSpec != null)
            DynamicComponentWidget(spec: segment.pcuiSpec!, onCommand: onCommand)
          else if (segment.isCode)
            _CopyableCodeBlock(code: segment.text)
          else if (segment.text.trim().isNotEmpty)
            MarkdownBody(
              data: segment.text,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
              selectable: true,
            ),
          if (segment != segments.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// Splits text into ordered segments: pcui components, code blocks, and
  /// plain text. A ```pcui block that parses becomes a [pcuiSpec] segment;
  /// one that fails to parse falls through as a normal code segment.
  List<_ContentSegment> _splitSegments(String value) {
    final pattern = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
    final segments = <_ContentSegment>[];
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        segments.add(_ContentSegment(value.substring(cursor, match.start)));
      }
      final tag = (match.group(1) ?? '').trim().toLowerCase();
      final inner = match.group(2) ?? '';
      if (tag == 'pcui') {
        final spec = DynamicUiService.instance.parse(inner);
        if (spec != null) {
          segments.add(_ContentSegment('', pcuiSpec: spec));
        } else {
          segments.add(_ContentSegment(inner, isCode: true));
        }
      } else {
        segments.add(_ContentSegment(inner, isCode: true));
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      segments.add(_ContentSegment(value.substring(cursor)));
    }
    return segments.isEmpty ? [_ContentSegment(value)] : segments;
  }
}
```

Update `_ContentSegment` (lines 354-359) to carry an optional spec:

```dart
class _ContentSegment {
  _ContentSegment(this.text, {this.isCode = false, this.pcuiSpec});

  final String text;
  final bool isCode;
  final ComponentSpec? pcuiSpec;
}
```

Add the import for the spec type at the top of message_bubble.dart:

```dart
import '../services/dynamic_ui/component_spec.dart';
```

- [ ] **Step 3b: Update chat_screen.dart**

Find the `MessageBubble(` construction at `chat_screen.dart:1452` and add the `onCommand` wiring:

```dart
                      return MessageBubble(
                        message: m,
                        onCommand: _handleComponentCommand,
                        loadingText: m.isAssistant && m.text.isEmpty && _busy
                        // ... keep the rest of the existing args unchanged
```

Add the handler method to `_ChatScreenState` (near the other send handlers). It submits the button command exactly as if the user typed it, through the existing `_handleSend(String text)` entry point (chat_screen.dart:730). `_handleSend` already takes the text as a parameter and already guards on `_busy`/`_preparingImageSummary` (line 731), so no extra guard is needed:

```dart
  void _handleComponentCommand(String command) {
    if (command.trim().isEmpty) return;
    _handleSend(command); // existing send path; self-guards on _busy
  }
```

> Verified: `_handleSend(String text)` is the screen's single send entry point
> (also wired to the input via `onSend: _handleSend` at chat_screen.dart:1487).
> Do not create a second generation path.

- [ ] **Step 3c: Add the pcui guide to the system prompt**

In `_buildPromptFromHistory` (chat_screen.dart:409), the assembled prompt begins with the assistant's instruction preamble. Append this concise guide to that preamble string (keep it short — the model is small):

```dart
// Append to the system/preamble portion of the prompt:
'\n\nYou may render a rich UI component instead of plain text ONLY when the '
'data is clearly structured. To do so, output a fenced block:\n'
'```pcui\n{"type":"card","title":"...","body":"..."}\n```\n'
'Supported types: card {title,body}; list {items:[{title,subtitle}]}; '
'key_value {title,rows:[{label,value}]}; buttons {buttons:[{label,command}]}. '
'Prefer plain text for normal answers. Emit at most one component.'
```

> Implementer note: locate the existing preamble literal in
> `_buildPromptFromHistory` and concatenate this guide onto it. If the
> preamble is built from a helper/constant, append there. Keep the existing
> preamble text intact.

- [ ] **Step 4: Run tests**

Run: `flutter test test/widgets/message_bubble_pcui_test.dart`
Expected: PASS (3 tests)

Run: `flutter test`
Expected: All pass (existing + new).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/message_bubble.dart lib/screens/chat_screen.dart test/widgets/message_bubble_pcui_test.dart
git commit -m "feat(dynamic-ui): render pcui components in chat + button command routing"
```

---

### Task 6: PcSkillCodec — encode/decode bundle, ID re-mint, ref rewire

**Files:**
- Create: `lib/services/marketplace/pcskill_codec.dart`
- Test: `test/services/marketplace/pcskill_codec_test.dart`

**Context — existing models:** `SkillModel` (lib/services/skill_engine/skill_model.dart) has `toJson()`/`fromJson()`, fields `id, name, description, version, steps (List<PrimitiveStep>), createdAt, useCount`. `WorkflowModel` (lib/services/workflow_engine/workflow_model.dart) has `toJson()`/`fromJson()`, fields `id, name, description, triggerType, stepSkillIds (List<String>), createdAt, lastRunAt, runCount`.

**Interfaces:**
- Consumes: `SkillModel`, `WorkflowModel`.
- Produces:
  - `class PcSkillCodec` with static methods.
  - `static String encode({required List<SkillModel> skills, List<WorkflowModel> workflows = const [], required String exportedAtIso})` → JSON string `{format:'pcskill/1', exportedAt, skills:[...], workflows:[...]}`.
  - `static ImportPlan decode(String jsonStr, {required String Function() newSkillId, required String Function() newWorkflowId})` → an `ImportPlan` of re-minted, ready-to-save models. Throws `FormatException` on bad/unknown format.
  - `class ImportPlan { final List<SkillModel> skills; final List<WorkflowModel> workflows; final List<String> warnings; }`
  - `class ImportResult { final int skillsAdded; final int workflowsAdded; final List<String> warnings; }` (used by the service in Task 7).
  - ID injection: `newSkillId`/`newWorkflowId` are passed in so the codec stays pure/testable (no `DateTime.now()` inside).

- [ ] **Step 1: Write the failing test**

```dart
// test/services/marketplace/pcskill_codec_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketclaw/services/marketplace/pcskill_codec.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_model.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  SkillModel skill(String id, String name) => SkillModel(
        id: id,
        name: name,
        steps: const [PrimitiveStep(primitive: 'back')],
        createdAt: DateTime(2026, 1, 1),
      );

  WorkflowModel workflow(String id, List<String> stepIds) => WorkflowModel(
        id: id,
        name: 'WF',
        stepSkillIds: stepIds,
        createdAt: DateTime(2026, 1, 1),
      );

  group('encode', () {
    test('produces pcskill/1 with skills and workflows', () {
      final json = PcSkillCodec.encode(
        skills: [skill('s1', 'A')],
        workflows: [workflow('w1', ['s1'])],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['format'], 'pcskill/1');
      expect((decoded['skills'] as List).length, 1);
      expect((decoded['workflows'] as List).length, 1);
    });
  });

  group('decode', () {
    test('rejects unknown format', () {
      expect(
        () => PcSkillCodec.decode(
          jsonEncode({'format': 'pcskill/99', 'skills': []}),
          newSkillId: () => 'new',
          newWorkflowId: () => 'neww',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-pcskill json', () {
      expect(
        () => PcSkillCodec.decode(
          '{"foo":1}',
          newSkillId: () => 'new',
          newWorkflowId: () => 'neww',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('re-mints skill ids', () {
      final json = PcSkillCodec.encode(
        skills: [skill('old-id', 'A')],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );
      var n = 0;
      final plan = PcSkillCodec.decode(
        json,
        newSkillId: () => 'skill-new-${n++}',
        newWorkflowId: () => 'wf-new',
      );
      expect(plan.skills.single.id, 'skill-new-0');
      expect(plan.skills.single.name, 'A');
    });

    test('rewires workflow stepSkillIds through the id map', () {
      final json = PcSkillCodec.encode(
        skills: [skill('old-s', 'A')],
        workflows: [workflow('old-w', ['old-s'])],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );
      final plan = PcSkillCodec.decode(
        json,
        newSkillId: () => 'skill-X',
        newWorkflowId: () => 'wf-Y',
      );
      expect(plan.skills.single.id, 'skill-X');
      expect(plan.workflows.single.id, 'wf-Y');
      expect(plan.workflows.single.stepSkillIds, ['skill-X']);
      expect(plan.warnings, isEmpty);
    });

    test('drops missing skill refs from a workflow and warns', () {
      final json = jsonEncode({
        'format': 'pcskill/1',
        'skills': <Map<String, dynamic>>[],
        'workflows': [workflow('old-w', ['ghost']).toJson()],
      });
      final plan = PcSkillCodec.decode(
        json,
        newSkillId: () => 'skill-X',
        newWorkflowId: () => 'wf-Y',
      );
      expect(plan.workflows.single.stepSkillIds, isEmpty);
      expect(plan.warnings.length, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/marketplace/pcskill_codec_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/services/marketplace/pcskill_codec.dart
import 'dart:convert';

import '../skill_engine/skill_model.dart';
import '../workflow_engine/workflow_model.dart';

/// Re-minted, ready-to-save models produced by [PcSkillCodec.decode].
class ImportPlan {
  final List<SkillModel> skills;
  final List<WorkflowModel> workflows;
  final List<String> warnings;
  const ImportPlan({
    required this.skills,
    required this.workflows,
    required this.warnings,
  });
}

/// Summary returned by MarketplaceService.importFromFile (Task 7).
class ImportResult {
  final int skillsAdded;
  final int workflowsAdded;
  final List<String> warnings;
  const ImportResult({
    required this.skillsAdded,
    required this.workflowsAdded,
    required this.warnings,
  });
}

/// Encodes/decodes the `pcskill/1` bundle format. Pure — ID generators are
/// injected so there is no DateTime.now()/randomness inside (testable).
class PcSkillCodec {
  static const formatTag = 'pcskill/1';

  static String encode({
    required List<SkillModel> skills,
    List<WorkflowModel> workflows = const [],
    required String exportedAtIso,
  }) {
    return jsonEncode({
      'format': formatTag,
      'exportedAt': exportedAtIso,
      'skills': skills.map((s) => s.toJson()).toList(),
      'workflows': workflows.map((w) => w.toJson()).toList(),
    });
  }

  /// Decodes a bundle, re-minting all IDs and rewiring workflow step refs.
  /// Throws [FormatException] on malformed JSON or unknown format.
  static ImportPlan decode(
    String jsonStr, {
    required String Function() newSkillId,
    required String Function() newWorkflowId,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (e) {
      throw const FormatException('Not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a pcskill bundle');
    }
    if (decoded['format'] != formatTag) {
      throw FormatException('Unsupported format: ${decoded['format']}');
    }

    final warnings = <String>[];
    final idMap = <String, String>{}; // oldSkillId -> newSkillId

    final rawSkills = (decoded['skills'] as List<dynamic>? ?? []);
    final skills = <SkillModel>[];
    for (final raw in rawSkills) {
      final original = SkillModel.fromJson(raw as Map<String, dynamic>);
      final newId = newSkillId();
      idMap[original.id] = newId;
      skills.add(SkillModel(
        id: newId,
        name: original.name,
        description: original.description,
        version: original.version,
        steps: original.steps,
        createdAt: original.createdAt,
        useCount: 0,
      ));
    }

    final rawWorkflows = (decoded['workflows'] as List<dynamic>? ?? []);
    final workflows = <WorkflowModel>[];
    for (final raw in rawWorkflows) {
      final original = WorkflowModel.fromJson(raw as Map<String, dynamic>);
      final rewired = <String>[];
      for (final oldStepId in original.stepSkillIds) {
        final mapped = idMap[oldStepId];
        if (mapped == null) {
          warnings.add(
            'Workflow "${original.name}" references missing skill '
            '$oldStepId — step dropped.',
          );
        } else {
          rewired.add(mapped);
        }
      }
      workflows.add(WorkflowModel(
        id: newWorkflowId(),
        name: original.name,
        description: original.description,
        triggerType: original.triggerType,
        stepSkillIds: rewired,
        createdAt: original.createdAt,
      ));
    }

    return ImportPlan(skills: skills, workflows: workflows, warnings: warnings);
  }
}
```

> Implementer note: confirm `WorkflowModel`'s constructor parameter names
> (`triggerType`, `stepSkillIds`) and `SkillModel`'s (`useCount`,
> `description`, `version`) by reading the two model files before writing.
> The field list above matches the spec; adjust only if the actual
> constructors differ.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/marketplace/pcskill_codec_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/marketplace/pcskill_codec.dart test/services/marketplace/pcskill_codec_test.dart
git commit -m "feat(marketplace): add PcSkillCodec with id re-mint + ref rewire"
```

---

### Task 7: MarketplaceService — export (share) + import (file picker)

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/services/marketplace/marketplace_service.dart`
- Test: `test/services/marketplace/marketplace_service_test.dart`

**Interfaces:**
- Consumes: `PcSkillCodec`, `ImportResult` (Task 6); `SkillStore.instance.save/get`, `WorkflowStore.instance.save`; `SkillModel`, `WorkflowModel`.
- Produces:
  - `MarketplaceService.instance` (singleton), `init()`/`dispose()` no-ops.
  - `Future<void> exportBundle({required List<SkillModel> skills, List<WorkflowModel> workflows = const [], required String suggestedName})` — writes a temp `<name>.pcskill` and opens the share sheet.
  - `Future<ImportResult?> importFromFile()` — opens file picker, reads the file, decodes, saves skills then workflows, returns a summary (null if user cancels).
  - `Future<ImportResult> importFromString(String contents)` — the testable core (no picker/IO): decode + save + return summary.
  - `@visibleForTesting` seams: `Future<String?> Function()? filePickOverride;` (returns file contents) and `Future<void> Function(String path, String name)? shareOverride;`.

- [ ] **Step 1: Add share_plus to pubspec.yaml**

Under `dependencies:` (near `file_picker: ^11.0.2`):

```yaml
  share_plus: ^10.1.4
```

Run: `flutter pub get`
Expected: resolves successfully.

- [ ] **Step 2: Write the failing test**

```dart
// test/services/marketplace/marketplace_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketclaw/services/marketplace/marketplace_service.dart';
import 'package:pocketclaw/services/marketplace/pcskill_codec.dart';
import 'package:pocketclaw/services/skill_engine/skill_store.dart';
import 'package:pocketclaw/services/skill_engine/skill_model.dart';
import 'package:pocketclaw/services/workflow_engine/workflow_store.dart';
import 'package:pocketclaw/services/primitive_engine/primitive_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarketplaceService.importFromString', () {
    setUp(() async {
      Hive.init('test/hive_test_db');
      await SkillStore.instance.init();
      await WorkflowStore.instance.init();
    });

    tearDown(() async {
      await SkillStore.instance.box.clear();
      await WorkflowStore.instance.box.clear();
    });

    test('imports skills and workflows from a bundle, re-minting ids', () async {
      final bundle = PcSkillCodec.encode(
        skills: [
          SkillModel(
            id: 'old-s',
            name: 'Imported Skill',
            steps: const [PrimitiveStep(primitive: 'back')],
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        exportedAtIso: '2026-06-26T00:00:00.000Z',
      );

      final result =
          await MarketplaceService.instance.importFromString(bundle);

      expect(result.skillsAdded, 1);
      expect(result.workflowsAdded, 0);
      final saved = SkillStore.instance.getAll();
      expect(saved.length, 1);
      expect(saved.single.name, 'Imported Skill');
      expect(saved.single.id, isNot('old-s')); // re-minted
    });

    test('throws/returns gracefully on a bad bundle', () async {
      expect(
        () => MarketplaceService.instance.importFromString('{"format":"x"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/services/marketplace/marketplace_service_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 4: Write minimal implementation**

```dart
// lib/services/marketplace/marketplace_service.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../skill_engine/skill_model.dart';
import '../skill_engine/skill_store.dart';
import '../workflow_engine/workflow_model.dart';
import '../workflow_engine/workflow_store.dart';
import 'pcskill_codec.dart';

/// Exports/imports `.pcskill` bundles. Export uses the system share sheet;
/// import uses the file picker. All file logic lives behind testable seams.
class MarketplaceService {
  MarketplaceService._();
  static final MarketplaceService instance = MarketplaceService._();

  Future<void> init() async {}
  Future<void> dispose() async {}

  @visibleForTesting
  Future<String?> Function()? filePickOverride;
  @visibleForTesting
  Future<void> Function(String path, String name)? shareOverride;

  int _idCounter = 0;

  String _mintSkillId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = ((ts + _idCounter++) % 99999).toString().padLeft(5, '0');
    return 'skill-$ts-$suffix';
  }

  String _mintWorkflowId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = ((ts + _idCounter++) % 99999).toString().padLeft(5, '0');
    return 'wf-$ts-$suffix';
  }

  /// Writes a temp `.pcskill` and opens the share sheet.
  Future<void> exportBundle({
    required List<SkillModel> skills,
    List<WorkflowModel> workflows = const [],
    required String suggestedName,
  }) async {
    final json = PcSkillCodec.encode(
      skills: skills,
      workflows: workflows,
      exportedAtIso: DateTime.now().toUtc().toIso8601String(),
    );
    final safe = suggestedName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final fileName = '$safe.pcskill';

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsString(json);

    if (shareOverride != null) {
      await shareOverride!(path, fileName);
      return;
    }
    await Share.shareXFiles([XFile(path)], subject: fileName);
  }

  /// Opens the picker, reads the chosen file, imports it. Null if cancelled.
  Future<ImportResult?> importFromFile() async {
    final String? contents;
    if (filePickOverride != null) {
      contents = await filePickOverride!();
    } else {
      final picked = await FilePicker.pickFiles(withData: false);
      if (picked == null || picked.files.isEmpty) return null;
      final path = picked.files.single.path;
      if (path == null) return null;
      contents = await File(path).readAsString();
    }
    if (contents == null) return null;
    return importFromString(contents);
  }

  /// Testable core: decode + save skills then workflows + summarize.
  Future<ImportResult> importFromString(String contents) async {
    final plan = PcSkillCodec.decode(
      contents,
      newSkillId: _mintSkillId,
      newWorkflowId: _mintWorkflowId,
    );
    for (final s in plan.skills) {
      await SkillStore.instance.save(s);
    }
    for (final w in plan.workflows) {
      await WorkflowStore.instance.save(w);
    }
    return ImportResult(
      skillsAdded: plan.skills.length,
      workflowsAdded: plan.workflows.length,
      warnings: plan.warnings,
    );
  }
}
```

> Verified: the existing call is `FilePicker.pickFiles(...)` (chat_screen.dart:240,
> file_picker ^11) — use that form, not `FilePicker.platform.pickFiles`. The
> doc picker passes `type: FileType.custom` + `allowedExtensions`; for `.pcskill`
> use `FilePicker.pickFiles(withData: false)` (no type filter) and rely on the
> codec's `format`-field check as the real gate — custom extensions are
> unreliable on Android. Confirm `SkillStore.instance.save` /
> `WorkflowStore.instance.save` signatures by reading the stores.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/services/marketplace/marketplace_service_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/marketplace/marketplace_service.dart test/services/marketplace/marketplace_service_test.dart
git commit -m "feat(marketplace): add MarketplaceService export/import + share_plus"
```

---

### Task 8: UI wiring — export from Skills/Workflows, import in chat, main.dart init

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/skills_screen.dart`
- Modify: `lib/screens/workflows_screen.dart`
- Modify: `lib/screens/chat_screen.dart`

**Context:** `main.dart` init sequence ends with the Phase 3 block (`...BackgroundTaskEngine.instance.init();`). `WorkflowsScreen` (lib/screens/workflows_screen.dart) already has a long-press → delete-confirm dialog; `SkillsScreen` (lib/screens/skills_screen.dart) lists skills. `chat_screen.dart` has a `PopupMenuButton` with `'clear'`, `'skills'`, `'workflows'` items (around line 1320).

**Interfaces:**
- Consumes: `DynamicUiService.instance.init()`, `MarketplaceService.instance` (export/import), `SkillStore`/`WorkflowStore` getters, `SkillEngine.instance.list()` or `SkillStore.instance.get`.
- Produces: working export/import entry points; both new services initialized at startup.

- [ ] **Step 1: Add init calls to main.dart**

Add imports (after the Phase 3 service imports):

```dart
import 'services/dynamic_ui/dynamic_ui_service.dart';
import 'services/marketplace/marketplace_service.dart';
```

After `await BackgroundTaskEngine.instance.init();`:

```dart
  await DynamicUiService.instance.init();
  await MarketplaceService.instance.init();
```

- [ ] **Step 2: Add "Import skill…" to the chat PopupMenu**

In `chat_screen.dart`, add to the `PopupMenuButton.onSelected` handler (after the `'workflows'` branch):

```dart
              } else if (value == 'import_skill') {
                await _importSkillBundle();
              }
```

> Implementer note: if `onSelected` is not already `async`, make it
> `(value) async { ... }`.

Add to `itemBuilder` (after the workflows item) — note this list may need to
drop `const` if other items are non-const after editing:

```dart
              const PopupMenuItem(
                value: 'import_skill',
                child: Text('Import skill…'),
              ),
```

Add the handler to `_ChatScreenState`:

```dart
  Future<void> _importSkillBundle() async {
    try {
      final result = await MarketplaceService.instance.importFromFile();
      if (!mounted) return;
      if (result == null) return; // cancelled
      final msg = StringBuffer(
        'Added ${result.skillsAdded} skill'
        '${result.skillsAdded == 1 ? '' : 's'}',
      );
      if (result.workflowsAdded > 0) {
        msg.write(', ${result.workflowsAdded} workflow'
            '${result.workflowsAdded == 1 ? '' : 's'}');
      }
      if (result.warnings.isNotEmpty) {
        msg.write(' (${result.warnings.length} warning'
            '${result.warnings.length == 1 ? '' : 's'})');
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg.toString())));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid .pcskill file')),
      );
    }
  }
```

Add the import at the top of `chat_screen.dart`:

```dart
import '../services/marketplace/marketplace_service.dart';
```

- [ ] **Step 3: Add Export to SkillsScreen (long-press)**

In `skills_screen.dart`, wrap each skill row in a `GestureDetector` with
`onLongPress` that shows a bottom sheet / dialog offering "Export". On tap:

```dart
  Future<void> _exportSkill(SkillModel skill) async {
    await MarketplaceService.instance.exportBundle(
      skills: [skill],
      suggestedName: skill.name,
    );
  }
```

Wire a long-press menu (mirror WorkflowsScreen's long-press delete pattern):

```dart
            onLongPress: () async {
              final action = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: PocketClawTheme.bg2,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.ios_share,
                            color: PocketClawTheme.cyan),
                        title: Text('Export',
                            style: Theme.of(ctx).textTheme.bodyMedium),
                        onTap: () => Navigator.pop(ctx, 'export'),
                      ),
                    ],
                  ),
                ),
              );
              if (action == 'export') await _exportSkill(skill);
            },
```

Add imports to `skills_screen.dart`:

```dart
import '../core/pocketclaw_theme.dart'; // if not already imported
import '../services/marketplace/marketplace_service.dart';
```

> Implementer note: read `skills_screen.dart` first to find the skill row
> widget and the `SkillModel` variable name in its builder; attach the
> `onLongPress` there. Confirm `PocketClawTheme` is already imported.

- [ ] **Step 4: Add Export to WorkflowsScreen (alongside Delete)**

`workflows_screen.dart` currently has `onLongPress: () => _deleteWorkflow(workflow)`.
Replace that direct delete with a bottom sheet offering Export + Delete:

```dart
                  onLongPress: () async {
                    final action = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: PocketClawTheme.bg2,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.ios_share,
                                  color: PocketClawTheme.cyan),
                              title: Text('Export',
                                  style: Theme.of(ctx).textTheme.bodyMedium),
                              onTap: () => Navigator.pop(ctx, 'export'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline,
                                  color: PocketClawTheme.error),
                              title: Text('Delete',
                                  style: Theme.of(ctx).textTheme.bodyMedium),
                              onTap: () => Navigator.pop(ctx, 'delete'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!mounted) return;
                    if (action == 'export') {
                      await _exportWorkflow(workflow);
                    } else if (action == 'delete') {
                      await _deleteWorkflow(workflow);
                    }
                  },
```

Add the export handler — it bundles the workflow WITH its referenced skills:

```dart
  Future<void> _exportWorkflow(WorkflowModel workflow) async {
    final skills = <SkillModel>[];
    for (final id in workflow.stepSkillIds) {
      final s = SkillStore.instance.get(id);
      if (s != null) skills.add(s);
    }
    await MarketplaceService.instance.exportBundle(
      skills: skills,
      workflows: [workflow],
      suggestedName: workflow.name,
    );
  }
```

Add imports to `workflows_screen.dart`:

```dart
import '../services/marketplace/marketplace_service.dart';
import '../services/skill_engine/skill_store.dart';
import '../services/skill_engine/skill_model.dart';
```

> Implementer note: `_deleteWorkflow` and the `workflow` variable already
> exist in the builder. Confirm `SkillStore.instance.get` returns
> `SkillModel?`.

- [ ] **Step 5: Run the full suite + analyze**

Run: `flutter test`
Expected: All pass (no new tests this task — it is UI wiring verified by the build + existing tests).

Run: `flutter analyze lib/main.dart lib/screens/skills_screen.dart lib/screens/workflows_screen.dart lib/screens/chat_screen.dart`
Expected: No issues found (fix any `const`/import warnings).

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/screens/skills_screen.dart lib/screens/workflows_screen.dart lib/screens/chat_screen.dart
git commit -m "feat(marketplace): wire export/import UI + init dynamic-ui & marketplace services"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Dynamic Components renderer (Core 4) → Tasks 1–3, 5. ✓
- Two sources (model pcui blocks + render_component primitive) → Task 4 (primitive) + Task 5 (chat detection). ✓
- Degrade-to-text on bad spec → Task 2 (`parse` returns null), Task 5 (malformed-block test). ✓
- Buttons re-enter ChatCommandService → Task 5 (`onCommand` → existing send path). ✓
- Model prompting (Source A enablement) → Task 5 Step 3c. ✓
- `.pcskill` bundle format + import algorithm (id re-mint, ref rewire, warnings) → Task 6. ✓
- Export via share_plus, import via file_picker → Task 7. ✓
- UI entry points (Skills export, Workflows export, chat Import) → Task 8. ✓
- main.dart init of both services → Task 8. ✓
- Tests for parse, extractBlocks, codec, primitive, widget rendering → Tasks 1,2,3,4,6,7. ✓

**Placeholder scan:** No "TBD"/"handle edge cases". Implementer notes name exactly what to confirm (existing method names) — these are verification directives, not deferred logic.

**Type consistency:** `ComponentSpec`/`ListItem`/`KvRow`/`UiButton` consistent across Tasks 1,3,5. `ImportPlan`/`ImportResult` consistent across Tasks 6,7. `PcSkillCodec.encode/decode` signatures match between definition (6) and use (7). `render_component` args shape (`{'spec': {...}}`) consistent across Tasks 4 (primitive) and the pcui JSON it emits (5).

**Known cross-task verification points (flagged for implementers):** real send-handler + controller name in chat_screen (Task 5); `FilePicker.pickFiles` exact API (Task 7); `SkillModel`/`WorkflowModel` constructor param names (Task 6). Each is called out inline.
