import 'dart:async';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../ui/layout.dart';
import 'job_screen.dart';
import 'login_screen.dart';
import 'profile_tab.dart';
import 'schedule_tab.dart';
import 'services_tab.dart';

/// The app shell once logged in: a bottom-nav'd Schedule / Earnings / Services /
/// Profile, plus a pending-approval banner (shown on every tab) if the admin hasn't
/// approved this cleaner yet.
///
/// Bookings are fetched once here (not per-tab) so the Schedule tab's bottom-nav
/// icon can carry a live "awaiting confirmation" badge count even while another
/// tab is showing — same polling + app-resume pattern as the customer app's
/// HomeScreen, plus a snackbar when a brand-new request comes in.
class HomeScreen extends StatefulWidget {
  final Cleaner cleaner;
  const HomeScreen({super.key, required this.cleaner});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 15);

  final _api = ApiClient();
  late Cleaner _cleaner;
  int _tabIndex = 0;
  bool _loadingBookings = true;
  List<CleanerBooking>? _bookings;
  Timer? _pollTimer;
  List<ChatMessage> _messages = const [];
  StreamSubscription<List<ChatMessage>>? _messagesSub;

  @override
  void initState() {
    super.initState();
    _cleaner = widget.cleaner;
    WidgetsBinding.instance.addObserver(this);
    _loadBookings();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _loadBookings());
    // Customer messages arrive live (Realtime) and feed the unread counts on
    // job cards; an error just leaves them at zero.
    _messagesSub = _api.watchMyMessages().listen(
      (messages) => setState(() => _messages = messages),
      onError: (Object e) => debugPrint('Messages unavailable: $e'),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messagesSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadBookings();
  }

  Future<void> _loadBookings() async {
    final hadBookingsAlready = _bookings != null;
    if (!hadBookingsAlready) setState(() => _loadingBookings = true);
    try {
      final fresh = await _api.getMyBookings();
      if (!mounted) return;
      _notifyNewRequests(previous: _bookings, current: fresh);
      setState(() {
        _bookings = fresh;
        _loadingBookings = false;
      });
    } catch (_) {
      // A failed background poll shouldn't disturb whatever's already on screen.
      if (!mounted) return;
      setState(() => _loadingBookings = false);
    }
  }

  /// Lets a cleaner know (via a snackbar) when a brand-new booking request has
  /// come in while they had the app open — otherwise a quiet background poll
  /// updating the badge count is easy to miss.
  void _notifyNewRequests({required List<CleanerBooking>? previous, required List<CleanerBooking> current}) {
    if (previous == null) return; // first load — nothing to compare against yet
    final previousIds = previous.map((b) => b.id).toSet();
    final newlyPendingCount = current.where((b) => b.status == 'pending' && !previousIds.contains(b.id)).length;
    if (newlyPendingCount == 0) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(newlyPendingCount == 1 ? 'New booking request!' : '$newlyPendingCount new booking requests!'),
    ));
  }

  void _onCleanerUpdated(Cleaner updated) => setState(() => _cleaner = updated);

  Future<void> _openJob(CleanerBooking booking) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => JobScreen(booking: booking, allBookings: _bookings ?? const [])),
    );
    if (changed == true) _loadBookings();
  }

  void _selectTab(int i) {
    if (i == _tabIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _tabIndex = i);
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final bookings = _bookings ?? [];
    final pendingCount = bookings.where((b) => b.status == 'pending').length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_cleaner.isPendingApproval)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: s.goldSoft,
                child: Row(
                  children: [
                    Icon(LucideIcons.hourglass, size: 16, color: s.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Your application is awaiting admin approval — you can't be assigned jobs yet.",
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: s.gold),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  ScheduleTab(
                    cleaner: _cleaner,
                    bookings: bookings,
                    loading: _loadingBookings && _bookings == null,
                    onRefresh: _loadBookings,
                    onCleanerUpdated: _onCleanerUpdated,
                    onOpenEarnings: () => _selectTab(1),
                    unread: unreadByBooking(_messages),
                    onOpenJob: _openJob,
                  ),
                  // TODO(redesign): step 9 — Earnings (07-earnings).
                  const Center(
                    child: EmptyState(
                      icon: LucideIcons.chartColumn,
                      title: 'Earnings',
                      message: "Your earnings summary is on its way.",
                    ),
                  ),
                  ServicesTab(cleanerId: _cleaner.id),
                  ProfileTab(cleaner: _cleaner, onCleanerUpdated: _onCleanerUpdated, onLogout: _logout),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CleanerNavBar(index: _tabIndex, onSelected: _selectTab, scheduleBadge: pendingCount),
    );
  }
}

/// Bottom nav: Schedule (badge = requests awaiting you), Earnings, Services, Profile.
class CleanerNavBar extends StatelessWidget {
  const CleanerNavBar({super.key, required this.index, required this.onSelected, this.scheduleBadge = 0});
  final int index;
  final ValueChanged<int> onSelected;
  final int scheduleBadge;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final bottom = max(MediaQuery.paddingOf(context).bottom, 10.0);
    Widget tab(int i, IconData icon, String label, [int badge = 0]) => Expanded(
          child: _NavItem(icon: icon, label: label, selected: index == i, badge: badge, onTap: () => onSelected(i)),
        );
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: s.line))),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 10, 10, bottom),
        child: Row(children: [
          tab(0, LucideIcons.calendarDays, 'Schedule', scheduleBadge),
          tab(1, LucideIcons.chartColumn, 'Earnings'),
          tab(2, LucideIcons.sparkles, 'Services'),
          tab(3, LucideIcons.user, 'Profile'),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.badge, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final color = selected ? context.colors.primary : s.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '$label, $badge' : label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 52,
              height: 30,
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: selected ? s.primarySoft : Colors.transparent,
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
          ]),
          if (badge > 0)
            Positioned(
              top: -2,
              left: 0,
              right: 0,
              child: Align(
                alignment: const Alignment(.55, 0),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: context.colors.secondary,
                    shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 2)),
                  ),
                  child: Text(badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
