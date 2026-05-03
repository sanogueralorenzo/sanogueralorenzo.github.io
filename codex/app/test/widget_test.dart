import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('shows initial disconnected state', (WidgetTester tester) async {
    await tester.pumpWidget(const PilotApp());

    expect(find.text('PiLOT'), findsOneWidget);
    expect(find.text('Codex Hub'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('No runs yet'), findsOneWidget);
  });

  testWidgets('renders disabled run controls', (WidgetTester tester) async {
    await tester.pumpWidget(const PilotApp());

    expect(find.text('New Run'), findsOneWidget);
    expect(find.text('Server Settings'), findsOneWidget);
  });
}
