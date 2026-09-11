import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import 'add_service_screen.dart';
import 'edit_service_details_screen.dart';

/// "My services" (rate edit / remove), pending self-proposed services, and rate
/// history — the JSON/mobile equivalent of the corresponding sections on the
/// website's /cleaner dashboard.
///
/// Fetches its own data independently of the Schedule tab. Services change far
/// less often than bookings, so this doesn't poll unconditionally — but while a
/// proposed service is still pending, an admin approving/rejecting it elsewhere
/// (the website) is exactly the kind of change this screen needs to notice on
/// its own, same as the website dashboard's own polling for the same thing —
/// so it polls only while [_pendingProposed] is non-empty, plus a refresh
/// whenever the app comes back to the foreground.
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
  /// otherwise a quiet poll silently moving a tile out of "Pending" is easy to miss.
  void _notifyResolvedServices({required List<MenuService>? previous, required List<MenuService> current}) {
    if (previous == null) return; // first load — nothing to compare against yet
    final previousIds = previous.map((s) => s.id).toSet();
    final currentIds = current.map((s) => s.id).toSet();
    final resolvedCount = previousIds.difference(currentIds).length;
    if (resolvedCount == 0) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(resolvedCount == 1 ? 'A proposed service was reviewed — list updated' : '$resolvedCount proposed services were reviewed — list updated'),
    ));
  }

  /// [silent] skips the full-page spinner and swallows errors — used for the
  /// background poll and app-resume refresh, so a flaky connection doesn't wipe
  /// out whatever's already on screen.
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
      await _loadAll();
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
    final controller = TextEditingController(
      text: current.priceCents != null ? (current.priceCents! / 100).toStringAsFixed(2) : '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Your rate for ${service.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Rate (£)',
            prefixText: '£ ',
            helperText: 'Leave blank to use the default £${(service.priceCents / 100).toStringAsFixed(2)} ${service.isHourly ? "/hour" : "fixed"}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    // Deliberately not disposing `controller` here: it's a one-off local
    // TextEditingController with no State object of its own, and the dialog's
    // AlertDialog/TextField can still be mid-exit-animation for a moment after
    // showDialog's Future resolves (Navigator.pop returns before the transition
    // finishes). Disposing it at this exact point raced that animation and
    // crashed with "a disposed ChangeNotifier was used" whenever a rebuild (e.g.
    // this screen's background poll) landed in that window. Skipping dispose is
    // safe here — nothing keeps a reference to it once this function returns, so
    // it's simply garbage collected instead.
    final text = controller.text.trim();
    if (save != true) return;
    final priceCents = _parsePriceCents(text);
    final updated = [
      for (final r in _myRates)
        if (r.serviceId != service.id) r,
      MyServiceRate(serviceId: service.id, priceCents: priceCents),
    ];
    await _saveRates(updated, successMessage: 'Rate saved');
  }

  int? _parsePriceCents(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    return value == null ? null : (value * 100).round();
  }

  Future<void> _removeService(MenuService service) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this service?'),
        content: Text("You'll stop being offered for ${service.name}."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
        actions: [
          IconButton(onPressed: _loading ? null : _openAddService, icon: const Icon(Icons.add), tooltip: 'Add service'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: Builder(builder: (context) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_error != null) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 40),
                Icon(Icons.wifi_off, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _loadAll, child: const Text('Try again')),
              ],
            );
          }

          final myServiceIds = _myRates.map((r) => r.serviceId).toSet();
          final myOffered = _allServices.where((s) => myServiceIds.contains(s.id)).toList();
          final rateByServiceId = {for (final r in _myRates) r.serviceId: r};

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text('My services', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Tap a service to edit your rate. Services you proposed also have a ✏️ to edit their full details.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              if (myOffered.isEmpty && _pendingProposed.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "You're not offering any services yet — tap + above to get started.",
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                )
              else ...[
                ...myOffered.map((s) => _MyServiceCard(
                  service: s,
                  rate: rateByServiceId[s.id]!,
                  busy: _savingRates,
                  onTap: () => _editRate(s, rateByServiceId[s.id]!),
                  onRemove: () => _removeService(s),
                  onEditDetails: s.createdByCleanerId == widget.cleanerId ? () => _editDetails(s) : null,
                )),
                ..._pendingProposed.map((s) => _PendingServiceCard(service: s, onEditDetails: () => _editDetails(s))),
              ],
              const SizedBox(height: 28),
              Text('Rate history', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('A record of every change to your rates, and who made it.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              const SizedBox(height: 10),
              if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No rate changes yet.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                )
              else
                ..._history.map((h) => _HistoryRow(entry: h)),
            ],
          );
        }),
      ),
    );
  }
}

String _fmtRate(MenuService service, MyServiceRate rate) {
  final unit = service.isHourly ? '/hour' : 'fixed';
  if (rate.priceCents == null) return 'Default ${formatMoney(service.priceCents)} $unit';
  return '${formatMoney(rate.priceCents!)} $unit';
}

class _MyServiceCard extends StatelessWidget {
  final MenuService service;
  final MyServiceRate rate;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onEditDetails; // non-null only for services this cleaner proposed themselves

  const _MyServiceCard({
    required this.service,
    required this.rate,
    required this.busy,
    required this.onTap,
    required this.onRemove,
    required this.onEditDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(service.icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(_fmtRate(service, rate), style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  ],
                ),
              ),
              if (onEditDetails != null)
                IconButton(
                  onPressed: busy ? null : onEditDetails,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit details',
                ),
              IconButton(
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline),
                color: Colors.red.shade400,
                tooltip: 'Remove',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingServiceCard extends StatelessWidget {
  final MenuService service;
  final VoidCallback onEditDetails;
  const _PendingServiceCard({required this.service, required this.onEditDetails});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.amber.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEditDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(service.icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${formatMoney(service.priceCents)} ${service.isHourly ? "/hour" : "fixed"}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: onEditDetails, icon: const Icon(Icons.edit_outlined), tooltip: 'Edit details'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.amber.shade200, borderRadius: BorderRadius.circular(20)),
                child: Text('⏳ Pending', style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PriceHistoryEntry entry;
  const _HistoryRow({required this.entry});

  String _fmt(int? cents) {
    if (cents == null) return 'Default (${formatMoney(entry.defaultPriceCents)})';
    final unit = entry.priceType == 'hourly' ? '/hour' : 'fixed';
    return '${formatMoney(cents)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(entry.serviceName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
              Text(
                entry.changedBy == 'cleaner' ? 'You' : 'Admin',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${_fmt(entry.oldPriceCents)} → ${_fmt(entry.newPriceCents)}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(friendlyDateTimeString(entry.changedAt), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          const Divider(height: 18),
        ],
      ),
    );
  }
}