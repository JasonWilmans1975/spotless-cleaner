import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_cleaner/main.dart';
import 'package:clean_cleaner/screens/home_screen.dart';
import 'package:clean_cleaner/theme/spotless_theme.dart';
import 'package:clean_cleaner/ui/debug_gallery.dart';
import 'package:clean_cleaner/ui/tiles.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:3000'));

  testWidgets('app boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SpotlessCleanerApp());
    expect(find.text('Spotless Cleaner'), findsOneWidget);
  });

  test('InitialsAvatar takes first and last initials', () {
    expect(InitialsAvatar.initialsOf('Lucy Green'), 'LG');
    expect(InitialsAvatar.initialsOf('sam'), 'S');
    expect(InitialsAvatar.initialsOf(''), '?');
  });

  // Every shared widget (and the cleaner nav bar) renders without overflow at
  // the narrowest and widest target phones — layout overflows throw in tests.
  for (final width in [375.0, 430.0]) {
    testWidgets('widget gallery lays out at ${width.toInt()}pt', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(theme: SpotlessTheme.light(), home: const DebugGallery()));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 14; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(find.byType(CleanerNavBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nav bar shows the pending-requests badge and switches tabs', (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: Scaffold(
        bottomNavigationBar: StatefulBuilder(
          builder: (context, setState) => CleanerNavBar(
            index: selected,
            onSelected: (i) => setState(() => selected = i),
            scheduleBadge: 3,
          ),
        ),
      ),
    ));
    expect(find.text('3'), findsOneWidget);
    for (final label in ['Schedule', 'Earnings', 'Services', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Earnings'));
    await tester.pump();
    expect(selected, 1);
  });
}
