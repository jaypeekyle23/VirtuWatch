import 'package:flutter/material.dart';

/// The three looks the user can choose from in the app.
enum AppThemeMode {
  /// The original navy look the app shipped with.
  defaultMode,

  /// A deeper, near-black version of the default look.
  dark,

  /// A light background with dark text.
  light;

  /// Name shown in the picker.
  String get label {
    switch (this) {
      case AppThemeMode.defaultMode:
        return 'Default';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.light:
        return 'Light';
    }
  }

  /// Short line shown under the name in the picker.
  String get description {
    switch (this) {
      case AppThemeMode.defaultMode:
        return 'The original navy look';
      case AppThemeMode.dark:
        return 'A deeper, darker background';
      case AppThemeMode.light:
        return 'A lighter background';
    }
  }

  /// Saved value. Stored by name so reordering the enum never changes
  /// what a saved choice means.
  String get storageValue => name;

  static AppThemeMode fromStorage(String? value) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return AppThemeMode.defaultMode;
  }

  AppPalette get palette {
    switch (this) {
      case AppThemeMode.defaultMode:
        return AppPalette.defaultPalette;
      case AppThemeMode.dark:
        return AppPalette.darkPalette;
      case AppThemeMode.light:
        return AppPalette.lightPalette;
    }
  }
}

/// One complete set of app colors. Each field matches a color that
/// already exists in [AppTheme], so screens can switch over without
/// changing names.
class AppPalette {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color gold;

  /// Fill for gold buttons. Brighter than [gold] in the light look, where
  /// [gold] has to be deep enough to read as small text and icons.
  final Color goldFill;

  /// Text and icons that sit on top of a [goldFill] button or badge.
  final Color onGold;
  final Color textPrimary;
  final Color textSecondary;
  final Color hairline;

  /// Borders and dividers: soft, normal and strong. These replace the
  /// fixed translucent whites the screens used before.
  final Color outlineSoft;
  final Color outline;
  final Color outlineStrong;

  /// Colors of the loading shimmer.
  final Color skeletonBase;
  final Color skeletonHighlight;

  /// Which logo image to show. The light look needs a version where the
  /// white lettering is dark.
  final String logoAsset;

  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.gold,
    required this.goldFill,
    required this.onGold,
    required this.textPrimary,
    required this.textSecondary,
    required this.hairline,
    required this.outlineSoft,
    required this.outline,
    required this.outlineStrong,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.logoAsset,
  });

  /// Exactly the colors the app uses today.
  static const defaultPalette = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0E1A2B),
    surface: Color(0xFF16263D),
    gold: Color(0xFFE8BF6A),
    goldFill: Color(0xFFE8BF6A),
    onGold: Color(0xFF0E1A2B),
    textPrimary: Color(0xFFF5F1E8),
    textSecondary: Color(0xFFA9B4C4),
    hairline: Color(0x1FFFFFFF),
    outlineSoft: Color(0x1FFFFFFF),
    outline: Color(0x3DFFFFFF),
    outlineStrong: Color(0x62FFFFFF),
    skeletonBase: Color(0xFF223A5C),
    skeletonHighlight: Color(0xFF35547E),
    logoAsset: 'assets/images/branding/logo.png',
  );

  /// Same accents and text as the default look, on a darker background.
  static const darkPalette = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF070B12),
    surface: Color(0xFF0F1620),
    gold: Color(0xFFE8BF6A),
    goldFill: Color(0xFFE8BF6A),
    onGold: Color(0xFF0E1A2B),
    textPrimary: Color(0xFFF5F1E8),
    textSecondary: Color(0xFFA9B4C4),
    hairline: Color(0x1FFFFFFF),
    outlineSoft: Color(0x1FFFFFFF),
    outline: Color(0x3DFFFFFF),
    outlineStrong: Color(0x62FFFFFF),
    skeletonBase: Color(0xFF1A2536),
    skeletonHighlight: Color(0xFF2A3A52),
    logoAsset: 'assets/images/branding/logo.png',
  );

  /// Light, cool background with dark navy text. The gold is deeper than
  /// in the dark looks so small gold text and icons stay readable, while
  /// gold buttons use a brighter fill with navy text on top.
  static const lightPalette = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    gold: Color(0xFFAD7D0F),
    goldFill: Color(0xFFD9A93A),
    onGold: Color(0xFF0E1A2B),
    textPrimary: Color(0xFF0E1A2B),
    textSecondary: Color(0xFF566175),
    hairline: Color(0x1F0E1A2B),
    outlineSoft: Color(0x1A0E1A2B),
    outline: Color(0x380E1A2B),
    outlineStrong: Color(0x610E1A2B),
    skeletonBase: Color(0xFFE3E7EE),
    skeletonHighlight: Color(0xFFF1F3F7),
    logoAsset: 'assets/images/branding/logo_light.png',
  );
}
