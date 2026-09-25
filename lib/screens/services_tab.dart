import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../format.dart';
import '../service_icons.dart';
import '../theme/spotless_theme.dart';
import '../ui/layout.dart';
import 'add_service_screen.dart';
import 'edit_service_details_screen.dart';

/// Pence from what the cleaner typed in the rate editor; null (blank or not a
/// number) means "use the service's default price".
int? parsePriceCents(String raw) {
  final text = raw.trim().replaceAll('£', '').trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  return value == null ? null : (value * 100).round();
}

/// My services (edit rate / remove), pending self-proposed services, a
/// suggestion for something to add, and rate history — the mobile equivalent
/// of the corresponding sections on the website's /cleaner dashboard.
///
/// Fetches its own data independently of the Schedule tab. Services change far
/// less often than bookings, so this doesn't poll unconditionally — but while a
/// proposed service is still pending, an admin approving/rejecting it elsewhere
/// (the website) is exactly the kind of change this screen needs to notice on
/// its own, so it polls only while [_pendingProposed] is non-empty, plus a
/// refresh whenever the app comes back to the foreground.
class ServicesTab extends StatefulWidget {
  final int cleanerId;

  const ServicesTab({super.key, required this.cleanerId});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 10);

  final _api = ApiClient();
  bool _loading = true;
  String? _error;
  bool _savingRates = false;
  List<MenuService> _allServices = [];
  List<MyServiceRate> _myRates = [];
  List<MenuService> _pendingProposed = [];
  List<PriceHistoryEntry> _history = [];
  List<MenuService>? _lastPendingSnapshot; // null until the first load completes
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAll(silent: true);
  }

  /// Starts polling once something's pending, stops once nothing is —
  /// no point polling forever for a change that isn't coming.
  void _syncPolling() {
    final shouldPoll = _pendingProposed.isNotEmpty;
    if (shouldPoll && _pollTimer == null) {
      _pollTimer = Timer.periodic(_pollInterval, (_) => _loadAll(silent: true));
    } else if (!shouldPoll && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  /// Lets the cleaner know (via a snackbar) when a proposed service they were
  /// waiting on got reviewed while this screen was open in the background —
  /// otherwise a quiet poll silently moving a card out of "Pending" is easy to miss.
  void _notifyResolvedServices({required List<MenuService>? previous, required List<MenuService> current}) {
    if (previous == null) return; // first load — nothing to compare against yet
    final previousIds = previous.map((s) => s.id).toSet();
    final currentIds = current.map((s) => s.id).toSet();
    final resolvedCount = previousIds.difference(currentIds).length;
    if (resolvedCount == 0) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(resolvedCount == 1
          ? 'A proposed service was reviewed — list updated'
          : '$resolvedCount proposed services were reviewed — list updated'),
    ));
  }

  /// [silent] skips the full-page loading state and swallows errors — used for
  /// the background poll and app-resume refresh, so a flaky connection doesn't
  /// wipe out whatever's already on screen.
  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _api.getServices(),
        _api.getMyServiceRates(),
        _api.getPendingProposedServices(),
        _api.getPriceHistory(),
      ]);
      if (!mounted) return;
      final newPending = results[2] as List<MenuService>;
      _notifyResolvedServices(previous: _lastPendingSnapshot, current: newPending);
      _lastPendingSnapshot = newPending;
      setState(() {
        _allServices = results[0] as List<MenuService>;
        _myRates = results[1] as List<MyServiceRate>;
        _pendingProposed = newPending;
        _history = results[3] as List<PriceHistoryEntry>;
        _loading = false;
      });
      _syncPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) setState(() => _error = e.toString());
    }
  }

  Future<void> _saveRates(List<MyServiceRate> updated, {required String successMessage}) async {
    setState(() => _savingRates = true);
    try {
      await _api.updateMyServices(updated);
      await _loadAll(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingRates = false);
    }
  }

  Future<void> _editRate(MenuService service, MyServiceRate current) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RateSheet(service: service, current: current),
    );
    if (text == null) return; // dismissed
    final updated = [
      for (final r in _myRates)
        if (r.serviceId != service.id) r,
      MyServiceRate(serviceId: service.id, priceCents: parsePriceCents(text)),
    ];
    await _saveRates(updated, successMessage: 'Rate saved');
  }

  Future<void> _removeService(MenuService service) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this service?'),
        content: Text("You'll stop being offered for ${service.name}."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.tokens.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    HapticFeedback.mediumImpact();
    final updated = _myRates.where((r) => r.serviceId != service.id).toList();
    await _saveRates(updated, successMessage: 'Removed');
  }

  Future<void> _openAddService() async {
    final myServiceIds = _myRates.map((r) => r.serviceId).toSet();
    final available = _allServices.where((s) => !myServiceIds.contains(s.id)).toList();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddServiceScreen(availableServices: available, currentRates: _myRates)),
    );
    if (changed == true) _loadAll();
  }

  /// Full-details edit (name, icon, description, pricing, duration, features) —
  /// only ever reachable for a service this cleaner proposed themselves; the
  /// shared default menu stays admin-only, same as the server enforces.
  Future<void> _editDetails(MenuService service) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditServiceDetailsScreen(service: service)),
    );
    if (changed == true) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Column(children: [
          ScreenHeader(
            title: 'My services',
            subtitle: 'Tap edit to change your rate',
            trailing: [
              IconButton(
                tooltip: 'Add a service',
                onPressed: _loading ? null : _openAddService,
                style: IconButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  side: BorderSide.none,
                  shadowColor: context.colors.primary,
                  elevation: 0,
                ),
                icon: const Icon(LucideIcons.plus, size: 20),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              child: Builder(builder: (context) {
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_error != null) {
                  return ListView(children: [
                    EmptyState(
                      icon: LucideIcons.wifiOff,
                      title: "Couldn't load your services",
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: _loadAll,
                    ),
                  ]);
                }
                return _buildList();
              }),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildList() {
    final myServiceIds = _myRates.map((r) => r.serviceId).toSet();
    final myOffered = _allServices.where((sv) => myServiceIds.contains(sv.id)).toList();
    final rateByServiceId = {for (final r in _myRates) r.serviceId: r};
    final suggestion = _allServices.where((sv) => !myServiceIds.contains(sv.id)).firstOrNull;

    var i = 0;
    Widget section(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: FadeSlideIn(index: i++, child: child),
        );

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      children: [
        if (myOffered.isEmpty && _pendingProposed.isEmpty)
          EmptyState(
            icon: LucideIcons.sparkles,
            title: "You're not offering any services yet",
            message: 'Add the cleans you do and set your own rates.',
            actionLabel: 'Add a service',
            onAction: _openAddService,
          )
        else ...[
          for (final sv in myOffered)
            section(MyServiceCard(
              service: sv,
              rate: rateByServiceId[sv.id]!,
              busy: _savingRates,
              onEditRate: () => _editRate(sv, rateByServiceId[sv.id]!),
              onRemove: () => _removeService(sv),
              onEditDetails: sv.createdByCleanerId == widget.cleanerId ? () => _editDetails(sv) : null,
            )),
          for (final sv in _pendingProposed) section(_PendingServiceCard(service: sv, onEditDetails: () => _editDetails(sv))),
        ],
        if (suggestion != null) section(_SuggestionCard(service: suggestion, onTap: _openAddService)),
        section(const SectionHeader('Rate history')),
        section(_history.isEmpty
            ? Text('No rate changes yet — every change to your rates, and who made it, shows up here.',
                style: TextStyle(fontSize: 13.5, color: context.tokens.muted))
            : SpotlessCard(
                child: Column(children: [
                  for (var n = 0; n < _history.length; n++) _HistoryRow(entry: _history[n], isLast: n == _history.length - 1),
                ]),
              )),
      ],
    );
  }
}

String _unit(bool hourly) => hourly ? 'per hour' : 'fixed';

/// One offered service: icon, name, rate and its Edit rate / Edit details / Remove actions.
class MyServiceCard extends StatelessWidget {
  final MenuService service;
  final MyServiceRate rate;
  final bool busy;
  final VoidCallback onEditRate;
  final VoidCallback onRemove;
  final VoidCallback? onEditDetails; // non-null only for services this cleaner proposed themselves

  const MyServiceCard({
    super.key,
    required this.service,
    required this.rate,
    required this.busy,
    required this.onEditRate,
    required this.onRemove,
    required this.onEditDetails,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final own = onEditDetails != null;
    final custom = rate.priceCents != null;
    final soft = FilledButton.styleFrom(
      backgroundColor: s.primarySofter,
      foregroundColor: context.colors.primary,
      minimumSize: const Size(0, 44),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );
    return SpotlessCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ServiceIconTile(service.icon, background: own ? s.accentSoft : s.primarySoft, foreground: own ? s.accentDeep : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(service.name, style: s.heading(16.5)),
                if (own) SpotlessPill('Proposed by you', colors: (s.accentSoft, s.accentDeep), icon: LucideIcons.sparkles),
              ]),
              const SizedBox(height: 2),
              Text(custom ? 'Default ${formatMoney(service.priceCents)}' : 'Using default rate',
                  style: TextStyle(fontSize: 12.5, color: s.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(formatMoney(rate.priceCents ?? service.priceCents),
                  key: ValueKey(rate.priceCents), style: s.heading(22).copyWith(height: 1)),
            ),
            Text(_unit(service.isHourly), style: TextStyle(fontSize: 12, color: s.muted)),
          ]),
        ]),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : onEditRate,
              style: soft,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.pencil, size: 15),
                SizedBox(width: 6),
                Flexible(child: Text('Edit rate', overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
          if (own) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onEditDetails,
                style: soft,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.filePen, size: 15),
                  SizedBox(width: 6),
                  Flexible(child: Text('Edit details', overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Remove ${service.name}',
            onPressed: busy ? null : onRemove,
            style: IconButton.styleFrom(backgroundColor: s.redSoft, foregroundColor: s.red, side: BorderSide.none),
            icon: const Icon(LucideIcons.trash2, size: 17),
          ),
        ]),
      ]),
    );
  }
}

class _PendingServiceCard extends StatelessWidget {
  final MenuService service;
  final VoidCallback onEditDetails;
  const _PendingServiceCard({required this.service, required this.onEditDetails});

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return SpotlessCard(
      padding: const EdgeInsets.all(16),
      onTap: onEditDetails,
      child: Row(children: [
        ServiceIconTile(service.icon, background: s.goldSoft, foreground: s.gold),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(service.name, style: s.heading(16.5)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SpotlessPill('Pending review', colors: s.awaiting, icon: LucideIcons.hourglass),
              Text('${formatMoney(service.priceCents)} ${_unit(service.isHourly)}', style: TextStyle(fontSize: 12.5, color: s.muted)),
            ]),
          ]),
        ),
        IconButton(
          tooltip: 'Edit details',
          onPressed: onEditDetails,
          style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none),
          icon: Icon(LucideIcons.filePen, size: 18, color: context.colors.primary),
        ),
      ]),
    );
  }
}

/// Hero-style nudge to offer a service the cleaner doesn't yet.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.service, required this.onTap});
  final MenuService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Material(
      color: s.heroBg,
      borderRadius: BorderRadius.circular(s.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(s.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: s.heroChip, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(iconForGlyph(service.icon) ?? LucideIcons.plus, size: 20, color: s.heroAccent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Offer ${service.name}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: s.heroInk)),
                Text(
                  service.isHourly
                      ? 'From ${formatMoney(service.priceCents)} per hour — more ways to get booked.'
                      : '${formatMoney(service.priceCents)} fixed — more ways to get booked.',
                  style: TextStyle(fontSize: 13, color: s.heroMuted),
                ),
              ]),
            ),
            Icon(LucideIcons.arrowRight, color: s.heroAccent),
          ]),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PriceHistoryEntry entry;
  final bool isLast;
  const _HistoryRow({required this.entry, required this.isLast});

  String _fmt(int? cents) {
    final unit = entry.priceType == 'hourly' ? '/hour' : 'fixed';
    if (cents == null) return 'Default ${formatMoney(entry.defaultPriceCents)} $unit';
    return '${formatMoney(cents)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: p, shape: BoxShape.circle, boxShadow: [BoxShadow(color: s.primarySoft, spreadRadius: 4)]),
            ),
            if (!isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 4), color: s.line)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(entry.serviceName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                Text(entry.changedBy == 'cleaner' ? 'by you' : 'by admin', style: TextStyle(fontSize: 12, color: s.muted)),
              ]),
              const SizedBox(height: 2),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: _fmt(entry.oldPriceCents),
                  style: TextStyle(color: s.muted, decoration: TextDecoration.lineThrough),
                ),
                TextSpan(text: '  →  ', style: TextStyle(color: s.muted)),
                TextSpan(text: _fmt(entry.newPriceCents), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]), style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 2),
              Text(friendlyDateTimeString(entry.changedAt), style: TextStyle(fontSize: 12, color: s.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Bottom sheet for one rate. Pops with the typed text ('' = use the default),
/// or null if dismissed.
class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.service, required this.current});
  final MenuService service;
  final MyServiceRate current;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late final _controller = TextEditingController(
    text: widget.current.priceCents != null ? (widget.current.priceCents! / 100).toStringAsFixed(2) : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final sv = widget.service;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Your rate for ${sv.name}', style: s.heading(20)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context, _controller.text),
            decoration: InputDecoration(
              labelText: 'Rate',
              prefixText: '£ ',
              suffixText: sv.isHourly ? 'per hour' : 'fixed',
              helperText: 'Leave blank to use the default ${formatMoney(sv.priceCents)} ${_unit(sv.isHourly)}',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save rate')),
        ]),
      ),
    );
  }
}
