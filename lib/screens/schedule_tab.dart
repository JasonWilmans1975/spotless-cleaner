import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../flags.dart';
import '../format.dart';
import '../links.dart';
import '../theme/spotless_theme.dart';
import '../ui/debug_gallery.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';

/// How long an Accept / Decline can be undone before it's sent.
const kUndoWindow = Duration(seconds: 5);

/// Monday 00:00 of the week containing [now].
DateTime weekStart(DateTime now) => DateTime(now.year, now.month, now.day - (now.weekday - 1));

/// Minutes a booking runs: its duration, else end − start.
int bookingMinutes(CleanerBooking b) =>
    b.durationMinutes > 0 ? b.durationMinutes : (toMinutes(b.endTime) - toMinutes(b.startTime)).clamp(0, 24 * 60);

typedef WeekSummary = ({int bookedCents, int jobs, int minutes});

/// "This week": confirmed + completed jobs dated Monday–Sunday of [now]'s week.
WeekSummary weekSummary(List<CleanerBooking> bookings, DateTime now) {
  final start = weekStart(now);
  final first = isoDate(start), last = isoDate(start.add(const Duration(days: 6)));
  var cents = 0, jobs = 0, minutes = 0;
  for (final b in bookings) {
    if (b.status != 'confirmed' && b.status != 'completed') continue;
    if (b.date.compareTo(first) < 0 || b.date.compareTo(last) > 0) continue;
    cents += b.priceCents;
    jobs++;
    minutes += bookingMinutes(b);
  }
  return (bookedCents: cents, jobs: jobs, minutes: minutes);
}

/// "6h" / "6.5h" for the week hero.
String hoursLabel(int minutes) {
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

/// How many earlier, non-cancelled bookings the same customer has with this
/// cleaner (matched by email, else name) — "first booking with you" when 0.
int previousBookingsWith(CleanerBooking request, List<CleanerBooking> all) {
  bool same(CleanerBooking b) => request.email.isNotEmpty
      ? b.email.toLowerCase() == request.email.toLowerCase()
      : b.customerName.trim().toLowerCase() == request.customerName.trim().toLowerCase();
  return all.where((b) => b.id != request.id && b.status != 'cancelled' && same(b)).length;
}

/// The cleaner's home: availability, this week at a glance, requests to act on
/// (with a short Undo before anything is sent), upcoming and completed jobs.
/// [bookings] and [loading] are owned by HomeScreen so the nav badge and this
/// list always agree; after acting it asks the parent to refetch via [onRefresh].
class ScheduleTab extends StatefulWidget {
  final Cleaner cleaner;
  final List<CleanerBooking> bookings;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<Cleaner> onCleanerUpdated;
  final VoidCallback onOpenEarnings;

  /// Unread customer messages per booking id (from HomeScreen's live stream).
  final Map<int, int> unread;

  /// Opens a job (Job details — step 4).
  final ValueChanged<CleanerBooking>? onOpenJob;

  /// Sends an accepted (true) / declined (false) request. Defaults to the API;
  /// tests pass a fake.
  final Future<void> Function(int bookingId, bool accept)? sendDecision;

  const ScheduleTab({
    super.key,
    required this.cleaner,
    required this.bookings,
    required this.loading,
    required this.onRefresh,
    required this.onCleanerUpdated,
    required this.onOpenEarnings,
    this.unread = const {},
    this.onOpenJob,
    this.sendDecision,
  });

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

typedef _Decision = ({bool accept, Timer timer});

class _ScheduleTabState extends State<ScheduleTab> with WidgetsBindingObserver {
  final _api = ApiClient();

  /// Requests the cleaner has just accepted/declined, not yet sent (Undo window).
  final _decisions = <int, _Decision>{};
  DateTime? _day; // week-strip filter; null = everything
  bool _savingAvailability = false;
  Map<int, Review> _reviews = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReviews();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushDecisions(); // leaving the screen sends anything still waiting
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding the app shouldn't leave a decision unsent.
    if (state == AppLifecycleState.paused) _flushDecisions();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await _api.getMyReviews();
      if (mounted) setState(() => _reviews = {for (final r in reviews) r.bookingId: r});
    } catch (_) {
      // Ratings on completed jobs are a nice-to-have.
    }
  }

  Future<void> _refresh() => Future.wait([widget.onRefresh(), _loadReviews()]);

  Future<void> _send(int bookingId, bool accept) =>
      (widget.sendDecision ?? (id, yes) => yes ? _api.confirmBooking(id) : _api.declineBooking(id))(bookingId, accept);

  void _decide(CleanerBooking b, bool accept) {
    HapticFeedback.mediumImpact();
    setState(() {
      _decisions[b.id] = (accept: accept, timer: Timer(kUndoWindow, () => _commit(b.id)));
    });
  }

  void _undo(int bookingId) {
    HapticFeedback.selectionClick();
    setState(() => _decisions.remove(bookingId)?.timer.cancel());
  }

  Future<void> _commit(int bookingId) async {
    final decision = _decisions[bookingId];
    if (decision == null) return;
    decision.timer.cancel();
    try {
      await _send(bookingId, decision.accept);
      await widget.onRefresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _decisions.remove(bookingId));
      } else {
        _decisions.remove(bookingId);
      }
    }
  }

  void _flushDecisions() {
    for (final id in _decisions.keys.toList()) {
      final d = _decisions.remove(id)!;
      d.timer.cancel();
      _send(id, d.accept).ignore();
    }
  }

  Future<void> _toggleAvailability(bool accepting) async {
    HapticFeedback.selectionClick();
    setState(() => _savingAvailability = true);
    try {
      widget.onCleanerUpdated(await _api.setAcceptingBookings(accepting));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingAvailability = false);
    }
  }

  Future<void> _directions(CleanerBooking b) async {
    final address = [b.address, b.postcode].where((x) => x.trim().isNotEmpty).join(', ');
    if (address.isEmpty || !await openDirections(address)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open maps")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final now = DateTime.now();
    final all = widget.bookings;
    bool onDay(CleanerBooking b) => _day == null || b.date == isoDate(_day!);
    int bySoonest(CleanerBooking a, CleanerBooking b) => '${a.date} ${a.startTime}'.compareTo('${b.date} ${b.startTime}');
    final pending = all.where((b) => b.status == 'pending' && onDay(b)).toList()..sort(bySoonest);
    final upcoming = all.where((b) => b.status == 'confirmed' && onDay(b)).toList()..sort(bySoonest);
    final completed = all.where((b) => b.status == 'completed' && onDay(b)).toList()
      ..sort((a, b) => bySoonest(b, a));
    final awaiting = pending.where((b) => !_decisions.containsKey(b.id)).length;

    var i = 0;
    Widget section(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FadeSlideIn(index: i++, child: child),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              _Header(cleaner: widget.cleaner, now: now),
              const SizedBox(height: 12),
              section(_AvailabilityCard(
                cleaner: widget.cleaner,
                saving: _savingAvailability,
                onChanged: _toggleAvailability,
              )),
              section(_WeekHero(summary: weekSummary(all, now), onOpenEarnings: widget.onOpenEarnings)),
              section(_WeekStrip(
                start: weekStart(now),
                today: DateUtils.dateOnly(now),
                selected: _day,
                busyDays: {for (final b in all) if (b.status != 'cancelled') b.date},
                onSelected: (d) => setState(() => _day = _day == d ? null : d),
              )),
              if (widget.loading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                if (pending.isNotEmpty) ...[
                  section(SectionHeader(
                    'Booking requests',
                    trailing: awaiting == 0 ? null : SpotlessPill('$awaiting awaiting you', colors: s.awaiting),
                  )),
                  for (final b in pending)
                    section(AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _decisions.containsKey(b.id)
                          ? _DecisionBanner(
                              key: ValueKey('decided-${b.id}'),
                              booking: b,
                              accepted: _decisions[b.id]!.accept,
                              onUndo: () => _undo(b.id),
                            )
                          : _RequestCard(
                              key: ValueKey('request-${b.id}'),
                              booking: b,
                              previousBookings: previousBookingsWith(b, all),
                              onAccept: () => _decide(b, true),
                              onDecline: () => _decide(b, false),
                            ),
                    )),
                ],
                section(const SectionHeader('Upcoming')),
                if (upcoming.isEmpty)
                  section(_DashedNote(
                    icon: LucideIcons.calendarDays,
                    title: _day == null ? 'No upcoming jobs yet.' : 'Nothing booked that day.',
                    message: _day == null ? 'Accepted requests will show up here.' : 'Tap the day again to see everything.',
                  ))
                else
                  for (final b in upcoming)
                    section(_UpcomingCard(
                      booking: b,
                      unread: widget.unread[b.id] ?? 0,
                      onTap: widget.onOpenJob == null ? null : () => widget.onOpenJob!(b),
                      onDirections: () => _directions(b),
                    )),
                section(const SectionHeader('Completed')),
                if (completed.isEmpty)
                  section(const _DashedNote(
                    icon: LucideIcons.circleCheckBig,
                    title: 'No completed jobs yet.',
                    message: 'Finished jobs and reviews will appear here.',
                  ))
                else
                  for (final b in completed)
                    section(_CompletedCard(
                      booking: b,
                      review: _reviews[b.id],
                      onTap: widget.onOpenJob == null ? null : () => widget.onOpenJob!(b),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.cleaner, required this.now});
  final Cleaner cleaner;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final first = cleaner.name.trim().split(' ').first;
    final greeting = now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(children: [
        // Long-press opens the widget gallery in debug builds only.
        GestureDetector(
          onLongPress: kDebugMode
              ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugGallery()))
              : null,
          child: InitialsAvatar(name: cleaner.name, url: cleaner.avatarUrl, size: 46),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: TextStyle(fontSize: 13, color: s.muted)),
            Text(first.isEmpty ? 'Welcome' : first, style: s.heading(22), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        // TODO(redesign): notifications bell needs a notifications feed (kRedesignNotifications).
        if (kRedesignNotifications)
          IconButton(tooltip: 'Notifications', onPressed: () {}, icon: const Icon(LucideIcons.bell, size: 20)),
      ]),
    );
  }
}

/// "Accepting new bookings" switch (cleaners.accepting_bookings).
class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.cleaner, required this.saving, required this.onChanged});
  final Cleaner cleaner;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final pendingApproval = cleaner.isPendingApproval;
    final on = cleaner.acceptingBookings && !pendingApproval;
    final (title, subtitle) = pendingApproval
        ? ('Not bookable yet', "Customers can book you once you're approved")
        : on
            ? ('Accepting new bookings', 'Customers can book you in your working hours')
            : ('Paused', "Customers can't book you until you switch this back on");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: s.line),
        borderRadius: BorderRadius.circular(s.radius),
      ),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: on ? s.green : s.muted,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: on ? s.greenSoft : s.lineSoft, spreadRadius: 4)],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(subtitle, style: TextStyle(fontSize: 12.5, color: s.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Switch(
          value: on,
          activeTrackColor: s.green,
          onChanged: pendingApproval || saving ? null : onChanged,
        ),
      ]),
    );
  }
}

class _WeekHero extends StatelessWidget {
  const _WeekHero({required this.summary, required this.onOpenEarnings});
  final WeekSummary summary;
  final VoidCallback onOpenEarnings;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    Widget stat(String value, String label, double size, {bool divider = true}) => Container(
          padding: EdgeInsets.only(left: divider ? 14 : 0),
          decoration: divider ? BoxDecoration(border: Border(left: BorderSide(color: s.heroLine))) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(value, key: ValueKey(value), style: s.heading(size, color: s.heroInk).copyWith(height: 1.1)),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12.5, color: s.heroMuted)),
          ]),
        );
    return SpotlessHeroCard(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          right: -46,
          top: -44,
          child: Icon(LucideIcons.sparkle, size: 130, color: s.heroAccent.withValues(alpha: .16)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('THIS WEEK',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.15, color: s.heroMuted)),
            ),
            TextButton(
              onPressed: onOpenEarnings,
              style: TextButton.styleFrom(foregroundColor: s.heroAccent, minimumSize: const Size(44, 44)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Earnings'),
                SizedBox(width: 4),
                Icon(LucideIcons.chevronRight, size: 16),
              ]),
            ),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 14, child: stat(formatMoney(summary.bookedCents), 'booked', 32, divider: false)),
            Expanded(flex: 10, child: stat('${summary.jobs}', summary.jobs == 1 ? 'job' : 'jobs', 24)),
            Expanded(flex: 10, child: stat(hoursLabel(summary.minutes), 'scheduled', 24)),
          ]),
        ]),
      ]),
    );
  }
}

/// Mon–Sun of this week; tap a day to filter the lists, tap it again to clear.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.start,
    required this.today,
    required this.selected,
    required this.busyDays,
    required this.onSelected,
  });
  final DateTime start, today;
  final DateTime? selected;
  final Set<String> busyDays;
  final ValueChanged<DateTime> onSelected;

  static const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final ink = context.colors.inverseSurface;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: s.line),
        borderRadius: BorderRadius.circular(s.radius),
      ),
      child: Row(children: [
        for (var n = 0; n < 7; n++)
          Builder(builder: (context) {
            final day = DateTime(start.year, start.month, start.day + n);
            final isSelected = selected == day;
            final busy = busyDays.contains(isoDate(day));
            final isToday = day == today;
            return Expanded(
              child: Semantics(
                button: true,
                selected: isSelected,
                label: '${_dow[n]} ${day.day}${busy ? ', has jobs' : ''}',
                excludeSemantics: true,
                child: Pressable(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelected(day);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: 66,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(s.radiusMd),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_dow[n],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white.withValues(alpha: .7) : (isToday ? context.colors.primary : s.muted),
                              )),
                          const SizedBox(height: 2),
                          Text('${day.day}', style: s.heading(18, color: isSelected ? Colors.white : null)),
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: busy ? (isSelected ? Colors.white : context.colors.secondary) : Colors.transparent,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
      ]),
    );
  }
}

Widget _infoRow(BuildContext context, IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: context.tokens.muted)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: SpotlessColors.inkSoft))),
      ]),
    );

String _when(CleanerBooking b) {
  final d = DateTime.tryParse(b.date);
  return '${d == null ? b.date : shortDate(d)} · ${b.startTime}–${b.endTime}';
}

String _address(CleanerBooking b) => [b.address, b.postcode].where((x) => x.trim().isNotEmpty).join(', ');

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    super.key,
    required this.booking,
    required this.previousBookings,
    required this.onAccept,
    required this.onDecline,
  });
  final CleanerBooking booking;
  final int previousBookings;
  final VoidCallback onAccept, onDecline;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final b = booking;
    final who = [
      if (b.customerName.trim().isNotEmpty) b.customerName.trim(),
      previousBookings == 0
          ? 'first booking with you'
          : 'booked you ${previousBookings == 1 ? 'once' : '$previousBookings times'} before',
    ].join(' · ');
    return SpotlessCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: s.goldSoft,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            Icon(LucideIcons.clock, size: 15, color: s.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text('New request · respond soon',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s.gold)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconTile(serviceIcon(b.serviceSlug), size: 46, background: context.colors.inverseSurface, foreground: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.serviceName, style: s.heading(17)),
                  if (bookingMinutes(b) > 0)
                    Text(durationText(bookingMinutes(b)), style: TextStyle(fontSize: 13, color: s.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(formatMoney(b.priceCents), style: s.heading(24)),
            ]),
            const SizedBox(height: 2),
            _infoRow(context, LucideIcons.calendar, _when(b)),
            if (_address(b).isNotEmpty) _infoRow(context, LucideIcons.mapPin, _address(b)),
            _infoRow(context, LucideIcons.userRound, who),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.check, size: 17),
                    SizedBox(width: 8),
                    Flexible(child: Text('Accept', overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Shown for [kUndoWindow] after Accept / Decline, before the decision is sent.
class _DecisionBanner extends StatelessWidget {
  const _DecisionBanner({super.key, required this.booking, required this.accepted, required this.onUndo});
  final CleanerBooking booking;
  final bool accepted;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final fg = accepted ? s.green : context.colors.onSurface;
    final d = DateTime.tryParse(booking.date);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: accepted ? s.greenSoft : s.lineSoft,
        borderRadius: BorderRadius.circular(s.radiusMd),
      ),
      child: Row(children: [
        Icon(accepted ? LucideIcons.circleCheckBig : LucideIcons.x, size: 18, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${accepted ? 'Accepted' : 'Declined'} — ${booking.serviceName}${d == null ? '' : ', ${shortDate(d)}'}',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
        TextButton(
          onPressed: onUndo,
          style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size(44, 44)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.undo2, size: 16),
            SizedBox(width: 6),
            Text('Undo'),
          ]),
        ),
      ]),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.booking, required this.unread, required this.onTap, required this.onDirections});
  final CleanerBooking booking;
  final int unread;
  final VoidCallback? onTap;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final b = booking;
    final d = DateTime.tryParse(b.date);
    final minutes = bookingMinutes(b);
    return SpotlessCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (d != null) ...[DateBlock(d), const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(b.serviceName, style: s.heading(16.5))),
                const SizedBox(width: 8),
                Text(formatMoney(b.priceCents), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 5),
              Text('${b.startTime}–${b.endTime}${minutes > 0 ? ' · ${durationText(minutes)}' : ''}',
                  style: TextStyle(fontSize: 13.5, color: s.muted)),
              if (_address(b).isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(_address(b),
                    style: TextStyle(fontSize: 13.5, color: s.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 4),
        Row(children: [
          Flexible(
            child: b.inProgress
                ? SpotlessPill('In progress', colors: s.approved, icon: LucideIcons.timer)
                : SpotlessPill('Confirmed', colors: s.confirmed, icon: LucideIcons.check),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(b.ref, style: TextStyle(fontSize: 12.5, color: s.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (unread > 0) ...[
            SpotlessPill('$unread', colors: (s.accentSoft, s.accentDeep), icon: LucideIcons.messageCircle),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: TextButton(
              onPressed: onDirections,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.navigation, size: 15),
                SizedBox(width: 6),
                Flexible(child: Text('Directions', overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.booking, required this.review, required this.onTap});
  final CleanerBooking booking;
  final Review? review;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final b = booking;
    final d = DateTime.tryParse(b.date);
    final comment = (review?.comment?.trim().isNotEmpty ?? false) ? review!.comment!.trim() : b.customerComment?.trim();
    return SpotlessCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (d != null) ...[DateBlock(d), const SizedBox(width: 14)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(b.serviceName, style: s.heading(16.5))),
              const SizedBox(width: 8),
              Text(formatMoney(b.priceCents), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(b.ref, style: TextStyle(fontSize: 12.5, color: s.muted)),
            if (review != null) ...[
              const SizedBox(height: 6),
              Semantics(
                label: '${review!.rating} out of 5 stars',
                excludeSemantics: true,
                child: Row(children: [
                  for (var n = 1; n <= 5; n++)
                    Icon(Icons.star_rounded, size: 16, color: n <= review!.rating ? context.colors.secondary : s.line),
                  if (review!.tipCents > 0) ...[
                    const SizedBox(width: 8),
                    Text('+ ${formatMoney(review!.tipCents)} tip',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: s.green)),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              comment != null && comment.isNotEmpty ? '"$comment"' : 'No comment left',
              style: TextStyle(
                fontSize: 12.5,
                color: s.muted,
                fontStyle: comment != null && comment.isNotEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _DashedNote extends StatelessWidget {
  const _DashedNote({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title, message;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return DashedBorder(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          IconTile(icon, size: 44, circle: true),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$title ', style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.onSurface)),
                TextSpan(text: message),
              ]),
              style: TextStyle(fontSize: 13.5, height: 1.45, color: s.muted),
            ),
          ),
        ]),
      ),
    );
  }
}
