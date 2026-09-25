import 'package:flutter/material.dart';

import '../api_client.dart';
import '../main.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Shown briefly on launch while we check for a stored, still-valid session
/// token — sends the cleaner straight to HomeScreen if they're already
/// logged in, or to LoginScreen otherwise.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    Cleaner? cleaner;
    try {
      cleaner = await _api.me();
    } catch (_) {
      // e.g. server unreachable on launch — fall back to the login screen
      // rather than getting stuck here; login will surface the real error.
      cleaner = null;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => cleaner != null ? HomeScreen(cleaner: cleaner!) : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kBrandPrimaryLight, kBrandPrimary],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Spotless Cleaner',
                style: TextStyle(color: Colors.white, fontSize: 24, fontFamily: kFontHeading, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
