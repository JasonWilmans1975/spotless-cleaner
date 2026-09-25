import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'layout.dart';

/// Segmented progress for the booking flow: the first [current] segments fill.
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({super.key, required this.current, this.labels = const ['Schedule', 'Details', 'Pay']});
  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 4,
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: i < current ? context.colors.primary : s.line,
              ),
            ),
            const SizedBox(height: 6),
            Text(labels[i],
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: i < current ? null : s.muted)),
          ]),
        ),
      ],
    ]);
  }
}

/// Horizontal strip of day chips covering every day from [first] for
/// [dayCount] days. Exactly seven chips fit the width at any screen size; the
/// strip scrolls through the rest and keeps [selected] centred when it changes
/// (e.g. after a pick from the full calendar).
class DayStrip extends StatefulWidget {
  const DayStrip({
    super.key,
    required this.first,
    required this.dayCount,
    required this.selected,
    required this.onSelected,
    this.isEnabled,
    this.onVisibleRangeChanged,
  });

  /// Date-only (local midnight).
  final DateTime first;
  final int dayCount;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;
  final bool Function(DateTime day)? isEnabled;

  /// Called with the first and last fully visible day whenever that changes.
  final void Function(DateTime first, DateTime last)? onVisibleRangeChanged;

  @override
  State<DayStrip> createState() => DayStripState();
}

class DayStripState extends State<DayStrip> {
  static const _gap = 8.0;
  static const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _controller = ScrollController();
  double _chipWidth = 44;
  int _firstVisible = -1;

  DateTime _day(int i) => DateTime(widget.first.year, widget.first.month, widget.first.day + i);
  int _indexOf(DateTime d) =>
      (DateTime(d.year, d.month, d.day).difference(widget.first).inHours / 24).round();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportVisible);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.selected != null) scrollTo(widget.selected!, animate: false);
      _reportVisible();
    });
  }

  @override
  void didUpdateWidget(DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sel = widget.selected;
    if (sel != null && sel != oldWidget.selected) scrollTo(sel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolls so [day] sits in the middle of the strip (clamped at the ends).
  void scrollTo(DateTime day, {bool animate = true}) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_indexOf(day) * (_chipWidth + _gap) - (pos.viewportDimension - _chipWidth) / 2)
        .clamp(0.0, pos.maxScrollExtent);
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (animate && !reduce) {
      _controller.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    } else {
      _controller.jumpTo(target);
    }
  }

  void _reportVisible() {
    if (!_controller.hasClients || widget.onVisibleRangeChanged == null) return;
    final first = (_controller.offset / (_chipWidth + _gap)).round().clamp(0, widget.dayCount - 1);
    if (first == _firstVisible) return;
    _firstVisible = first;
    widget.onVisibleRangeChanged!(_day(first), _day((first + 6).clamp(0, widget.dayCount - 1)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    return LayoutBuilder(builder: (context, box) {
      _chipWidth = (box.maxWidth - 6 * _gap) / 7;
      return SizedBox(
        height: 70,
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemCount: widget.dayCount,
          separatorBuilder: (context, i) => const SizedBox(width: _gap),
          itemBuilder: (context, i) {
            final day = _day(i);
            final sel = widget.selected;
            final selected = sel != null && _indexOf(sel) == i;
            final enabled = widget.isEnabled?.call(day) ?? true;
            return Semantics(
              selected: selected,
              button: true,
              label: '${_dow[day.weekday - 1]} ${day.day}',
              child: Opacity(
                opacity: enabled ? 1 : .45,
                child: Pressable(enabled: enabled, child: GestureDetector(
                  onTap: enabled
                      ? () {
                          HapticFeedback.selectionClick();
                          widget.onSelected(day);
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: _chipWidth,
                    decoration: BoxDecoration(
                      color: selected ? p : Colors.white,
                      borderRadius: BorderRadius.circular(s.radiusMd),
                      border: Border.all(color: selected ? p : s.line),
                    ),
                    padding: const EdgeInsets.all(4),
                    // Large text sizes shrink to fit rather than wrap inside the fixed chip.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_dow[day.weekday - 1],
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white.withValues(alpha: .8) : s.muted,
                            )),
                        const SizedBox(height: 3),
                        Text('${day.day}', style: s.heading(19, color: selected ? Colors.white : null)),
                      ]),
                    ),
                  ),
                )),
              ),
            );
          },
        ),
      );
    });
  }
}

/// Grid of pill chips (time slots, tip amounts, radius). Unavailable items
/// render transparent with a strikethrough and can't be tapped.
class ChoiceChipGrid<T> extends StatelessWidget {
  const ChoiceChipGrid({
    super.key,
    required this.items,
    required this.labelOf,
    required this.isSelected,
    required this.onSelected,
    this.isEnabled,
    this.columns = 3,
    this.selectedColor,
    this.height = 48,
  });
  final List<T> items;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final ValueChanged<T> onSelected;
  final bool Function(T)? isEnabled;
  final int columns;

  /// Defaults to primary; the tip picker uses ink.
  final Color? selectedColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final fill = selectedColor ?? context.colors.primary;
    const gap = 10.0;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final item in items)
          Builder(builder: (context) {
            final selected = isSelected(item);
            final enabled = isEnabled?.call(item) ?? true;
            return Semantics(
              selected: selected,
              button: true,
              enabled: enabled,
              child: Pressable(enabled: enabled, child: GestureDetector(
                onTap: enabled
                    ? () {
                        HapticFeedback.selectionClick();
                        onSelected(item);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: w,
                  height: height,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: selected ? fill : (enabled ? Colors.white : Colors.transparent),
                    shape: StadiumBorder(side: BorderSide(color: selected ? fill : s.line)),
                  ),
                  child: Text(
                    labelOf(item),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : (enabled ? null : s.muted),
                      decoration: enabled ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
              )),
            );
          }),
      ]);
    });
  }
}

/// Multi-select pill (checkout notes, rating praise): soft primary with a
/// check when on.
class ToggleChip extends StatelessWidget {
  const ToggleChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // 36pt pill, 44pt touch area — callers drop runSpacing by the 8 this adds.
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected ? s.primarySoft : Colors.white,
            shape: StadiumBorder(side: BorderSide(color: selected ? p : s.line)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) ...[Icon(LucideIcons.check, size: 14, color: s.primaryDeep), const SizedBox(width: 5)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? s.primaryDeep : context.text.bodyMedium?.color,
                  )),
            ),
          ]),
        )),
      )),
    );
  }
}
