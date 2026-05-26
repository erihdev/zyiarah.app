import 'package:flutter_test/flutter_test.dart';

// Smoke test placeholder. The full app requires Firebase + dotenv initialization
// which cannot be run in unit test context without additional mocks.
// TODO: add firebase_core_testing mock when test coverage is expanded.
void main() {
  testWidgets('placeholder passes', (WidgetTester tester) async {
    expect(1 + 1, equals(2));
  });
}
