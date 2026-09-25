import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';
import 'service_form.dart';

/// Pushed from My services to edit the full details — not just the rate — of
/// a service this cleaner proposed themselves. Pre-fills from [service] and
/// saves through updateProposedService; works whether the proposal is still
/// pending admin review or already approved and live (editing never changes
/// its approval status). Pops `true` on success so the caller knows to refetch.
class EditServiceDetailsScreen extends StatefulWidget {
  final MenuService service;

  const EditServiceDetailsScreen({super.key, required this.service});

  @override
  State<EditServiceDetailsScreen> createState() => _EditServiceDetailsScreenState();
}

class _EditServiceDetailsScreenState extends State<EditServiceDetailsScreen> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  late final _form = ServiceFormController(widget.service);
  bool _saving = false;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = _form.priceValue;
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a price greater than £0')));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      await _api.updateProposedService(
        serviceId: widget.service.id,
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
    final s = context.tokens;
    final isPending = widget.service.status == 'pending';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            ScreenHeader(title: 'Edit service', subtitle: widget.service.name, showBack: true),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isPending ? s.goldSoft : s.primarySofter,
                        borderRadius: BorderRadius.circular(s.radius),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        IconTile(
                          isPending ? LucideIcons.hourglass : LucideIcons.circleCheckBig,
                          size: 36,
                          circle: true,
                          background: Colors.white,
                          foreground: isPending ? s.gold : context.colors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isPending
                                ? "This service is still awaiting admin approval — changes here are saved right away and don't restart the review."
                                : 'This service is already live. Changes here go into effect immediately.',
                            style: TextStyle(fontSize: 13.5, height: 1.45, color: isPending ? s.gold : context.colors.onSurface),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    ServiceDetailsFields(controller: _form),
                  ],
                ),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: StickyBottomBar(
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save changes'),
          ),
        ),
      ),
    );
  }
}
