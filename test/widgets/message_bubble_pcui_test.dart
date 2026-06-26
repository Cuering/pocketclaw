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
