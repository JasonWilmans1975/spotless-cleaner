import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';
import 'screens/splash_screen.dart';
import 'theme/spotless_theme.dart';

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
