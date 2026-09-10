import 'package:flutter/material.dart';

/// A single selectable watch color: a merchant-facing [name] plus the
/// [hex] value used both to render the swatch and to score against a
/// user's scanned outfit colors in the recommendation engine.
class WatchColorOption {
  final String name;
  final String hex;

  const WatchColorOption(this.name, this.hex);
}

/// Fixed palette merchants pick a watch's primary color from. Kept as a
/// closed set (rather than a free-form color picker) so every watch's
/// color is one of a small number of known, comparable hex values —
/// simpler for merchants, and it keeps the color-matching math in
/// RecommendationService meaningful (comparing against a handful of
/// intentional swatches, not arbitrary noise).
const List<WatchColorOption> watchColorPalette = [
  WatchColorOption('Silver', '#C0C0C0'),
  WatchColorOption('Black', '#1A1A1A'),
  WatchColorOption('Gold', '#D4AF37'),
  WatchColorOption('Rose Gold', '#B76E79'),
  WatchColorOption('Brown', '#6F4E37'),
  WatchColorOption('Navy Blue', '#1F3A5F'),
  WatchColorOption('Green', '#2E4D3A'),
  WatchColorOption('White', '#F5F5F5'),
];

/// Parses a '#RRGGBB' string into a [Color]. Falls back to mid-gray if
/// the string is malformed, so a bad value never crashes a build.
Color hexToColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse('FF$cleaned', radix: 16);
  return value != null ? Color(value) : const Color(0xFF808080);
}

/// Extracts (r, g, b) as 0–255 ints from a '#RRGGBB' string. Returns
/// mid-gray if the string is malformed.
(int, int, int) hexToRgb(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  if (cleaned.length != 6) return (128, 128, 128);
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return (128, 128, 128);
  return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

/// Finds the palette color closest to an arbitrary [Color] by Euclidean
/// RGB distance. Used to snap a photo-extracted color (which can be any
/// RGB value) onto one of the known [watchColorPalette] swatches, since
/// the recommendation engine's color matching assumes every watch's
/// color is one of that closed set.
WatchColorOption nearestPaletteColor(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();

  WatchColorOption closest = watchColorPalette.first;
  double closestDistanceSquared = double.infinity;
  for (final option in watchColorPalette) {
    final (or_, og, ob) = hexToRgb(option.hex);
    final dr = r - or_;
    final dg = g - og;
    final db = b - ob;
    final distanceSquared = (dr * dr + dg * dg + db * db).toDouble();
    if (distanceSquared < closestDistanceSquared) {
      closestDistanceSquared = distanceSquared;
      closest = option;
    }
  }
  return closest;
}