import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/ui_constants.dart';
import '../../shell/app_shell.dart';

/// First screen shown on launch. Displays the app mark, wordmark, and a
/// loading indicator for a fixed duration before replacing itself with
/// [AppShell]. The delay is a deliberate branding pause, not a wait on real
/// initialisation — [initDependencies] in `main.dart` already completes
/// before this widget is built.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(UiConstants.splashDuration, _goToAppShell);
  }

  void _goToAppShell() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              Theme.of(context).brightness == Brightness.light
                  ? 'assets/icon/icon_foreground_dark.png'
                  : 'assets/icon/icon_foreground.png',
              width: UiConstants.splashIconSize,
              height: UiConstants.splashIconSize,
            ),
            const SizedBox(height: 24),
            Text(
              'Doodlingz',
              style: GoogleFonts.lacquer(
                fontSize: 28,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
