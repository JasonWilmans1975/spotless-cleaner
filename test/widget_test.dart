import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_cleaner/main.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:3000'));

  testWidgets('app boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SpotlessCleanerApp());
    expect(find.text('Spotless Cleaner'), findsOneWidget);
  });
}
