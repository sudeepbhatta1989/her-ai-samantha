import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HerAIApp());
    expect(find.byType(HerAIApp), findsOneWidget);
  });
}
