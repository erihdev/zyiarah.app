import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/main.dart';

void main() {
  testWidgets('App starts test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ZyiarahApp());

    // Verify that onboarding screen is shown (contains specific text)
    expect(find.text('أهلاً بكِ في زيارة'), findsOneWidget);
  });
}
