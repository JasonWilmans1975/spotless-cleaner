// Spotless Solutions — shared theme for the Customer and Cleaner apps.
//
// Colours come straight from the website's CSS variables (localhost:3000 :root).
// The knobs in [SpotlessThemeConfig] mirror the "Tweaks" panel on the design
// canvas (primary, accent, surface, hero style, heading font, body font,
// corner radius), so whatever you settle on there can be set here 1:1.
//
// Fonts are bundled as assets (pubspec.yaml `fonts:`), not fetched through
// google_fonts, so the app renders correctly offline.
//
// Usage:
//   MaterialApp(theme: SpotlessTheme.light(), ...)
//   // or with tweaks:
//   MaterialApp(theme: SpotlessTheme.light(const SpotlessThemeConfig(
//     radius: 16, heroStyle: HeroStyle.primary)))
//
//   // extra tokens (hero card, status pills):
//   final s = Theme.of(context).extension<SpotlessTokens>()!;
//   Container(color: s.heroBg, ...)

import 'package:flutter/material.dart';

/// Raw brand palette — identical to the website.
abstract final class SpotlessColors {
  static const acc = Color(0xFF4A5D8F); // --acc   (slate blue, primary)
  static const acc2 = Color(0xFFB8607A); // --acc2  (rose, accent)
  static const ink = Color(0xFF26201A); // --ink
  static const inkSoft = Color(0xFF4D4437); // --ink-soft
  static const muted = Color(0xFF6B6254); // --muted
  static const muted2 = Color(0xFF8A8071); // --muted-2 (large text only)
  static const line = Color(0xFFE8E1D3); // --line
  static const lineSoft = Color(0xFFEFEADD); // --line-soft
  static const bg = Color(0xFFFAF7F1); // --bg
  static const bgDot = Color(0xFFECE7DD); // --bg-dot
  static const blush = Color(0xFFF4EAE6); // "tint" section (reviews)
  static const card = Colors.white; // --card

  // Status colours used by the existing apps.
  static const gold = Color(0xFF7D5F17); // awaiting confirmation
  static const goldSoft = Color(0xFFF5EAD6);
  static const green = Color(0xFF3F7A4F); // approved / accepted
  static const greenSoft = Color(0xFFE3EFE4);
  static const red = Color(0xFFA33B3B); // destructive
  static const redSoft = Color(0xFFF6E3E1);
}

enum HeroStyle { ink, primary, blush }

/// Mirrors the canvas Tweaks. Only pick colours from [SpotlessColors].
class SpotlessThemeConfig {
  const SpotlessThemeConfig({
    this.primary = SpotlessColors.acc,
    this.accent = SpotlessColors.acc2,
    this.surface = SpotlessColors.bg,
    this.heroStyle = HeroStyle.ink,
    this.headingFont = 'SpaceGrotesk',
    this.bodyFont = 'PublicSans',
    this.radius = 22,
  });

  final Color primary;
  final Color accent;
  final Color surface;
  final HeroStyle heroStyle;

  /// A font family declared in pubspec.yaml (bundled asset).
  final String headingFont;

  /// A font family declared in pubspec.yaml (bundled asset).
  final String bodyFont;

  /// Card radius. Small = radius * .55, chips/inputs = radius * .75, hero = radius + 8.
  final double radius;
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Extra tokens the Material ColorScheme has no slot for.
@immutable
class SpotlessTokens extends ThemeExtension<SpotlessTokens> {
  const SpotlessTokens({
    required this.primarySoft,
    required this.primarySofter,
    required this.primaryDeep,
    required this.accentSoft,
    required this.accentDeep,
    required this.heroBg,
    required this.heroInk,
    required this.heroMuted,
    required this.heroChip,
    required this.heroLine,
    required this.heroAccent,
    required this.gold,
    required this.goldSoft,
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.line,
    required this.lineSoft,
    required this.muted,
    required this.radius,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.cardShadow,
    required this.buttonShadow,
    required this.headingFont,
  });

  final Color primarySoft, primarySofter, primaryDeep, accentSoft, accentDeep;
  final Color heroBg, heroInk, heroMuted, heroChip, heroLine, heroAccent;
  final Color gold, goldSoft, green, greenSoft, red, redSoft;
  final Color line, lineSoft, muted;
  final double radius, radiusSm, radiusMd, radiusLg;
  final List<BoxShadow> cardShadow, buttonShadow;
  final String headingFont;

  /// Heading text in the brand display face.
  TextStyle heading(double size, {Color? color, FontWeight weight = FontWeight.w700}) =>
      TextStyle(fontFamily: headingFont, fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.02 * size, height: 1.15);

  /// Status pill colours: (background, foreground).
  (Color, Color) get awaiting => (goldSoft, gold);
  (Color, Color) get confirmed => (primarySoft, primaryDeep);
  (Color, Color) get approved => (greenSoft, green);
  (Color, Color) get cancelled => (redSoft, red);

  /// Pill colours for a `bookings.status` value.
  (Color, Color) statusColors(String status) => switch (status) {
        'confirmed' => confirmed,
        'completed' => approved,
        'cancelled' => cancelled,
        _ => awaiting,
      };

  @override
  SpotlessTokens copyWith() => this;

  @override
  SpotlessTokens lerp(ThemeExtension<SpotlessTokens>? other, double t) => this;
}

abstract final class SpotlessTheme {
  static ThemeData light([SpotlessThemeConfig c = const SpotlessThemeConfig()]) {
    final p = c.primary, a = c.accent, s = c.surface;
    final r = c.radius, rSm = (r * .55).clamp(6, 40).toDouble(), rMd = (r * .75).clamp(8, 40).toDouble(), rLg = r + 8;

    final light = c.heroStyle == HeroStyle.blush;
    final heroBg = switch (c.heroStyle) {
      HeroStyle.ink => SpotlessColors.ink,
      HeroStyle.primary => p,
      HeroStyle.blush => SpotlessColors.blush,
    };

    final tokens = SpotlessTokens(
      primarySoft: _mix(p, Colors.white, .87),
      primarySofter: _mix(p, Colors.white, .94),
      primaryDeep: _mix(p, Colors.black, .22),
      accentSoft: _mix(a, Colors.white, .87),
      accentDeep: _mix(a, Colors.black, .20),
      heroBg: heroBg,
      heroInk: light ? SpotlessColors.ink : Colors.white,
      heroMuted: light ? SpotlessColors.muted : Colors.white.withValues(alpha: .72),
      heroChip: light ? Colors.white : Colors.white.withValues(alpha: .12),
      heroLine: light ? SpotlessColors.line : Colors.white.withValues(alpha: .16),
      heroAccent: switch (c.heroStyle) {
        HeroStyle.ink => _mix(p, Colors.white, .5),
        HeroStyle.primary => Colors.white,
        HeroStyle.blush => p,
      },
      gold: SpotlessColors.gold,
      goldSoft: SpotlessColors.goldSoft,
      green: SpotlessColors.green,
      greenSoft: SpotlessColors.greenSoft,
      red: SpotlessColors.red,
      redSoft: SpotlessColors.redSoft,
      line: SpotlessColors.line,
      lineSoft: SpotlessColors.lineSoft,
      muted: SpotlessColors.muted,
      radius: r,
      radiusSm: rSm,
      radiusMd: rMd,
      radiusLg: rLg,
      cardShadow: const [
        BoxShadow(color: Color(0x0A3C301E), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x4D3C301E), blurRadius: 32, spreadRadius: -22, offset: Offset(0, 16)),
      ],
      buttonShadow: [BoxShadow(color: p.withValues(alpha: .45), blurRadius: 22, spreadRadius: -8, offset: const Offset(0, 10))],
      headingFont: c.headingFont,
    );

    final scheme = ColorScheme.fromSeed(seedColor: p, brightness: Brightness.light).copyWith(
      primary: p,
      onPrimary: Colors.white,
      primaryContainer: tokens.primarySoft,
      onPrimaryContainer: tokens.primaryDeep,
      secondary: a,
      onSecondary: Colors.white,
      secondaryContainer: tokens.accentSoft,
      onSecondaryContainer: tokens.accentDeep,
      tertiary: SpotlessColors.gold,
      tertiaryContainer: SpotlessColors.goldSoft,
      error: SpotlessColors.red,
      errorContainer: SpotlessColors.redSoft,
      surface: s,
      onSurface: SpotlessColors.ink,
      onSurfaceVariant: SpotlessColors.muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: SpotlessColors.lineSoft,
      outline: SpotlessColors.line,
      outlineVariant: SpotlessColors.lineSoft,
      inverseSurface: SpotlessColors.ink,
    );

    final body = Typography.material2021().black.apply(fontFamily: c.bodyFont, bodyColor: SpotlessColors.ink, displayColor: SpotlessColors.ink);
    TextStyle h(double size) => TextStyle(fontFamily: c.headingFont,
        fontSize: size, fontWeight: FontWeight.w700, color: SpotlessColors.ink, letterSpacing: -0.02 * size, height: 1.15);
    final text = body.copyWith(
      displayLarge: h(40),
      displayMedium: h(34),
      displaySmall: h(30),
      headlineLarge: h(27),
      headlineMedium: h(24),
      headlineSmall: h(21),
      titleLarge: h(20), // app bar titles
      titleMedium: h(17), // card titles
      titleSmall: h(15),
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 15.5, height: 1.5),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 14.5, height: 1.5),
      bodySmall: body.bodySmall?.copyWith(fontSize: 12.5, color: SpotlessColors.muted),
      labelLarge: body.labelLarge?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
      labelMedium: body.labelMedium?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
      labelSmall: body.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .4),
    );

    const pillShape = StadiumBorder();
    final btnText = text.labelLarge;

    return ThemeData(
      useMaterial3: true,
      fontFamily: c.bodyFont,
      colorScheme: scheme,
      scaffoldBackgroundColor: s,
      textTheme: text,
      extensions: [tokens],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: s,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SpotlessColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: const BorderSide(color: SpotlessColors.line)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: pillShape,
          textStyle: btnText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: pillShape,
          elevation: 0,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: SpotlessColors.ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: SpotlessColors.line),
          shape: pillShape,
          textStyle: btnText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p, textStyle: text.labelMedium),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          fixedSize: const Size(44, 44),
          backgroundColor: Colors.white,
          foregroundColor: SpotlessColors.ink,
          side: const BorderSide(color: SpotlessColors.line),
          shape: const CircleBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: text.bodyMedium?.copyWith(color: SpotlessColors.muted),
        labelStyle: text.labelMedium?.copyWith(color: SpotlessColors.inkSoft),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(rMd), borderSide: const BorderSide(color: SpotlessColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMd), borderSide: const BorderSide(color: SpotlessColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMd), borderSide: BorderSide(color: p, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMd), borderSide: const BorderSide(color: SpotlessColors.red)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: tokens.primarySoft,
        side: const BorderSide(color: SpotlessColors.line),
        shape: pillShape,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: SpotlessColors.lineSoft,
          selectedBackgroundColor: Colors.white,
          selectedForegroundColor: SpotlessColors.ink,
          foregroundColor: SpotlessColors.muted,
          side: BorderSide.none,
          shape: pillShape,
          textStyle: text.labelMedium,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.primarySoft,
        height: 72,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelSmall!.copyWith(
              color: states.contains(WidgetState.selected) ? p : SpotlessColors.muted,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            )),
        iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(color: states.contains(WidgetState.selected) ? p : SpotlessColors.muted, size: 22)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p,
        unselectedLabelColor: SpotlessColors.muted,
        indicatorColor: p,
        labelStyle: text.labelLarge,
        dividerColor: SpotlessColors.line,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p : SpotlessColors.line),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: SpotlessColors.line, width: 2),
        fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p : Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p : SpotlessColors.line),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p, linearTrackColor: SpotlessColors.lineSoft),
      dividerTheme: const DividerThemeData(color: SpotlessColors.lineSoft, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(rLg))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
        titleTextStyle: text.headlineSmall,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SpotlessColors.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: heroBg,
        headerForegroundColor: tokens.heroInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
    );
  }
}

/// Status pill used across both apps ("Confirmed", "Awaiting", "Approved cleaner").
class SpotlessPill extends StatelessWidget {
  const SpotlessPill(this.label, {super.key, required this.colors, this.icon});

  /// e.g. `Theme.of(context).extension<SpotlessTokens>()!.awaiting`
  final (Color, Color) colors;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
        // Loose flex in a shrink-wrapped row: ellipsises when squeezed, and is
        // still fine where the pill gets unbounded width (Wrap, FittedBox).
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

/// The "next clean" / earnings hero card container.
class SpotlessHeroCard extends StatelessWidget {
  const SpotlessHeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).extension<SpotlessTokens>()!;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias, // keeps decorative artwork inside the rounded corners
      decoration: BoxDecoration(
        color: s.heroBg,
        borderRadius: BorderRadius.circular(s.radiusLg),
        boxShadow: const [BoxShadow(color: Color(0x8C26201A), blurRadius: 40, spreadRadius: -28, offset: Offset(0, 24))],
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: s.heroInk), child: IconTheme.merge(data: IconThemeData(color: s.heroInk), child: child)),
    );
  }
}
