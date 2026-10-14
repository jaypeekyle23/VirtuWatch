import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_controller.dart';
import 'app_palette.dart';

/// App-wide colors and the Material theme.
///
/// The color names below keep working everywhere they are used, but they
/// now follow whichever look the user picked (Default, Dark or Light), so
/// they are getters and not fixed constants. That means they cannot be
/// used inside `const` widgets or `const` declarations.
class AppTheme {
  static AppPalette get _palette => ThemeController.instance.palette;

  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get gold => _palette.gold;
  static Color get goldFill => _palette.goldFill;
  static Color get onGold => _palette.onGold;
  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get hairline => _palette.hairline;
  static Color get outlineSoft => _palette.outlineSoft;
  static Color get outline => _palette.outline;
  static Color get outlineStrong => _palette.outlineStrong;
  static Color get skeletonBase => _palette.skeletonBase;
  static Color get skeletonHighlight => _palette.skeletonHighlight;

  /// Path of the logo image that suits the current look.
  static String get logoAsset => _palette.logoAsset;

  /// Serif display style for headings and key figures.
  static TextStyle serif({
    double size = 26,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) =>
      GoogleFonts.cormorantGaramond(
          fontSize: size, color: color ?? textPrimary, fontWeight: weight);

  static ThemeData get theme {
    final p = _palette;
    final isLight = p.brightness == Brightness.light;

    var baseTextTheme = GoogleFonts.soraTextTheme(
      ThemeData(brightness: p.brightness).textTheme,
    );
    // The dark looks already get light text by default. The light look
    // needs its dark text color applied explicitly.
    if (isLight) {
      baseTextTheme = baseTextTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      );
    }

    return ThemeData(
      brightness: p.brightness,
      scaffoldBackgroundColor: p.background,
      colorScheme: isLight
          ? ColorScheme.light(
              primary: p.gold,
              secondary: p.gold,
              surface: p.surface,
              onPrimary: p.onGold,
              onSurface: p.textPrimary,
            )
          : ColorScheme.dark(
              primary: p.gold,
              secondary: p.gold,
              surface: p.surface,
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        elevation: 0,
        foregroundColor: p.textPrimary,
      ),
      textTheme: baseTextTheme.copyWith(
        headlineMedium: GoogleFonts.sora(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        bodyMedium: GoogleFonts.sora(
          color: p.textSecondary,
          fontSize: 14,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: GoogleFonts.sora(color: p.textSecondary, fontSize: 14),
        labelStyle: GoogleFonts.sora(color: p.textSecondary, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.goldFill,
          foregroundColor: p.onGold,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.sora(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
