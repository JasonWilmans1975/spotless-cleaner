import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/spotless_theme.dart';
import 'layout.dart';

/// Outline icon for a service, picked from its slug (admin-created services
/// fall back to sparkles). The `services.icon` column holds an emoji, which
/// the redesign doesn't use.
IconData serviceIcon(String slug) {
  if (slug.contains('tenancy') || slug.contains('move')) return LucideIcons.arrowLeftRight;
  if (slug.contains('deep')) return LucideIcons.sparkle;
  if (slug.contains('airbnb') || slug.contains('turnover')) return LucideIcons.bedDouble;
  if (slug.contains('office') || slug.contains('commercial')) return LucideIcons.building2;
  if (slug.contains('oven')) return LucideIcons.cookingPot;
  if (slug.contains('window')) return LucideIcons.appWindow;
  if (slug.contains('carpet')) return LucideIcons.layers;
  if (slug.contains('standard') || slug.contains('regular') || slug.contains('home')) return LucideIcons.house;
  return LucideIcons.sparkles;
}

/// Unread / pending count: a circle for single digits, a pill for more,
/// with an optional white ring so it stands out over icons.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.size = 18, this.ring = true});
  final int count;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: count > 9 ? 5 : 0),
      decoration: ShapeDecoration(
        color: context.colors.secondary,
        shape: StadiumBorder(side: ring ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none),
      ),
      // widthFactor: 1 hugs the number — a Container with its own alignment
      // would stretch to fill whatever width it's given.
      child: Center(
        widthFactor: 1,
        child: Text(count > 99 ? '99+' : '$count',
            style: TextStyle(color: Colors.white, fontSize: size * .58, fontWeight: FontWeight.w700, height: 1)),
      ),
    );
  }
}

/// The Spotless "S" mark: primary rounded square with the button shadow.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42, this.inverted = false});
  final double size;

  /// White square with a primary "S", for use on primary backgrounds.
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverted ? Colors.white : p,
        borderRadius: BorderRadius.circular(size * .29),
        boxShadow: inverted ? null : s.buttonShadow,
      ),
      child: Text('S', style: s.heading(size * .45, color: inverted ? p : Colors.white)),
    );
  }
}

/// Rounded square (or circle) with an icon on a soft background.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 40, this.background, this.foreground, this.circle = false});
  final IconData icon;
  final double size;
  final Color? background, foreground;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? s.primarySofter,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(s.radiusSm),
      ),
      child: Icon(icon, size: size * .46, color: foreground ?? context.colors.primary),
    );
  }
}

/// "Lucy Green" -> "Lucy G." for tight spots (cards, carousels).
String shortName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.length > 1 ? '${parts.first} ${parts.last[0]}.' : name.trim();
}

/// Circular photo, or up to two initials on a soft background.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.url, this.size = 40, this.background, this.foreground});
  final String name;
  final String? url;
  final double size;
  final Color? background, foreground;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final photo = url != null && url!.startsWith('http');
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: background ?? s.primarySoft, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: photo
          ? Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => _initials(s),
            )
          : _initials(s),
    );
  }

  Widget _initials(SpotlessTokens s) =>
      Text(initialsOf(name), style: s.heading(size * .35, color: foreground ?? s.primaryDeep));
}

/// Dashed rounded outline around [child] ("All services", "Add another address").
class DashedBorder extends StatelessWidget {
  const DashedBorder({super.key, required this.child, this.color, this.radius});
  final Widget child;
  final Color? color;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(color ?? s.line, radius ?? s.radius),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(.75), Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color || old.radius != radius;
}

/// DOW / day / month block used on booking cards.
class DateBlock extends StatelessWidget {
  const DateBlock(this.date, {super.key});
  final DateTime date;

  static const _dow = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: s.primarySofter,
        border: Border.all(color: s.primarySoft),
        borderRadius: BorderRadius.circular(s.radiusSm),
      ),
      child: Column(children: [
        Text(_dow[date.weekday - 1],
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .9, color: context.colors.primary)),
        Text('${date.day}', style: s.heading(24).copyWith(height: 1.1)),
        Text(_mon[date.month - 1], style: TextStyle(fontSize: 11.5, color: s.muted)),
      ]),
    );
  }
}

/// Card with a radio circle (or checkbox) that gains a primary border and soft
/// ring when selected. Selection changes animate.
class SelectableCard extends StatelessWidget {
  const SelectableCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.checkbox = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final bool checkbox;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    final radius = BorderRadius.circular(s.radius);
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(enabled: onTap != null, child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: selected ? p : s.line, width: 1.5),
          boxShadow: selected ? [BoxShadow(color: s.primarySoft, spreadRadius: 3)] : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: padding,
              child: Row(children: [
                Expanded(child: child),
                const SizedBox(width: 12),
                _Indicator(selected: selected, checkbox: checkbox),
              ]),
            ),
          ),
        ),
      )),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.selected, required this.checkbox});
  final bool selected, checkbox;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: checkbox ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: checkbox ? BorderRadius.circular(7) : null,
        color: checkbox && selected ? p : Colors.transparent,
        border: Border.all(color: selected ? p : s.line, width: 2),
      ),
      alignment: Alignment.center,
      child: checkbox
          ? (selected ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null)
          : AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? p : Colors.transparent),
            ),
    );
  }
}

enum TimelineState { done, current, future }

/// One step of the vertical booking timeline.
class TimelineTile extends StatelessWidget {
  const TimelineTile({super.key, required this.title, this.subtitle, required this.state, this.isLast = false, this.onTap});
  final String title;
  final String? subtitle;
  final TimelineState state;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final p = context.colors.primary;
    final dot = switch (state) {
      TimelineState.done => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: p, shape: BoxShape.circle),
          child: const Icon(LucideIcons.check, size: 14, color: Colors.white),
        ),
      TimelineState.current => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: s.primarySoft, shape: BoxShape.circle, border: Border.all(color: p, width: 2)),
          alignment: Alignment.center,
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p, shape: BoxShape.circle)),
        ),
      TimelineState.future => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: s.line, width: 2)),
        ),
    };
    final future = state == TimelineState.future;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          dot,
          if (!isLast)
            Expanded(
              child: Container(
                width: 2,
                constraints: const BoxConstraints(minHeight: 22),
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: state == TimelineState.done ? p : s.line,
              ),
            ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? p : (future ? s.muted : null),
                    )),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: s.muted)),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
