import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';
import 'screens/splash_screen.dart';
import 'theme/spotless_theme.dart';

/// Legacy brand constants, still read by screens not yet redesigned.
/// TODO(redesign): delete once every screen reads the theme (SpotlessTheme).
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
  // anonKey is deprecated in favour of publishableKey, which expects the newer
  // `sb_publishable_...` key format — this project still issues a legacy anon
  // JWT (same as the customer app). Switch both apps over together.
  // ignore: deprecated_member_use
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  runApp(const SpotlessCleanerApp());
}

class SpotlessCleanerApp extends StatelessWidget {
  const SpotlessCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotless Cleaner',
      debugShowCheckedModeBanner: false,
      theme: SpotlessTheme.light(),
      home: const SplashScreen(),
    );
  }
}
