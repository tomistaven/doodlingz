import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  // Warm amber accent — active tool highlight, selected states, FAB.
  static const Color _accent = Color(0xFFE2B93B);
  static const Color _accentDark = Color(0xFFD4A373);

  // Dark chrome surfaces.
  static const Color _darkScaffold = Color(0xFF1A1A1A);
  static const Color _darkSurface = Color(0xFF242424);
  static const Color _darkSurfaceVariant = Color(0xFF2E2E2E);

  // Light chrome surfaces.
  static const Color _lightScaffold = Color(0xFFF5F5F5);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceVariant = Color(0xFFEEEEEE);

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    accent: _accent,
    scaffold: _darkScaffold,
    surface: _darkSurface,
    surfaceVariant: _darkSurfaceVariant,
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white70,
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    accent: _accentDark,
    scaffold: _lightScaffold,
    surface: _lightSurface,
    surfaceVariant: _lightSurfaceVariant,
    onSurface: Colors.black87,
    onSurfaceVariant: Colors.black54,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color accent,
    required Color scaffold,
    required Color surface,
    required Color surfaceVariant,
    required Color onSurface,
    required Color onSurfaceVariant,
  }) {
    final base = GoogleFonts.mansalvaTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
        secondary: accent,
        onSecondary: brightness == Brightness.dark
            ? Colors.black
            : Colors.white,
        error: const Color(0xFFCF6679),
        onError: Colors.white,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceVariant,
        onSurfaceVariant: onSurfaceVariant,
      ),
      scaffoldBackgroundColor: scaffold,
      textTheme: base,
      iconTheme: IconThemeData(color: onSurfaceVariant, size: 24),
      // Lacquer wordmark for app-bar titles; body text stays on Mansalva.
      // fontSize 22 is the tuning knob for the editor "Doodlingz" overflow.
      appBarTheme: AppBarThemeData(
        titleTextStyle: GoogleFonts.lacquer(fontSize: 22, color: onSurface),
      ),
      // CardThemeData constructor — avoids the Flutter 3.41 CardTheme type error.
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Colors.transparent,
        // Active icon uses accent; inactive uses muted onSurface.
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent, size: 26);
          }
          return IconThemeData(color: onSurfaceVariant, size: 24);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: surfaceVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}