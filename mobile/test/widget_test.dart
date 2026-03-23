import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('Signtone app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SigntoneApp());
    expect(find.byType(SigntoneApp), findsOneWidget);
  });
}
