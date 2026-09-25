import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../main.dart';
import 'login_screen.dart';
import 'profile_tab.dart';
import 'schedule_tab.dart';
import 'services_tab.dart';

/// The app shell once logged in: a bottom-nav'd Schedule / Services / Profile,
/// plus a pending-approval banner (shown on every tab) if the admin hasn't
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

  @override
  void initState() {
    super.initState();
    _cleaner = widget.cleaner;
    WidgetsBinding.instance.addObserver(this);
    _loadBookings();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _loadBookings());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: kBrandSecondary.withOpacity(0.12),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top, size: 16, color: kBrandSecondary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Your application is awaiting admin approval — you can't be assigned jobs yet.",
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
                    bookings: bookings,
                    loading: _loadingBookings && _bookings == null,
                    onRefresh: _loadBookings,
                  ),
                  ServicesTab(cleanerId: _cleaner.id),
                  ProfileTab(cleaner: _cleaner, onCleanerUpdated: _onCleanerUpdated, onLogout: _logout),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        items: [
          BottomNavigationBarItem(
            icon: _BadgeIcon(icon: Icons.calendar_today_outlined, count: pendingCount),
            activeIcon: _BadgeIcon(icon: Icons.calendar_today, count: pendingCount),
            label: 'Schedule',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.cleaning_services_outlined),
            activeIcon: Icon(Icons.cleaning_services),
            label: 'Services',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// A bottom-nav icon with a small red count badge — the "unread" indicator for
/// bookings still awaiting this cleaner's confirmation.
class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -7,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: const BoxDecoration(color: kDangerInk, shape: BoxShape.circle),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}