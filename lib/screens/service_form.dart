import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../service_icons.dart';
import '../ui/layout.dart';
import '../ui/pickers.dart';

/// The glyph stored when no icon is picked (same default as before).
const kDefaultServiceGlyph = '✦';

/// Lines of "what's included", trimmed, blanks dropped.
List<String> featureLines(String text) => text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// State for the service details form — shared by "Propose new" and "Edit
/// service" so both keep exactly the same fields, validation and payload.
class ServiceFormController {
  ServiceFormController([MenuService? service])
      : name = TextEditingController(text: service?.name ?? ''),
        description = TextEditingController(text: service?.description ?? ''),
        price = TextEditingController(text: service == null ? '' : (service.priceCents / 100).toStringAsFixed(2)),
        durationMinutes = TextEditingController(text: service?.durationMinutes.toString() ?? ''),
        durationLabel = TextEditingController(text: service?.durationLabel ?? ''),
        features = TextEditingController(text: service?.features.join('\n') ?? ''),
        priceType = service?.priceType ?? 'hourly',
        icon = (service?.icon.trim().isNotEmpty ?? false) ? service!.icon.trim() : kDefaultServiceGlyph,
        originalIcon = service?.icon.trim();

  final TextEditingController name, description, price, durationMinutes, durationLabel, features;
  String priceType;

  /// The glyph saved in `services.icon`.
  String icon;

  /// The service's icon when editing — kept as a choice if it isn't one of
  /// [kServiceIcons], so older values survive unless the cleaner picks another.
  final String? originalIcon;

  double? get priceValue => double.tryParse(price.text.trim());

  void dispose() {
    for (final c in [name, description, price, durationMinutes, durationLabel, features]) {
      c.dispose();
    }
  }
}

/// The service details fields. Wrap in a [Form] and validate before reading
/// the [ServiceFormController].
class ServiceDetailsFields extends StatefulWidget {
  const ServiceDetailsFields({super.key, required this.controller});
  final ServiceFormController controller;

  @override
  State<ServiceDetailsFields> createState() => _ServiceDetailsFieldsState();
}

class _ServiceDetailsFieldsState extends State<ServiceDetailsFields> {
  ServiceFormController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.description.addListener(_rebuild); // character counter
  }

  @override
  void dispose() {
    c.description.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final original = c.originalIcon;
    final choices = [
      ...kServiceIcons.map((o) => o.glyph),
      if (original != null && original.isNotEmpty && iconForGlyph(original) == null) original,
    ];
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: s.muted)),
        );
    const gap = SizedBox(height: 16);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        controller: c.name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Service name', hintText: 'e.g. Oven deep clean'),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a service name' : null,
      ),
      gap,
      label('Icon'),
      LayoutBuilder(builder: (context, box) {
        const spacing = 10.0;
        final w = (box.maxWidth - 2 * spacing) / 3;
        return Wrap(spacing: spacing, runSpacing: spacing, children: [
          for (final glyph in choices)
            SizedBox(
              width: w,
              child: _IconChoice(
                glyph: glyph,
                label: kServiceIcons.where((o) => o.glyph == glyph).firstOrNull?.label ?? 'Current',
                selected: c.icon == glyph,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => c.icon = glyph);
                },
              ),
            ),
        ]);
      }),
      gap,
      TextFormField(
        controller: c.description,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Short description',
          hintText: 'What makes this clean different?',
          counterText: '${c.description.text.trim().length} characters',
        ),
      ),
      gap,
      label('Pricing'),
      ChoiceChipGrid<String>(
        items: const ['hourly', 'fixed'],
        columns: 2,
        height: 44,
        labelOf: (t) => t == 'hourly' ? 'Hourly' : 'Fixed price',
        isSelected: (t) => t == c.priceType,
        onSelected: (t) => setState(() => c.priceType = t),
      ),
      gap,
      TextFormField(
        controller: c.price,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Your price',
          prefixText: '£ ',
          suffixText: c.priceType == 'hourly' ? 'per hour' : 'fixed',
        ),
        validator: (v) {
          final p = double.tryParse((v ?? '').trim());
          return (p == null || p <= 0) ? 'Enter a price greater than £0' : null;
        },
      ),
      gap,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextFormField(
            controller: c.durationMinutes,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Duration (mins)', hintText: 'Optional'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: c.durationLabel,
            decoration: const InputDecoration(labelText: 'Label for customers', hintText: 'e.g. 2–3 hours'),
          ),
        ),
      ]),
      gap,
      TextFormField(
        controller: c.features,
        minLines: 3,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: "What's included",
          hintText: 'One per line, e.g.\nInside the oven\nHob and extractor',
          helperText: 'Optional — shown to customers and used as your job checklist',
        ),
      ),
    ]);
  }
}

/// One icon option: tile + label, primary border and soft ring when selected.
class _IconChoice extends StatelessWidget {
  const _IconChoice({required this.glyph, required this.label, required this.selected, required this.onTap});
  final String glyph, label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label icon',
      excludeSemantics: true,
      child: Pressable(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(s.radiusMd),
              border: Border.all(color: selected ? p : s.line, width: 1.5),
              boxShadow: selected ? [BoxShadow(color: s.primarySoft, spreadRadius: 3)] : const [],
            ),
            child: Column(children: [
              ServiceIconTile(glyph, size: 38, background: selected ? s.primarySoft : s.primarySofter),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? p : null)),
            ]),
          ),
        ),
      ),
    );
  }
}
