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
