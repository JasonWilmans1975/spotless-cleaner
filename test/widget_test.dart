import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:clean_cleaner/api_client.dart';
import 'package:clean_cleaner/format.dart';
import 'package:clean_cleaner/geocode.dart';
import 'package:clean_cleaner/links.dart';
import 'package:clean_cleaner/main.dart';
import 'package:clean_cleaner/screens/add_service_screen.dart';
import 'package:clean_cleaner/screens/chat_screen.dart';
import 'package:clean_cleaner/screens/earnings_tab.dart';
import 'package:clean_cleaner/screens/edit_service_details_screen.dart';
import 'package:clean_cleaner/screens/hours_screen.dart';
import 'package:clean_cleaner/screens/job_screen.dart';
import 'package:clean_cleaner/screens/profile_tab.dart';
import 'package:clean_cleaner/screens/reviews_screen.dart';
import 'package:clean_cleaner/screens/schedule_tab.dart';
import 'package:clean_cleaner/screens/service_form.dart';
import 'package:clean_cleaner/screens/services_tab.dart';
import 'package:clean_cleaner/service_icons.dart';
import 'package:clean_cleaner/screens/home_screen.dart';
import 'package:clean_cleaner/theme/spotless_theme.dart';
import 'package:clean_cleaner/ui/pickers.dart';
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

  test('groupTimeOff joins consecutive days into ranges', () {
    TimeOff off(int id, String date) => TimeOff.fromJson({'id': id, 'date': date});
    final ranges = groupTimeOff([
      off(3, '2026-10-08'),
      off(1, '2026-10-06'),
      off(2, '2026-10-07'),
      off(4, '2026-10-20'),
      off(5, '2026-10-31'),
      off(6, '2026-11-01'), // across a month end
    ]);
    expect(ranges.map(timeOffLabel), ['Tue 6 Oct – Thu 8 Oct', 'Tue 20 Oct', 'Sat 31 Oct – Sun 1 Nov']);
    expect(ranges.first.ids, [1, 2, 3]);
    expect(groupTimeOff([]), isEmpty);
  });

  for (final width in [375.0, 430.0]) {
    testWidgets('Working hours shows a retryable error when loading fails at ${width.toInt()}pt', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: SpotlessTheme.light(), home: const HoursScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Working hours'), findsOneWidget);
      expect(find.text("Couldn't load your hours"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale) in [(375.0, 1.0), (375.0, 1.3), (430.0, 1.0)]) {
    testWidgets('Working hours lays out with hours and time off at ${width.toInt()}pt, text x$scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final soon = DateTime.now().add(const Duration(days: 5));
      await tester.pumpWidget(MaterialApp(
        theme: SpotlessTheme.light(),
        home: HoursScreen(
          loadHours: () async => [
            WorkingHours(weekday: 0, startTime: '08:00', endTime: '16:00'),
            WorkingHours(weekday: 2, startTime: '09:30', endTime: '17:30'),
          ],
          loadTimeOff: () async => [
            TimeOff(id: 1, date: DateUtils.dateOnly(soon)),
            TimeOff(id: 2, date: DateUtils.dateOnly(soon.add(const Duration(days: 1)))),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('08:00 – 16:00'), findsOneWidget);
      expect(find.text('Day off'), findsNWidgets(5));
      await tester.scrollUntilVisible(find.text('2 days off coming up'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Save working hours'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Editing a day opens the From / Until sheet.
      await tester.scrollUntilVisible(find.text('08:00 – 16:00'), -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('08:00 – 16:00'));
      await tester.pumpAndSettle();
      expect(find.text('Monday hours'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('withAvatar keeps the bio and the booking pause', () {
    final c = Cleaner.fromJson({'id': 1, 'name': 'Lucy', 'bio': 'Ten years', 'accepting_bookings': false, 'status': 'approved', 'active': 1});
    final updated = c.withAvatar('https://x/1.jpg');
    expect((updated.avatar, updated.bio, updated.acceptingBookings, updated.status), ('https://x/1.jpg', 'Ten years', false, 'approved'));
  });

  Review review(int rating, {String? comment, int tip = 0, List<String> tags = const []}) =>
      Review(bookingId: rating, rating: rating, comment: comment, tipCents: tip, tags: tags, reviewerName: 'Emma R.', serviceName: 'Deep cleaning');

  test('averageRating', () {
    expect(averageRating([]), isNull);
    expect(averageRating([review(5), review(4)]), 4.5);
  });

  for (final (width, scale) in [(375.0, 1.0), (375.0, 1.3), (430.0, 1.0)]) {
    testWidgets('Profile lays out at ${width.toInt()}pt, text x$scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final status in ['approved', 'pending']) {
        await tester.pumpWidget(MaterialApp(
          theme: SpotlessTheme.light(),
          home: ProfileTab(
            key: ValueKey(status),
            cleaner: Cleaner.fromJson({
              'id': 1,
              'name': 'Liam Test',
              'email': 'liam.test@example.com',
              'phone': '07000 000000',
              'address': '10 Corsica Avenue',
              'postcode': 'SW1A 1AA',
              'status': status,
              'active': 1,
            }),
            onCleanerUpdated: (_) {},
            onLogout: () async {},
            upcomingCount: 2,
            onOpenEarnings: () {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text(status == 'approved' ? 'Approved cleaner' : 'Awaiting approval'), findsOneWidget);
        expect(find.text('New'), findsOneWidget); // no stats in tests
        await tester.scrollUntilVisible(find.text('Log out'), 300, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Profile edit sheet keeps phone required and has the bio field', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: ProfileTab(
        cleaner: Cleaner.fromJson({'id': 1, 'name': 'Liam', 'phone': '07000', 'address': 'A', 'postcode': 'B', 'status': 'approved'}),
        onCleanerUpdated: (_) {},
        onLogout: () async {},
        onOpenEarnings: () {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('About you (optional)'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
  });

  for (final width in [375.0, 430.0]) {
    testWidgets('Reviews list and empty state at ${width.toInt()}pt', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: SpotlessTheme.light(),
        home: ReviewsScreen(
          key: UniqueKey(),
          loadReviews: () async => [
            review(5, comment: 'Spotless, thank you!', tip: 500, tags: ['On time', 'Went the extra mile']),
            review(4),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('4.5 average · 2 reviews'), findsOneWidget);
      expect(find.text('£5 tip'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
        theme: SpotlessTheme.light(),
        home: ReviewsScreen(key: UniqueKey(), loadReviews: () async => const []),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No reviews yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('earningsFor', () {
    final now = DateTime(2026, 9, 30, 10); // Wednesday
    final list = [
      job(1, '2026-09-29', 'completed', price: 4400, minutes: 120), // Tue
      job(2, '2026-09-30', 'confirmed', price: 2400, minutes: 240), // Wed
      job(3, '2026-09-30', 'pending', price: 9900), // a request — not booked, not in activity
      job(4, '2026-10-01', 'cancelled', price: 3000), // in activity, not booked
      job(5, '2026-09-02', 'completed', price: 1700, minutes: 60), // earlier this month
      job(6, '2026-10-05', 'confirmed', price: 5000), // next week
    ];
    final reviews = [
      Review(bookingId: 1, rating: 5, tipCents: 500, reviewerName: 'Emma R.'),
      Review(bookingId: 5, rating: 4, tipCents: 200, reviewerName: 'Sam T.'),
    ];

    test('week', () {
      final w = earningsFor(list, reviews, EarningsPeriod.week, now);
      expect(w.label, 'This week · 28 Sep – 4 Oct');
      expect((w.bookedCents, w.jobs, w.completedJobs, w.minutes, w.tipsCents, w.avgCents), (6800, 2, 1, 360, 500, 3400));
      expect(w.bars.map((b) => b.label), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
      expect(w.bars.map((b) => b.cents), [0, 4400, 2400, 0, 0, 0, 0]);
      expect(w.activity.map((b) => b.id), [4, 2, 1]); // newest first, no requests
    });

    test('month', () {
      final m = earningsFor(list, reviews, EarningsPeriod.month, now);
      expect(m.label, 'This month · September 2026');
      expect((m.bookedCents, m.jobs, m.tipsCents), (8500, 3, 700));
      expect(m.bars.map((b) => b.label), ['1–7', '8–14', '15–21', '22–28', '29–30']);
      expect(m.bars.map((b) => b.cents), [1700, 0, 0, 0, 6800]);
    });

    test('nothing booked', () {
      final e = earningsFor(const [], const [], EarningsPeriod.week, now);
      expect((e.bookedCents, e.avgCents), (0, 0));
      expect(e.activity, isEmpty);
    });
  });

  for (final (width, scale) in [(375.0, 1.0), (375.0, 1.3), (430.0, 1.0)]) {
    testWidgets('Earnings lays out at ${width.toInt()}pt, text x$scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final today = isoDate(DateTime.now());
      Future<void> pump(List<CleanerBooking> bookings) async {
        await tester.pumpWidget(MaterialApp(
          theme: SpotlessTheme.light(),
          home: EarningsTab(
            key: UniqueKey(),
            bookings: bookings,
            loading: false,
            onRefresh: () async {},
            loadReviews: () async => [Review(bookingId: 1, rating: 5, tipCents: 500, reviewerName: 'Emma R.')],
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pump([job(1, today, 'completed', price: 12450), job(2, today, 'confirmed', price: 2400)]);
      expect(find.text('£148.50'), findsNWidgets(2)); // hero total + today's bar (both jobs are today)
      expect(find.text('2 jobs booked'), findsOneWidget);
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This month'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Activity'), 200, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);

      await pump(const []);
      await tester.scrollUntilVisible(find.textContaining('Nothing in this week'), 200, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }

  group('Accessibility at 375pt, text x1.3', () {
    final cleaner = Cleaner.fromJson({
      'id': 1, 'name': 'Liam Test', 'email': 'liam.test@example.com', 'phone': '07000 000000',
      'address': '10 Corsica Avenue', 'postcode': 'SW1A 1AA', 'status': 'approved', 'active': 1, 'bio': 'Ten years cleaning.',
    });
    final today = DateTime.now();
    String inDays(int d) => isoDate(today.add(Duration(days: d)));
    final bookings = [job(1, inDays(1), 'pending'), job(2, inDays(0), 'confirmed'), job(3, inDays(-2), 'completed')];
    final screens = <String, Widget Function()>{
      'Schedule': () => ScheduleTab(
            cleaner: cleaner, bookings: bookings, loading: false, onRefresh: () async {},
            onCleanerUpdated: (_) {}, onOpenEarnings: () {}, unread: const {2: 1}, sendDecision: (_, _) async {}),
      'Job details': () => JobScreen(booking: jobWith({})),
      'Chat': () => ChatScreen(booking: jobWith({})),
      'Add a service': () => AddServiceScreen(availableServices: [menu(1, 'Standard home cleaning')], currentRates: const []),
      'Edit service': () => EditServiceDetailsScreen(service: menu(9, 'Oven deep clean', mine: 1)),
      'Working hours': () => HoursScreen(
            loadHours: () async => [WorkingHours(weekday: 0, startTime: '08:00', endTime: '16:00')],
            loadTimeOff: () async => [TimeOff(id: 1, date: DateUtils.dateOnly(today.add(const Duration(days: 3))))]),
      'Profile': () => ProfileTab(cleaner: cleaner, onCleanerUpdated: (_) {}, onLogout: () async {}, upcomingCount: 1, onOpenEarnings: () {}),
      'Reviews': () => ReviewsScreen(loadReviews: () async => [review(5, comment: 'Great', tip: 200, tags: ['On time'])]),
      'Earnings': () => EarningsTab(bookings: bookings, loading: false, onRefresh: () async {}, loadReviews: () async => const []),
    };

    for (final entry in screens.entries) {
      testWidgets('${entry.key}: no overflow, 44pt targets, readable contrast', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(375 * 3, 812 * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(MaterialApp(theme: SpotlessTheme.light(), home: entry.value()));
        await tester.pump(const Duration(seconds: 1));
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 8; i++) {
          await tester.drag(scrollable, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 600));
        }
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await tester.pumpWidget(const SizedBox()); // stop any timers
      });
    }
  });

  test('parseNominatim reads the first result, or null', () {
    expect(parseNominatim('[{"lat":"51.5014","lon":"-0.1419"},{"lat":"1","lon":"1"}]'), const LatLng(51.5014, -0.1419));
    expect(parseNominatim('[]'), isNull);
    expect(parseNominatim('{"error":"x"}'), isNull);
    expect(parseNominatim('not json'), isNull);
  });

  test('geocodeAddress identifies the app, caches hits, never caches failures', () async {
    final seen = <http.Request>[];
    var fail = true;
    final client = MockClient((req) async {
      seen.add(req);
      if (fail) return http.Response('busy', 503);
      return http.Response('[{"lat":"51.5","lon":"-0.14"}]', 200);
    });
    const address = '10 Corsica Avenue, SW1A 1AA (geocode test)';

    expect(await geocodeAddress(address, client: client), isNull); // 503 — not cached
    fail = false;
    expect(await geocodeAddress(address, client: client), const LatLng(51.5, -0.14));
    expect(await geocodeAddress(address, client: client), const LatLng(51.5, -0.14)); // from cache
    expect(seen, hasLength(2));
    expect(seen.last.headers['User-Agent'], kOsmUserAgent);
    expect(seen.last.url.host, 'nominatim.openstreetmap.org');
    expect(seen.last.url.queryParameters['q'], address);
    expect(await geocodeAddress('  ', client: client), isNull);
  });

  testWidgets('CountBadge is a circle for one digit and a pill for more', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: const Scaffold(
        body: Stack(children: [
          // Given the full screen width, like the nav bar's Positioned + Align.
          Positioned(left: 0, right: 0, top: 0, child: Align(child: CountBadge(3, key: Key('one')))),
          Positioned(left: 0, right: 0, top: 40, child: Align(child: CountBadge(12, key: Key('two')))),
        ]),
      ),
    ));
    final one = tester.getSize(find.byKey(const Key('one')));
    final two = tester.getSize(find.byKey(const Key('two')));
    expect(one, const Size(18, 18));
    expect(two.height, 18);
    expect(two.width, greaterThan(18));
    expect(two.width, lessThan(40));
  });

  testWidgets('ToggleChip hugs its label instead of filling the row', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: SpotlessTheme.light(),
      home: Scaffold(
        body: Wrap(children: [ToggleChip(key: const Key('chip'), label: 'On time', selected: false, onTap: () {})]),
      ),
    ));
    expect(tester.getSize(find.byKey(const Key('chip'))).width, lessThan(200));
  });
}
