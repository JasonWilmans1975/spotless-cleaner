import 'package:flutter/material.dart';

import '../api_client.dart';

/// Pushed from the Services tab's "+" button — two tabs mirroring the website's
/// "Add a service" modal: opt into an existing menu item at your own rate, or
/// propose a brand-new one for admin review. Pops `true` if anything changed
/// (so the caller knows to refetch), or `false`/null if nothing did.
class AddServiceScreen extends StatefulWidget {
  final List<MenuService> availableServices; // menu items this cleaner doesn't already offer
  final List<MyServiceRate> currentRates; // this cleaner's full current rate list, to merge into

  const AddServiceScreen({super.key, required this.availableServices, required this.currentRates});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _api = ApiClient();

  // "Existing" tab state
  final Map<int, bool> _checked = {};
  final Map<int, TextEditingController> _priceControllers = {};
  bool _savingExisting = false;

  // "Propose new" tab state
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _iconCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _durationMinCtrl = TextEditingController();
  final _durationLabelCtrl = TextEditingController();
  final _featuresCtrl = TextEditingController();
  String _priceType = 'hourly';
  bool _submittingNew = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    for (final s in widget.availableServices) {
      _checked[s.id] = false;
      _priceControllers[s.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _durationMinCtrl.dispose();
    _durationLabelCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  int? _parsePriceCents(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null) return null;
    return (value * 100).round();
  }

  Future<void> _saveExisting() async {
    final newOnes = widget.availableServices
        .where((s) => _checked[s.id] == true)
        .map((s) => MyServiceRate(serviceId: s.id, priceCents: _parsePriceCents(_priceControllers[s.id]!.text)))
        .toList();
    if (newOnes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tick at least one service to add.')));
      return;
    }
    setState(() => _savingExisting = true);
    try {
      final merged = [...widget.currentRates, ...newOnes];
      await _api.updateMyServices(merged);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingExisting = false);
    }
  }

  Future<void> _submitNew() async {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a price greater than £0')));
      return;
    }
    setState(() => _submittingNew = true);
    try {
      await _api.proposeService(
        name: _nameCtrl.text.trim(),
        icon: _iconCtrl.text.trim().isEmpty ? '✦' : _iconCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        priceType: _priceType,
        price: price,
        durationMinutes: int.tryParse(_durationMinCtrl.text.trim()),
        durationLabel: _durationLabelCtrl.text.trim(),
        features: _featuresCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted — awaiting admin approval')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submittingNew = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a service'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Existing'), Tab(text: 'Propose new')]),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildExistingTab(), _buildProposeTab()],
      ),
    );
  }

  Widget _buildExistingTab() {
    if (widget.availableServices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "You're already offering everything on the menu — try proposing a new one instead.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: widget.availableServices.map((s) {
              final checked = _checked[s.id] ?? false;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(() => _checked[s.id] = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('${s.icon}  ${s.name}'),
                      ),
                      if (checked)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: TextField(
                            controller: _priceControllers[s.id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Your rate (optional)',
                              prefixText: '£ ',
                              helperText:
                                  'Leave blank for the default £${(s.priceCents / 100).toStringAsFixed(2)} ${s.isHourly ? "/hour" : "fixed"}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _savingExisting ? null : _saveExisting,
              child: _savingExisting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add selected'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProposeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Offer something not already on the menu — an admin reviews it before it goes live. Once approved, you're set up to offer it straight away at the rate you set here.",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Service name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a service name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _iconCtrl, decoration: const InputDecoration(labelText: 'Icon (emoji, optional)'), maxLength: 4),
            TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: "What's included?"), maxLines: 2),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _priceType,
              decoration: const InputDecoration(labelText: 'Pricing type'),
              items: const [
                DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed price')),
              ],
              onChanged: (v) => setState(() => _priceType = v ?? 'hourly'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Your price (£)'),
              validator: (v) {
                final p = double.tryParse((v ?? '').trim());
                return (p == null || p <= 0) ? 'Enter a price greater than £0' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durationMinCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Typical duration in minutes (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durationLabelCtrl,
              decoration: const InputDecoration(labelText: 'Duration label shown to customers (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _featuresCtrl,
              decoration: const InputDecoration(labelText: "What's included (one per line, optional)"),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submittingNew ? null : _submitNew,
              child: _submittingNew
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit for approval'),
            ),
          ],
        ),
      ),
    );
  }
}
