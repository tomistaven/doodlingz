import 'package:flutter_test/flutter_test.dart';
import 'package:doodlingz/main.dart';

void main() {
  testWidgets('smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DoodlingzApp());
    expect(find.text('Doodlingz'), findsOneWidget);
  });
}