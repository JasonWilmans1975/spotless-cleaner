import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_cleaner/api_client.dart';
import 'package:clean_cleaner/format.dart';
import 'package:clean_cleaner/links.dart';
import 'package:clean_cleaner/main.dart';
import 'package:clean_cleaner/screens/add_service_screen.dart';
import 'package:clean_cleaner/screens/chat_screen.dart';
import 'package:clean_cleaner/screens/edit_service_details_screen.dart';
import 'package:clean_cleaner/screens/job_screen.dart';
import 'package:clean_cleaner/screens/schedule_tab.dart';
import 'package:clean_cleaner/screens/service_form.dart';
import 'package:clean_cleaner/screens/services_tab.dart';
import 'package:clean_cleaner/service_icons.dart';
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

  CleanerBooking job(int id, String date, String status,
          {int price = 4400, String start = '11:00', String end = '13:00', int minutes = 120, String email = 'liam@example.com'}) =>
      CleanerBooking.fromJson({
        'id': id,
        'ref': 'SS-$id',
        'date': date,
        'start_time': start,
        'end_time': end,
        'status': status,
        'customer_name': 'Liam Customer',
        'email': email,
        'address': '10 Corsica Avenue',
        'postcode': 'SW1A 1AA',
        'price_cents': price,
        'duration_minutes': minutes,
        'services': {'name': 'Deep cleaning', 'slug': 'deep'},
      });

  group('schedule logic', () {
    final now = DateTime(2026, 9, 30, 10); // a Wednesday

    test('weekStart is Monday', () {
      expect(weekStart(now), DateTime(2026, 9, 28));
      expect(weekStart(DateTime(2026, 10, 4, 23)), DateTime(2026, 9, 28)); // Sunday
    });

    test('weekSummary counts confirmed + completed jobs in this week only', () {
      final summary = weekSummary([
        job(1, '2026-09-28', 'completed', price: 2400, minutes: 0, start: '09:00', end: '13:00'), // 4h from times
        job(2, '2026-10-04', 'confirmed', price: 4400, minutes: 120),
        job(3, '2026-09-30', 'pending'), // not booked yet
        job(4, '2026-09-29', 'cancelled'),
        job(5, '2026-10-05', 'confirmed'), // next week
      ], now);
      expect(summary, (bookedCents: 6800, jobs: 2, minutes: 360));
      expect(hoursLabel(360), '6h');
      expect(hoursLabel(390), '6.5h');
    });

    test('previousBookingsWith matches the customer and ignores cancellations', () {
      final request = job(1, '2026-10-01', 'pending');
      expect(previousBookingsWith(request, [request]), 0);
      expect(
        previousBookingsWith(request, [
          request,
          job(2, '2026-09-01', 'completed', email: 'LIAM@example.com'),
          job(3, '2026-09-10', 'cancelled'),
          job(4, '2026-09-12', 'completed', email: 'someone@else.com'),
        ]),
        1,
      );
    });

    test('mapsUri picks Apple Maps on iOS, Google Maps elsewhere', () {
      expect(mapsUri('10 Corsica Ave', platform: TargetPlatform.iOS).toString(), 'https://maps.apple.com/?daddr=10+Corsica+Ave');
      expect(mapsUri('10 Corsica Ave', platform: TargetPlatform.android).host, 'www.google.com');
    });
  });

  Future<List<(int, bool)>> pumpSchedule(WidgetTester tester, double width, {Cleaner? cleaner}) async {
    tester.view.physicalSize = Size(width * 3, 932 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final sent = <(int, bool)>[];
    final today = DateTime.now();
    String inDays(int d) => isoDate(today.add(Duration(days: d)));
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: ScheduleTab(
        cleaner: cleaner ?? Cleaner.fromJson({'id': 1, 'name': 'Liam Test', 'status': 'approved', 'active': 1}),
        bookings: [
          job(1, inDays(1), 'pending'),
          job(2, inDays(2), 'confirmed'),
          job(3, inDays(-3), 'completed'),
        ],
        loading: false,
        onRefresh: () async {},
        onCleanerUpdated: (_) {},
        onOpenEarnings: () {},
        unread: const {2: 3},
        sendDecision: (id, accept) async => sent.add((id, accept)),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    return sent;
  }

  for (final width in [375.0, 430.0]) {
    testWidgets('Schedule lays out at ${width.toInt()}pt', (tester) async {
      await pumpSchedule(tester, width);
      expect(find.text('Accepting new bookings'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('1 awaiting you'), findsOneWidget);
      expect(find.text('Liam Customer · booked you 2 times before'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Directions'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('3'), findsOneWidget); // unread messages on the upcoming job
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Accept waits out the undo window, then sends once', (tester) async {
    final sent = await pumpSchedule(tester, 390);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(find.textContaining('Accepted — Deep cleaning'), findsOneWidget);
    await tester.pump(kUndoWindow - const Duration(seconds: 1));
    expect(sent, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(sent, [(1, true)]);
  });

  testWidgets('Undo cancels a decline before it is sent', (tester) async {
    final sent = await pumpSchedule(tester, 390);
    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump(kUndoWindow * 2);
    expect(sent, isEmpty);
    expect(find.text('Accept'), findsOneWidget); // request card is back
  });

  testWidgets('availability switch is off and locked while awaiting approval', (tester) async {
    await pumpSchedule(tester, 390, cleaner: Cleaner.fromJson({'id': 1, 'name': 'Liam', 'status': 'pending', 'active': 0}));
    expect(find.text('Not bookable yet'), findsOneWidget);
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect((sw.value, sw.onChanged), (false, null));
  });

  CleanerBooking jobWith(Map<String, dynamic> extra) => CleanerBooking.fromJson({
        'id': 21,
        'ref': 'SS-504215',
        'date': isoDate(DateTime.now()),
        'start_time': '11:00',
        'end_time': '13:00',
        'status': 'confirmed',
        'customer_name': 'Liam Customer',
        'email': 'liam@example.com',
        'phone': '0782814983',
        'address': '10 Corsica Avenue',
        'postcode': 'SW1A 1AA',
        'price_cents': 4400,
        'duration_minutes': 120,
        'services': {'name': 'Deep cleaning', 'slug': 'deep', 'features': '["Dust all surfaces","Kitchen deep clean","Bathrooms descaled"]'},
        ...extra,
      });

  group('job logic', () {
    final now = DateTime(2026, 9, 30, 10);
    test('jobPhase', () {
      JobPhase phase(Map<String, dynamic> extra) => jobPhase(jobWith({'date': '2026-09-30', ...extra}), now);
      expect(phase({'status': 'pending'}), JobPhase.request);
      expect(phase({}), JobPhase.ready);
      expect(phase({'date': '2026-10-02'}), JobPhase.upcoming);
      expect(phase({'started_at': '2026-09-30T09:00:00Z'}), JobPhase.inProgress);
      expect(phase({'status': 'completed'}), JobPhase.done);
      expect(phase({'status': 'cancelled'}), JobPhase.cancelled);
    });

    test('elapsedText', () {
      expect(elapsedText(const Duration(minutes: 12, seconds: 3)), '12:03');
      expect(elapsedText(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
    });
  });

  for (final width in [375.0, 430.0]) {
    testWidgets('Job details lays out in every phase at ${width.toInt()}pt', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Future<void> pumpJob(Map<String, dynamic> extra, String expected) async {
        await tester.pumpWidget(MaterialApp(theme: SpotlessTheme.light(), home: JobScreen(key: UniqueKey(), booking: jobWith(extra))));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(expected), findsOneWidget);
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 4; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(tester.takeException(), isNull);
      }

      await pumpJob({}, 'Start job'); // ready today
      await pumpJob({'started_at': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String()}, 'Finish job');
      await pumpJob({'status': 'completed'}, 'Job completed');
      await pumpJob({'status': 'pending'}, 'Awaiting your answer');
      await pumpJob({'status': 'cancelled'}, 'Cancelled');
      await tester.pumpWidget(const SizedBox()); // stop the in-progress ticker
    });
  }

  testWidgets('Job details: start is locked before the day; checklist ticks count up', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: JobScreen(booking: jobWith({'id': 22, 'date': isoDate(DateTime.now().add(const Duration(days: 2)))})),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('You can start on the day of the clean.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start job')).onPressed, isNull);
    expect(find.byTooltip('Call customer'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kitchen deep clean'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('0 of 3 done'), findsOneWidget);
    await tester.tap(find.text('Kitchen deep clean'));
    await tester.pump();
    expect(find.text('1 of 3 done'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chat screen lays out with quick replies and a send button', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: SpotlessTheme.light(), home: ChatScreen(booking: jobWith({}))));
    await tester.pumpAndSettle();
    expect(find.text('Liam Customer'), findsOneWidget);
    expect(find.text('On my way'), findsOneWidget);
    expect(find.text("Couldn't load messages"), findsOneWidget); // no Supabase in tests
    IconButton send() => tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Send'), matching: find.byType(IconButton)));
    expect(send().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Running 5 minutes late');
    await tester.pump();
    expect(send().onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  test('parsePriceCents: blank or junk means "use the default"', () {
    expect(parsePriceCents(''), isNull);
    expect(parsePriceCents('  '), isNull);
    expect(parsePriceCents('abc'), isNull);
    expect(parsePriceCents('17'), 1700);
    expect(parsePriceCents('£17.50'), 1750);
    expect(parsePriceCents('22.999'), 2300);
  });

  test('service icons: known glyphs map to outline icons, others stay text', () {
    expect(iconForGlyph('⌂'), isNotNull);
    expect(iconForGlyph(' ✦ '), isNotNull);
    expect(iconForGlyph(':)'), isNull);
    expect(kServiceIcons.map((o) => o.glyph).toSet(), hasLength(6)); // no duplicate glyphs
  });

  testWidgets('ServiceIconTile draws an icon for known glyphs and text for old ones', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: const Scaffold(body: Row(children: [ServiceIconTile('⌂'), ServiceIconTile(':)')])),
    ));
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text(':)'), findsOneWidget);
  });

  testWidgets('My services shows a retryable error when loading fails', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: SpotlessTheme.light(), home: const ServicesTab(cleanerId: 1)));
    await tester.pumpAndSettle();
    expect(find.text('My services'), findsOneWidget);
    expect(find.text("Couldn't load your services"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(375.0, 1.0), (375.0, 1.3), (430.0, 1.0)]) {
    testWidgets('service card with every action fits at ${width.toInt()}pt, text x$scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final service = MenuService.fromJson({
        'id': 5,
        'name': 'End-of-tenancy deep clean with oven',
        'icon': '⇄',
        'price_type': 'hourly',
        'price_cents': 16000,
        'created_by_cleaner_id': 1,
      });
      await tester.pumpWidget(MaterialApp(
        theme: SpotlessTheme.light(),
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(20), children: [
            MyServiceCard(
              service: service,
              rate: MyServiceRate(serviceId: 5, priceCents: 2400),
              busy: false,
              onEditRate: () {},
              onRemove: () {},
              onEditDetails: () {},
            ),
          ]),
        ),
      ));
      expect(find.text('Proposed by you'), findsOneWidget);
      expect(find.text('Default £160'), findsOneWidget);
      expect(find.text('£24'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  MenuService menu(int id, String name, {String icon = '⌂', String type = 'hourly', int cents = 1700, int? mine, String status = 'approved'}) =>
      MenuService.fromJson({
        'id': id,
        'name': name,
        'icon': icon,
        'price_type': type,
        'price_cents': cents,
        'duration_minutes': 120,
        'duration_label': '2–4 hours',
        'features': '["Oven","Hob"]',
        'status': status,
        'created_by_cleaner_id': mine,
      });

  test('service form: feature lines, prefill and keeping an old icon', () {
    expect(featureLines(' Oven \n\nHob\n '), ['Oven', 'Hob']);
    final fresh = ServiceFormController();
    expect((fresh.icon, fresh.priceType, fresh.name.text), (kDefaultServiceGlyph, 'hourly', ''));
    final old = ServiceFormController(menu(9, 'Test clean', icon: ':)', type: 'fixed', cents: 2450));
    expect((old.icon, old.originalIcon, old.priceType, old.price.text), (':)', ':)', 'fixed', '24.50'));
    expect(old.features.text, 'Oven\nHob');
    fresh.dispose();
    old.dispose();
  });

  for (final (width, scale) in [(375.0, 1.0), (375.0, 1.3), (430.0, 1.0)]) {
    testWidgets('Add a service at ${width.toInt()}pt, text x$scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        theme: SpotlessTheme.light(),
        home: AddServiceScreen(
          availableServices: [menu(1, 'Standard home cleaning'), menu(2, 'End-of-tenancy cleaning', icon: '⇄', type: 'fixed', cents: 16000)],
          currentRates: const [],
        ),
      ));
      await tester.pumpAndSettle();
      FilledButton bottom() => tester.widget<FilledButton>(find.byType(FilledButton).last);
      expect(find.text('Select a service to add'), findsOneWidget);
      expect(bottom().onPressed, isNull);

      await tester.tap(find.text('Standard home cleaning'));
      await tester.pumpAndSettle();
      expect(find.text('Add selected (1)'), findsOneWidget);
      expect(find.text('Your rate (optional)'), findsOneWidget);

      await tester.tap(find.text('Propose new'));
      await tester.pumpAndSettle();
      expect(find.text('Send for review'), findsOneWidget);
      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a service name'), findsOneWidget);
      final list = find.byType(Scrollable).last;
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Edit service keeps an old icon as "Current" and lays out', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 932 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: EditServiceDetailsScreen(service: menu(9, 'Test app clean', icon: ':)', mine: 1, status: 'pending')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Current'), findsOneWidget);
    expect(find.textContaining('awaiting admin approval'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
