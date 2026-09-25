import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../format.dart';
import '../theme/spotless_theme.dart';
import '../ui/layout.dart';
import '../ui/pickers.dart';
import '../ui/tiles.dart';
import 'schedule_tab.dart';

enum EarningsPeriod { week, month }

typedef EarningsBar = ({String label, int cents});

/// Everything the Earnings tab shows for one period.
typedef EarningsSummary = ({
  String label, // "This week · 28 Sep – 4 Oct"
  int bookedCents, // confirmed + completed jobs dated in the period
  int jobs,
  int completedJobs,
  int minutes,
  int tipsCents,
  int avgCents,
  List<EarningsBar> bars,
  List<CleanerBooking> activity, // everything but requests, newest first
});

const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Earnings for the week (Mon–Sun) or calendar month containing [now].
/// "Booked" = confirmed + completed, like the Schedule's THIS WEEK card;
/// tips come from reviews on jobs in the period.
EarningsSummary earningsFor(List<CleanerBooking> bookings, List<Review> reviews, EarningsPeriod period, DateTime now) {
  final DateTime first, last;
  final String label;
  if (period == EarningsPeriod.week) {
    first = weekStart(now);
    last = DateTime(first.year, first.month, first.day + 6);
    String d(DateTime x) => '${x.day} ${_monthShort[x.month - 1]}';
    label = 'This week · ${d(first)} – ${d(last)}';
  } else {
    first = DateTime(now.year, now.month, 1);
    last = DateTime(now.year, now.month + 1, 0);
    label = 'This month · ${monthYear(now)}';
  }
  final from = isoDate(first), to = isoDate(last);
  bool inPeriod(CleanerBooking b) => b.date.compareTo(from) >= 0 && b.date.compareTo(to) <= 0;
  final booked = bookings.where((b) => inPeriod(b) && (b.status == 'confirmed' || b.status == 'completed')).toList();

  final centsByDate = <String, int>{};
  for (final b in booked) {
    centsByDate[b.date] = (centsByDate[b.date] ?? 0) + b.priceCents;
  }
  int sumDays(DateTime a, DateTime b) {
    var total = 0;
    for (var d = a; !d.isAfter(b); d = DateTime(d.year, d.month, d.day + 1)) {
      total += centsByDate[isoDate(d)] ?? 0;
    }
    return total;
  }

  final bars = <EarningsBar>[];
  if (period == EarningsPeriod.week) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    for (var n = 0; n < 7; n++) {
      final day = DateTime(first.year, first.month, first.day + n);
      bars.add((label: letters[n], cents: sumDays(day, day)));
    }
  } else {
    for (var start = 1; start <= last.day; start += 7) {
      final end = (start + 6).clamp(1, last.day);
      bars.add((
        label: '$start–$end',
        cents: sumDays(DateTime(first.year, first.month, start), DateTime(first.year, first.month, end)),
      ));
    }
  }

  final bookedIds = {for (final b in booked) b.id};
  final cents = booked.fold(0, (sum, b) => sum + b.priceCents);
  return (
    label: label,
    bookedCents: cents,
    jobs: booked.length,
    completedJobs: booked.where((b) => b.status == 'completed').length,
    minutes: booked.fold(0, (sum, b) => sum + bookingMinutes(b)),
    tipsCents: reviews.where((r) => bookedIds.contains(r.bookingId)).fold(0, (sum, r) => sum + r.tipCents),
    avgCents: booked.isEmpty ? 0 : (cents / booked.length).round(),
    bars: bars,
    activity: bookings.where((b) => inPeriod(b) && b.status != 'pending').toList()
      ..sort((a, b) => '${b.date} ${b.startTime}'.compareTo('${a.date} ${a.startTime}')),
  );
}

/// What the cleaner has earned and has booked, by week or month. Bookings come
/// from HomeScreen (same list as the Schedule); tips from their reviews.
class EarningsTab extends StatefulWidget {
  final List<CleanerBooking> bookings;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<CleanerBooking>? onOpenJob;

  /// Load override for tests; defaults to the API.
  final Future<List<Review>> Function()? loadReviews;

  const EarningsTab({
    super.key,
    required this.bookings,
    required this.loading,
    required this.onRefresh,
    this.onOpenJob,
    this.loadReviews,
  });

  @override
  State<EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<EarningsTab> {
  EarningsPeriod _period = EarningsPeriod.week;
  List<Review> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await (widget.loadReviews ?? ApiClient().getMyReviews)();
      if (mounted) setState(() => _reviews = reviews);
    } catch (_) {
      // Tips are a nice-to-have; the rest comes from bookings.
    }
  }

  Future<void> _refresh() => Future.wait([widget.onRefresh(), _loadReviews()]);

  @override
  Widget build(BuildContext context) {
    final summary = earningsFor(widget.bookings, _reviews, _period, DateTime.now());
    var i = 0;
    Widget section(Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FadeSlideIn(index: i++, child: child),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Column(children: [
          ScreenHeader(
            title: 'Earnings',
            trailing: [
              SizedBox(
                width: 170,
                child: SegmentedPills(
                  labels: const ['Week', 'Month'],
                  selected: _period.index,
                  onSelected: (n) => setState(() => _period = EarningsPeriod.values[n]),
                ),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: widget.loading
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        section(_Hero(summary: summary)),
                        // TODO(redesign): "Add payout details" prompt → payout screen (kRedesignPayouts).
                        section(_StatGrid(summary: summary)),
                        section(const SectionHeader('Activity')),
                        if (summary.activity.isEmpty)
                          section(EmptyState(
                            icon: LucideIcons.receipt,
                            title: 'Nothing in this ${_period == EarningsPeriod.week ? 'week' : 'month'} yet',
                            message: 'Accepted and finished jobs will show up here.',
                          ))
                        else
                          section(SpotlessCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Column(children: [
                              for (var n = 0; n < summary.activity.length; n++) ...[
                                if (n > 0) const Divider(),
                                _ActivityRow(
                                  booking: summary.activity[n],
                                  onTap: widget.onOpenJob == null ? null : () => widget.onOpenJob!(summary.activity[n]),
                                ),
                              ],
                            ]),
                          )),
                      ],
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.summary});
  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final bars = summary.bars;
    final maxCents = bars.fold(0, (m, b) => b.cents > m ? b.cents : m);
    const chartHeight = 150.0, labelSpace = 36.0;
    return SpotlessHeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(summary.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: s.heroMuted)),
        const SizedBox(height: 6),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 6, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              formatMoney(summary.bookedCents),
              key: ValueKey(summary.bookedCents),
              style: s.heading(40, color: s.heroInk).copyWith(height: 1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SpotlessPill('${summary.jobs} ${summary.jobs == 1 ? 'job' : 'jobs'} booked', colors: (s.heroChip, s.heroInk)),
          ),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: chartHeight,
          child: Semantics(
            label: [for (final b in bars) '${b.label}: ${formatMoney(b.cents)}'].join(', '),
            excludeSemantics: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var n = 0; n < bars.length; n++) ...[
                if (n > 0) const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(bars[n].cents == 0 ? ' ' : formatMoney(bars[n].cents),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.heroInk)),
                    ),
                    const SizedBox(height: 6),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: maxCents == 0 ? 0 : bars[n].cents / maxCents),
                      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Container(
                        height: 6 + (chartHeight - labelSpace - 6 - 18) * v,
                        decoration: BoxDecoration(
                          color: bars[n].cents == 0 ? Colors.white.withValues(alpha: .14) : s.heroAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(bars[n].label, style: TextStyle(fontSize: 11.5, color: s.heroMuted)),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.summary});
  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    Widget tile(IconData icon, String value, String label, {Color? bg, Color? fg}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: s.line),
            borderRadius: BorderRadius.circular(s.radius),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(icon, size: 36, circle: true, background: bg, foreground: fg),
            const SizedBox(height: 10),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: s.heading(22))),
            Text(label, style: TextStyle(fontSize: 12.5, color: s.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    return Column(children: [
      Row(children: [
        Expanded(child: tile(LucideIcons.circleCheck, '${summary.completedJobs}', 'Jobs completed', bg: s.greenSoft, fg: s.green)),
        const SizedBox(width: 10),
        Expanded(child: tile(LucideIcons.coins, formatMoney(summary.avgCents), 'Avg. per job')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: tile(LucideIcons.clock, hoursLabel(summary.minutes), 'Hours booked')),
        const SizedBox(width: 10),
        Expanded(
          child: tile(LucideIcons.heartHandshake, formatMoney(summary.tipsCents), 'Tips',
              bg: s.accentSoft, fg: context.colors.secondary),
        ),
      ]),
    ]);
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.booking, required this.onTap});
  final CleanerBooking booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final b = booking;
    final d = DateTime.tryParse(b.date);
    final cancelled = b.status == 'cancelled';
    final (label, colors) = switch (b.status) {
      'completed' => ('Completed', s.approved),
      'cancelled' => ('Cancelled', s.cancelled),
      _ => ('Booked', s.confirmed),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          IconTile(serviceIcon(b.serviceSlug), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.serviceName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${d == null ? b.date : shortDate(d).replaceFirst(',', '')} · ${b.ref}',
                  style: TextStyle(fontSize: 12.5, color: s.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatMoney(b.priceCents),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cancelled ? s.muted : null,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                )),
            const SizedBox(height: 4),
            SpotlessPill(label, colors: colors),
          ]),
        ]),
      ),
    );
  }
}
