import 'package:flutter/material.dart';

import '../main.dart';

import '../api_client.dart';
import '../format.dart';

/// Booking requests (awaiting this cleaner's confirmation), the upcoming
/// confirmed schedule, and completed jobs — the JSON/mobile equivalent of the
/// website's /cleaner dashboard sections. [bookings] and [loading] are owned
/// by HomeScreen (so the bottom-nav badge and this list always agree); confirm/
/// decline call the API directly here, then ask the parent to refetch via
/// [onRefresh] so both this list and the badge update together.
class ScheduleTab extends StatefulWidget {
  final List<CleanerBooking> bookings;
  final bool loading;
  final Future<void> Function() onRefresh;

  const ScheduleTab({super.key, required this.bookings, required this.loading, required this.onRefresh});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  final _api = ApiClient();
  final Set<int> _actioningIds = {};

  Future<void> _confirm(CleanerBooking booking) => _act(booking, isConfirm: true);
  Future<void> _decline(CleanerBooking booking) => _act(booking, isConfirm: false);

  Future<void> _act(CleanerBooking booking, {required bool isConfirm}) async {
    if (!isConfirm) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline this booking?'),
          content: const Text('The slot opens back up right away for other cleaners.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Decline')),
          ],
        ),
      );
      if (sure != true) return;
    }
    setState(() => _actioningIds.add(booking.id));
    try {
      if (isConfirm) {
        await _api.confirmBooking(booking.id);
      } else {
        await _api.declineBooking(booking.id);
      }
      await widget.onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isConfirm ? 'Booking confirmed' : 'Booking declined'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _actioningIds.remove(booking.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: Builder(builder: (context) {
          if (widget.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final pending = widget.bookings.where((b) => b.status == 'pending').toList();
          final upcoming = widget.bookings.where((b) => b.status == 'confirmed').toList();
          final completed = widget.bookings.where((b) => b.status == 'completed').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (pending.isNotEmpty) ...[
                Row(
                  children: [
                    Text('Booking requests', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: kPendingBg, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        '${pending.length} awaiting you',
                        style: TextStyle(fontSize: 11, color: kPendingInk, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...pending.map((b) => _PendingBookingCard(
                      booking: b,
                      busy: _actioningIds.contains(b.id),
                      onConfirm: () => _confirm(b),
                      onDecline: () => _decline(b),
                    )),
                const SizedBox(height: 24),
              ],
              Text('Upcoming', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (upcoming.isEmpty)
                const _EmptyNote(text: 'No upcoming jobs assigned yet.')
              else
                ...upcoming.map((b) => _BookingCard(booking: b)),
              const SizedBox(height: 24),
              Text('Completed', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (completed.isEmpty)
                const _EmptyNote(text: 'No completed jobs yet.')
              else
                ...completed.map((b) => _BookingCard(booking: b)),
            ],
          );
        }),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: TextStyle(color: kBrandMuted)),
    );
  }
}

class _PendingBookingCard extends StatelessWidget {
  final CleanerBooking booking;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  const _PendingBookingCard({required this.booking, required this.busy, required this.onConfirm, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: kPendingInk, width: 5))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(booking.serviceName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                '${friendlyDateString(booking.date)} · ${booking.startTime}–${booking.endTime}',
                style: TextStyle(color: kBrandMuted, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text('${booking.address}, ${booking.postcode}', style: TextStyle(color: kBrandMuted, fontSize: 13)),
              const SizedBox(height: 6),
              Text(formatMoney(booking.priceCents), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : onConfirm,
                      child: busy
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onDecline,
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final CleanerBooking booking;
  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(booking.serviceName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              '${friendlyDateString(booking.date)} · ${booking.startTime}–${booking.endTime}',
              style: TextStyle(color: kBrandMuted, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text('${booking.address}, ${booking.postcode}', style: TextStyle(color: kBrandMuted, fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(booking.ref, style: TextStyle(color: kBrandMuted2, fontSize: 12)),
                Text(formatMoney(booking.priceCents), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (booking.status == 'completed') ...[
              const SizedBox(height: 6),
              Text(
                booking.customerComment != null && booking.customerComment!.trim().isNotEmpty
                    ? '"${booking.customerComment}"'
                    : 'No comment left',
                style: TextStyle(
                  fontSize: 12.5,
                  color: kBrandMuted,
                  fontStyle: booking.customerComment != null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
