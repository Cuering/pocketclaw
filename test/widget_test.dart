// test/widget_test.dart
//
// Smoke test: verify the app shell builds.
// We don't test Gemma calls here because they require the model on disk and
// a real device. Those are manual / integration tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:pocketclaw/main.dart';

void main() {
  testWidgets('PocketClaw app boots', (WidgetTester tester) async {
    // pumpWidget: builds the widget tree and triggers a frame.
    await tester.pumpWidget(const PocketClawApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
