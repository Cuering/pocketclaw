// test/widget_test.dart
//
// Smoke test: verify the app boots and the Gemma diagnostic screen renders.
// We don't test Gemma calls here because they require the model on disk and
// a real device. Those are manual / integration tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:pocketclaw/main.dart';

void main() {
  testWidgets('PocketClaw app boots and shows the Gemma test screen', (
    WidgetTester tester,
  ) async {
    // pumpWidget: builds the widget tree and triggers a frame.
    await tester.pumpWidget(const PocketClawApp());

    // Verify the diagnostic screen rendered.
    // We check for the AppBar title — a stable, visible string.
    expect(find.text('PocketClaw — Gemma Test'), findsOneWidget);

    // Verify the three diagnostic buttons are present.
    expect(find.text('1. Install'), findsOneWidget);
    expect(find.text('2. Load'), findsOneWidget);
    expect(find.text('3. Generate'), findsOneWidget);
  });
}
