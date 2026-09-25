import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';
import 'screens/splash_screen.dart';

/// Brand palette — mirrors the website's design tokens in
/// spotless-cleaning/public/css/styles.css (:root) so the apps and site look
/// like one product. Change them there and here together.
const kBrandPrimary = Color(0xFF4A5D8F); // --acc (indigo)
const kBrandPrimaryLight = Color(0xFF6B7AA3); // --acc mixed 82% with white — .btn-primary gradient start
const kBrandSecondary = Color(0xFFB8607A); // --acc2 (rose)
const kBrandInk = Color(0xFF26201A); // --ink
const kBrandInkSoft = Color(0xFF4D4437); // --ink-soft
const kBrandMuted = Color(0xFF6B6254); // --muted
const kBrandMuted2 = Color(0xFF8A8071); // --muted-2
const kBrandLine = Color(0xFFE8E1D3); // --line
const kBrandBackground = Color(0xFFFAF7F1); // --bg

// Status pill colours (.badge-* / .status-pill on the site).
const kPendingBg = Color(0xFFF6ECD8);
const kPendingInk = Color(0xFF8A6A1F);
const kSuccessBg = Color(0xFFE3F0E6);
const kSuccessInk = Color(0xFF347A4A);
const kDangerBg = Color(0xFFF5E2E2);
const kDangerInk = Color(0xFFA3423C);

const kFontBody = 'PublicSans'; // --font-b
const kFontHeading = 'SpaceGrotesk'; // --font-h

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  runApp(const SpotlessCleanerApp());
}

class SpotlessCleanerApp extends StatelessWidget {
  const SpotlessCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.light(
      primary: kBrandPrimary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE4ECF3), // .badge-confirmed background
      onPrimaryContainer: kBrandPrimary,
      secondary: kBrandSecondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFF4E7E9), // --acc2 at ~10% on cream, as .section.tint
      onSecondaryContainer: const Color(0xFF7A3548),
      tertiary: kBrandInk,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: kBrandInk,
      onSurfaceVariant: kBrandMuted,
      outline: kBrandLine,
      outlineVariant: kBrandLine,
      error: kDangerInk,
      onError: Colors.white,
    );

    // Inputs: .field input — 12px radius, --line border, --acc focus ring.
    final roundedField = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBrandLine),
    );
    final roundedFieldFocused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBrandPrimary, width: 2),
    );
    // Headings use Space Grotesk with the site's -.01em tracking; body text Public Sans.
    const heading = TextStyle(fontFamily: kFontHeading, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: kBrandInk);
    // Buttons: .btn — pill shape, Public Sans 600.
    const buttonText = TextStyle(fontFamily: kFontBody, fontSize: 15, fontWeight: FontWeight.w600);
    const pill = StadiumBorder();

    return MaterialApp(
      title: 'Spotless Cleaner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        fontFamily: kFontBody,
        scaffoldBackgroundColor: kBrandBackground,
        dividerColor: kBrandLine,
        dividerTheme: const DividerThemeData(color: kBrandLine, space: 1),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white, // .site-header
          foregroundColor: kBrandInk,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          shape: const Border(bottom: BorderSide(color: kBrandLine)),
          titleTextStyle: heading.copyWith(fontSize: 19),
        ),
        textTheme: TextTheme(
          displaySmall: heading.copyWith(fontWeight: FontWeight.w700),
          headlineLarge: heading.copyWith(fontWeight: FontWeight.w700),
          headlineMedium: heading.copyWith(fontWeight: FontWeight.w700),
          headlineSmall: heading.copyWith(fontWeight: FontWeight.w700),
          titleLarge: heading,
          titleMedium: heading.copyWith(fontSize: 17),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600, color: kBrandInk),
          bodyLarge: const TextStyle(color: kBrandInk),
          bodyMedium: const TextStyle(color: kBrandInk),
          bodySmall: const TextStyle(color: kBrandMuted),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600),
        ),
        // .card — white, 1px --line border, 22px radius.
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            side: BorderSide(color: kBrandLine),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kBrandPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 26),
            shape: pill,
            textStyle: buttonText,
          ),
        ),
        // .btn-secondary — white pill with --line border.
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kBrandInk,
            backgroundColor: Colors.white,
            side: const BorderSide(color: kBrandLine),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: pill,
            textStyle: buttonText,
          ),
        ),
        // .btn-link — rose accent.
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kBrandSecondary,
            textStyle: buttonText.copyWith(fontSize: 14),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: kBrandPrimary,
          secondarySelectedColor: kBrandPrimary,
          labelStyle: TextStyle(fontWeight: FontWeight.w600, color: kBrandInk),
          secondaryLabelStyle: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
          shape: StadiumBorder(side: BorderSide(color: kBrandLine)),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: const TextStyle(color: kBrandInkSoft),
          hintStyle: const TextStyle(color: kBrandMuted2),
          helperStyle: const TextStyle(color: kBrandMuted2),
          errorStyle: const TextStyle(color: Color(0xFFB23B3B)), // .field-error
          border: roundedField,
          enabledBorder: roundedField,
          focusedBorder: roundedFieldFocused,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kBrandPrimary,
          foregroundColor: Colors.white,
          shape: StadiumBorder(),
          extendedTextStyle: TextStyle(fontFamily: kFontBody, fontWeight: FontWeight.w600),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: kBrandInk, // .toast
          behavior: SnackBarBehavior.floating,
          shape: StadiumBorder(),
          contentTextStyle: TextStyle(fontFamily: kFontBody, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: kBrandPrimary),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: kBrandPrimary,
          unselectedItemColor: kBrandMuted2,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
