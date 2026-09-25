import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../format.dart';
import '../service_icons.dart';
import '../ui/layout.dart';
import '../ui/pickers.dart';
import '../ui/tiles.dart';
import 'service_form.dart';
import 'services_tab.dart';

/// Pushed from My services' "+" button — two segments mirroring the website's
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

class _AddServiceScreenState extends State<AddServiceScreen> {
  final _api = ApiClient();
  int _tab = 0; // 0 Existing, 1 Propose new

  // "Existing" state
  final _checked = <int>{};
  late final Map<int, TextEditingController> _priceControllers = {
    for (final s in widget.availableServices) s.id: TextEditingController(),
  };
  bool _savingExisting = false;

  // "Propose new" state
  final _formKey = GlobalKey<FormState>();
  final _form = ServiceFormController();
  bool _submittingNew = false;

  @override
  void dispose() {
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    _form.dispose();
    super.dispose();
  }

  Future<void> _saveExisting() async {
    final newOnes = [
      for (final s in widget.availableServices)
        if (_checked.contains(s.id)) MyServiceRate(serviceId: s.id, priceCents: parsePriceCents(_priceControllers[s.id]!.text)),
    ];
    if (newOnes.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _savingExisting = true);
    try {
      await _api.updateMyServices([...widget.currentRates, ...newOnes]);
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
    final price = _form.priceValue;
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a price greater than £0')));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _submittingNew = true);
    try {
      await _api.proposeService(
        name: _form.name.text.trim(),
        icon: _form.icon,
        description: _form.description.text.trim(),
        priceType: _form.priceType,
        price: price,
        durationMinutes: int.tryParse(_form.durationMinutes.text.trim()),
        durationLabel: _form.durationLabel.text.trim(),
        features: featureLines(_form.features.text),
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
    final count = _checked.length;
    final busy = _tab == 0 ? _savingExisting : _submittingNew;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const ScreenHeader(title: 'Add a service', showBack: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedPills(
                labels: const ['Existing', 'Propose new'],
                selected: _tab,
                onSelected: (i) {
                  FocusScope.of(context).unfocus();
                  setState(() => _tab = i);
                },
              ),
            ),
            Expanded(child: IndexedStack(index: _tab, children: [_existingTab(), _proposeTab()])),
          ]),
        ),
        bottomNavigationBar: _tab == 0 && widget.availableServices.isEmpty
            ? null
            : StickyBottomBar(
                child: FilledButton(
                  onPressed: busy || (_tab == 0 && count == 0) ? null : (_tab == 0 ? _saveExisting : _submitNew),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  child: busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_tab == 0 ? LucideIcons.plus : LucideIcons.send, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _tab == 1 ? 'Send for review' : (count == 0 ? 'Select a service to add' : 'Add selected ($count)'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                ),
              ),
      ),
    );
  }

  Widget _existingTab() {
    final s = context.tokens;
    if (widget.availableServices.isEmpty) {
      return ListView(children: [
        EmptyState(
          icon: LucideIcons.circleCheckBig,
          title: "You're offering everything on the menu",
          message: 'Have something else in mind? Propose a new service.',
          actionLabel: 'Propose new',
          onAction: () => setState(() => _tab = 1),
        ),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text('Pick services already on the menu. You can set your own rate now, or leave it blank to use the default.',
            style: TextStyle(fontSize: 14, height: 1.5, color: s.muted)),
        const SizedBox(height: 12),
        for (var n = 0; n < widget.availableServices.length; n++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FadeSlideIn(index: n, child: _existingCard(widget.availableServices[n])),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: s.primarySofter, borderRadius: BorderRadius.circular(s.radius)),
          child: Row(children: [
            Icon(LucideIcons.lightbulb, size: 18, color: context.colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: "Can't find it? Switch to "),
                  TextSpan(text: 'Propose new', style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.primary)),
                  const TextSpan(text: '.'),
                ]),
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _existingCard(MenuService sv) {
    final s = context.tokens;
    final checked = _checked.contains(sv.id);
    final detail = [
      'Default ${formatMoney(sv.priceCents)}${sv.isHourly ? '/hr' : ''}',
      if (sv.durationLabel.isNotEmpty) sv.durationLabel else if (!sv.isHourly) 'Fixed price',
    ].join(' · ');
    return SelectableCard(
      selected: checked,
      checkbox: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => checked ? _checked.remove(sv.id) : _checked.add(sv.id));
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ServiceIconTile(sv.icon, size: 44, background: s.accentSoft, foreground: context.colors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sv.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              Text(detail, style: TextStyle(fontSize: 13, color: s.muted)),
            ]),
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: checked
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: _priceControllers[sv.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Your rate (optional)',
                      prefixText: '£ ',
                      suffixText: sv.isHourly ? 'per hour' : 'fixed',
                      helperText: 'Leave blank for the default ${formatMoney(sv.priceCents)}',
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _proposeTab() {
    final s = context.tokens;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: s.primarySofter, borderRadius: BorderRadius.circular(s.radius)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const IconTile(LucideIcons.shieldCheck, size: 36, circle: true, background: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Offer something not already on the menu. An admin reviews it before it goes live — once approved, you're set up to offer it straight away at the price you set here.",
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: context.colors.onSurface),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          ServiceDetailsFields(controller: _form),
        ],
      ),
    );
  }
}
