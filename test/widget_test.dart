// Smoke test for the app's widget tree.
//
// Feature-level tests land alongside their milestones. This just verifies a
// widget tree boots without throwing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a MaterialApp', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('ok'))),
    );

    expect(find.text('ok'), findsOneWidget);
  });
}
