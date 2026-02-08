import 'package:daiko_kun_driver/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: DaikoDriverApp()));

    // Verify that the app builds successfully.
    expect(find.byType(DaikoDriverApp), findsOneWidget);
  });
}
