import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the title is present
    expect(find.text('تحميل الفيديوهات'), findsOneWidget);
  });
}
