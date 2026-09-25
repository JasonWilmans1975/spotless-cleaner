import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/spotless_theme.dart';

extension SpotlessContext on BuildContext {
  SpotlessTokens get tokens => Theme.of(this).extension<SpotlessTokens>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Shrinks its child to 97% while a finger is down (the design's press
/// feedback). Pointer-only, so it never steals taps; off with reduced motion.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? .97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// White card with the design's border, radius and soft drop shadow.
class SpotlessCard extends StatelessWidget {
  const SpotlessCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final radius = BorderRadius.circular(s.radius);
    return Pressable(
      enabled: onTap != null,
      child: DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: radius,
        border: Border.all(color: s.line),
        boxShadow: s.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    ),
    );
  }
}

/// In-body page header: optional back button, title + subtitle, trailing actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.showBack = false, this.trailing = const []});
  final String title;
  final String? subtitle;
  final bool showBack;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(children: [
        if (showBack) ...[
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(LucideIcons.chevronLeft, size: 20),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(subtitle!, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ]),
        ),
        for (final w in trailing) ...[const SizedBox(width: 8), w],
      ]),
    );
  }
}

/// Section title (heading 19) with an optional trailing link such as "See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.trailing});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(title, style: context.tokens.heading(19))),
      ?trailing,
      if (actionLabel != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(44, 44)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(actionLabel!, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronRight, size: 16),
          ]),
        ),
    ]);
  }
}

/// Uppercase caption above a group ("YOUR DETAILS", "SEPTEMBER 2026").
class Overline extends StatelessWidget {
  const Overline(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: context.tokens.muted),
      );
}

/// Red message box for a failed action (log in, register, confirm booking).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: s.redSoft, borderRadius: BorderRadius.circular(s.radiusSm)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(LucideIcons.circleAlert, size: 18, color: s.red),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: s.red))),
      ]),
    );
  }
}

/// White bar pinned to the bottom of a pushed screen (Continue / Confirm).
class StickyBottomBar extends StatelessWidget {
  const StickyBottomBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: context.tokens.line))),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: child),
      ),
    );
  }
}

/// Soft circle icon, title, helper text and an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: s.primarySofter, shape: BoxShape.circle),
          child: Icon(icon, size: 38, color: context.colors.primary),
        ),
        const SizedBox(height: 18),
        Text(title, style: s.heading(19), textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, style: context.text.bodyMedium?.copyWith(color: s.muted), textAlign: TextAlign.center),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 26)),
            child: Text(actionLabel!),
          ),
        ],
      ]),
    );
  }
}

/// Overline + white card of rows separated by hairlines (Account screen).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Overline(label)),
      SpotlessCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ]),
      ),
    ]);
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconBackground,
    this.iconColor,
    this.titleColor,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconBackground, iconColor, titleColor;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBackground ?? s.primarySofter, borderRadius: BorderRadius.circular(s.radiusSm)),
            child: Icon(icon, size: 19, color: iconColor ?? context.colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: titleColor)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: TextStyle(fontSize: 13, color: s.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ]),
          ),
          trailing ?? (onTap != null ? Icon(LucideIcons.chevronRight, size: 18, color: s.muted) : const SizedBox.shrink()),
        ]),
      ),
    );
  }
}

/// A [SettingsRow] whose trailing control is a switch.
class PillSwitchRow extends StatelessWidget {
  const PillSwitchRow({super.key, required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

/// Fades a child in while sliding it up 8px; [index] staggers siblings by 40ms.
/// Renders immediately when the platform asks for reduced motion.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = 40 * index.clamp(0, 10);
    const run = 280;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: delay + run),
      curve: Interval(delay / (delay + run), 1, curve: Curves.easeOut),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
    );
  }
}
