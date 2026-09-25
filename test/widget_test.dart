import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_cleaner/api_client.dart';
import 'package:clean_cleaner/format.dart';
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

  group('models', () {
    test('Cleaner: bio, and accepting bookings unless explicitly paused', () {
      Cleaner parse(Map<String, dynamic> extra) => Cleaner.fromJson({'id': 1, 'name': 'Lucy', ...extra});
      expect(parse({}).acceptingBookings, isTrue); // column missing -> accepting
      expect(parse({'accepting_bookings': true}).acceptingBookings, isTrue);
      expect(parse({'accepting_bookings': false}).acceptingBookings, isFalse);
      expect(parse({'bio': 'Ten years cleaning'}).bio, 'Ten years cleaning');
    });

    test('CleanerBooking reads the joined service, contact details and job timestamps', () {
      final b = CleanerBooking.fromJson({
        'id': 7,
        'ref': 'SS-ABC123',
        'date': '2026-09-30',
        'start_time': '11:00',
        'end_time': '13:00',
        'status': 'confirmed',
        'service_id': 2,
        'phone': '0782814983',
        'notes': 'Key in lockbox',
        'duration_minutes': 120,
        'started_at': '2026-09-30T10:02:00Z',
        'services': {'name': 'Deep cleaning', 'slug': 'deep', 'features': '["Oven","Fridge"]'},
      });
      expect(b.serviceName, 'Deep cleaning');
      expect(b.serviceSlug, 'deep');
      expect(b.serviceFeatures, ['Oven', 'Fridge']);
      expect(b.phone, '0782814983');
      expect(b.notes, 'Key in lockbox');
      expect(b.startsAt, DateTime(2026, 9, 30, 11));
      expect(b.inProgress, isTrue);
      // Old rows (no joined features, no timestamps) still parse.
      final old = CleanerBooking.fromJson({'id': 8, 'status': 'pending', 'services': {'name': 'Standard', 'features': 'not json'}});
      expect(old.serviceFeatures, isEmpty);
      expect(old.inProgress, isFalse);
      expect(old.startsAt, isNull);
    });

    test('unread customer messages are counted per booking', () {
      ChatMessage m(int id, int booking, String role, {bool read = false}) => ChatMessage.fromJson({
            'id': id,
            'booking_id': booking,
            'sender_role': role,
            'body': 'x',
            'created_at': '2026-09-25T10:00:00Z',
            'read_at': read ? '2026-09-25T10:05:00Z' : null,
          });
      final counts = unreadByBooking([
        m(1, 7, 'customer'),
        m(2, 7, 'customer'),
        m(3, 7, 'cleaner'), // mine
        m(4, 8, 'customer', read: true),
        m(5, 9, 'customer'),
      ]);
      expect(counts, {7: 2, 9: 1});
    });

    test('Review, TimeOff and JobPhoto parse', () {
      final r = Review.fromJson({'booking_id': 7, 'rating': 5, 'tags': ['On time'], 'tip_cents': 500, 'reviewer_name': 'Emma R.'});
      expect((r.rating, r.tipCents), (5, 500));
      expect(r.tags, ['On time']);
      expect(TimeOff.fromJson({'id': 1, 'date': '2026-10-02', 'reason': null}).date, DateTime(2026, 10, 2));
      final p = JobPhoto.fromJson({'id': 3, 'booking_id': 7, 'kind': 'after', 'path': '7/after/1.jpg'}, url: 'https://x');
      expect((p.kind, p.url), ('after', 'https://x'));
    });

    test('format helpers', () {
      expect(shortDate(DateTime(2026, 9, 29)), 'Tue, 29 Sep');
      expect(daysUntil(DateTime(2026, 10, 1), DateTime(2026, 9, 30, 23)), 1);
      expect(toMinutes('09:30'), 570);
      expect(durationText(150), '2h 30m');
    });
  });
}
