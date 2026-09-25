import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'ui/layout.dart';

/// The icon choices for a service. `services.icon` stores the [glyph] — a
/// plain text symbol the website already renders as-is — and the apps draw
/// the matching outline [icon]. Any other stored value (older services) is
/// shown as text.
typedef ServiceIconOption = ({String glyph, IconData icon, String label});

const List<ServiceIconOption> kServiceIcons = [
  (glyph: '⌂', icon: LucideIcons.house, label: 'Home'),
  (glyph: '✦', icon: LucideIcons.sparkle, label: 'Deep clean'),
  (glyph: '⇄', icon: LucideIcons.arrowLeftRight, label: 'Moving'),
  (glyph: '⌘', icon: LucideIcons.bedDouble, label: 'Holiday let'),
  (glyph: '♨', icon: LucideIcons.cookingPot, label: 'Kitchen'),
  (glyph: '▦', icon: LucideIcons.appWindow, label: 'Windows'),
];

/// The outline icon for a stored glyph, or null if it isn't one of ours.
IconData? iconForGlyph(String glyph) {
  for (final o in kServiceIcons) {
    if (o.glyph == glyph.trim()) return o.icon;
  }
  return null;
}

/// Rounded tile showing a service's icon — the outline icon when the stored
/// glyph is one of [kServiceIcons], otherwise the stored text itself.
class ServiceIconTile extends StatelessWidget {
  const ServiceIconTile(this.glyph, {super.key, this.size = 46, this.background, this.foreground});
  final String glyph;
  final double size;
  final Color? background, foreground;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final fg = foreground ?? context.colors.primary;
    final icon = iconForGlyph(glyph);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background ?? s.primarySoft, borderRadius: BorderRadius.circular(s.radiusSm)),
      child: icon != null
          ? Icon(icon, size: size * .46, color: fg)
          : Text(glyph.trim().isEmpty ? '✦' : glyph.trim(),
              style: TextStyle(fontSize: size * .4, color: fg, fontWeight: FontWeight.w600), maxLines: 1),
    );
  }
}
