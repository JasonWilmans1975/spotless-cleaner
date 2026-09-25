import 'package:flutter/material.dart';

import '../main.dart';

import '../api_client.dart';

/// Pushed from the Services tab to edit the full details — not just the rate —
/// of a service this cleaner proposed themselves. Pre-fills from [service] and
/// PATCHes on save; works whether the proposal is still pending admin review
/// or already approved and live (editing never changes its approval status).
/// Pops `true` on success so the caller knows to refetch.
class EditServiceDetailsScreen extends StatefulWidget {
  final MenuService service;

  const EditServiceDetailsScreen({super.key, required this.service});

  @override
  State<EditServiceDetailsScreen> createState() => _EditServiceDetailsScreenState();
}

class _EditServiceDetailsScreenState extends State<EditServiceDetailsScreen> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _iconCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _durationMinCtrl;
  late final TextEditingController _durationLabelCtrl;
  late final TextEditingController _featuresCtrl;
  late String _priceType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s.name);
    _iconCtrl = TextEditingController(text: s.icon);
    _descCtrl = TextEditingController(text: s.description);
    _priceCtrl = TextEditingController(text: (s.priceCents / 100).toStringAsFixed(2));
    _durationMinCtrl = TextEditingController(text: s.durationMinutes.toString());
    _durationLabelCtrl = TextEditingController(text: s.durationLabel);
    _featuresCtrl = TextEditingController(text: s.features.join('\n'));
    _priceType = s.priceType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _durationMinCtrl.dispose();
    _durationLabelCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a price greater than £0')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.updateProposedService(
        serviceId: widget.service.id,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service updated')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.service.status == 'pending';
    return Scaffold(
      appBar: AppBar(title: const Text('Edit service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isPending
                    ? "This service is still awaiting admin approval — changes here are saved right away and don't restart the review."
                    : "This service is already live. Changes here go into effect immediately.",
                style: const TextStyle(color: kBrandMuted),
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
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}