import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';

/// Same design language as the customer app, but with the palette led by teal
/// instead of orange — a deliberate, small visual difference so the two apps
/// are easy to tell apart at a glance (e.g. side-by-side on a phone while
/// testing), while still clearly being the same brand. Orange becomes the
/// secondary/accent color here instead of the primary.
const kBrandPrimary = Color(0xFF2FA88F); // teal — "cleaner" primary
const kBrandSecondary = Color(0xFFFF6A3D); // sunrise orange — accent
const kBrandInk = Color(0xFF2B2320); // warm near-black for text, not pure black
const kBrandBackground = Color(0xFFFFF8F2); // warm cream, not stark white

void main() {
  runApp(const SpotlessCleanerApp());
}

class SpotlessCleanerApp extends StatelessWidget {
  const SpotlessCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.light(
      primary: kBrandPrimary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD8F3EC),
      onPrimaryContainer: const Color(0xFF0B4239),
      secondary: kBrandSecondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFE1D1),
      onSecondaryContainer: const Color(0xFF7A2E0A),
      tertiary: const Color(0xFFFF4D82), // warm pink, used sparingly (matches the customer app's family)
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFFE0EC),
      onTertiaryContainer: const Color(0xFF7A1440),
      surface: Colors.white,
      onSurface: kBrandInk,
      error: const Color(0xFFD84438),
      onError: Colors.white,
    );

    final roundedField = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
    );
    final roundedFieldFocused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kBrandPrimary, width: 2),
    );

    return MaterialApp(
      title: 'Spotless Cleaner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: kBrandBackground,
        appBarTheme: AppBarTheme(
          backgroundColor: kBrandBackground,
          foregroundColor: kBrandInk,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kBrandInk),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4, color: kBrandInk),
          titleMedium: TextStyle(fontWeight: FontWeight.w700, color: kBrandInk),
          titleSmall: TextStyle(fontWeight: FontWeight.w700, color: kBrandInk),
        ),
        // NOTE: this project's Flutter SDK needs CardThemeData here (not the older
        // CardTheme) — same fix already applied in the customer app.
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kBrandPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kBrandInk,
            side: BorderSide(color: Colors.black.withOpacity(0.16)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kBrandSecondary,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.black.withOpacity(0.045),
          selectedColor: kBrandPrimary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: kBrandInk),
          shape: StadiumBorder(side: BorderSide(color: Colors.black.withOpacity(0.08))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: roundedField,
          enabledBorder: roundedField,
          focusedBorder: roundedFieldFocused,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kBrandSecondary,
          foregroundColor: Colors.white,
          extendedTextStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: kBrandPrimary,
          unselectedItemColor: Colors.grey.shade500,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
