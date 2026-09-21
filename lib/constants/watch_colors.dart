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

/// Max number of colors a single watch can carry (e.g. case, dial, and
/// strap accents on a two/three-tone piece). Kept small and deliberate —
/// see [colorProminenceWeights] for why more colors isn't automatically
/// "better" for a watch's color-match score.
const int maxWatchColors = 3;

/// Implicit prominence weight for a watch's colors by list position —
/// index 0 (the merchant-chosen primary/dominant color) counts fully,
/// each color after it counts for less. Used by RecommendationService to
/// blend a multi-color watch's color-match score.
///
/// This is deliberately a strict generalization of the old single-color
/// model: a watch with just one color has nothing to blend, so its score
/// is exactly what it would have been before multi-color support
/// existed. A secondary or tertiary color can only ever nudge the score
/// toward the outfit, never dominate it — that keeps a merchant from
/// gaming the match score by tacking on a barely-visible accent color.
const List<double> colorProminenceWeights = [1.0, 0.6, 0.4];

/// Looks up a palette color's display name for [hex], if it's one of the
/// known [watchColorPalette] swatches. Returns null for a custom
/// (wheel-picked) color that isn't in the palette, so callers can fall
/// back to showing the raw hex instead.
String? paletteNameForHex(String hex) {
  for (final option in watchColorPalette) {
    if (option.hex.toUpperCase() == hex.toUpperCase()) return option.name;
  }
  return null;
}

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

/// Best-effort plain-language name for an arbitrary hex color, bucketed
/// by hue with a lightness/saturation adjustment (so a dark, muted red
/// reads as "burgundy" rather than a flat "red", a washed-out blue reads
/// as "muted blue" rather than overclaiming a bold shade, etc.).
///
/// Used as the fallback for a custom (wheel-picked) color that doesn't
/// match one of the fixed [watchColorPalette] swatches — without this,
/// the only "name" available for a custom color was its raw hex string
/// (e.g. '#6F1011'), which is meaningless read out loud in a chat
/// conversation. This is deliberately approximate — a human-readable
/// descriptor for conversation, not a precise color-science classifier.
String describeHexColor(String hex) {
  final (r, g, b) = hexToRgb(hex);
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final maxC = [rf, gf, bf].reduce((a, v) => a > v ? a : v);
  final minC = [rf, gf, bf].reduce((a, v) => a < v ? a : v);
  final lightness = (maxC + minC) / 2;
  final delta = maxC - minC;

  // Near-neutral: too little saturation for a hue name to mean anything.
  if (delta < 0.08) {
    if (lightness < 0.15) return 'black';
    if (lightness > 0.85) return 'white';
    if (lightness < 0.4) return 'dark gray';
    if (lightness > 0.65) return 'light gray';
    return 'gray';
  }

  final saturation = delta / (1 - (2 * lightness - 1).abs());

  double hue;
  if (maxC == rf) {
    hue = 60 * (((gf - bf) / delta) % 6);
  } else if (maxC == gf) {
    hue = 60 * (((bf - rf) / delta) + 2);
  } else {
    hue = 60 * (((rf - gf) / delta) + 4);
  }
  if (hue < 0) hue += 360;

  final String base;
  if (hue < 15 || hue >= 345) {
    base = 'red';
  } else if (hue < 45) {
    base = 'orange';
  } else if (hue < 65) {
    base = 'yellow';
  } else if (hue < 170) {
    base = 'green';
  } else if (hue < 200) {
    base = 'teal';
  } else if (hue < 255) {
    base = 'blue';
  } else if (hue < 290) {
    base = 'purple';
  } else {
    base = 'pink';
  }

  if (lightness < 0.25) {
    return base == 'red' ? 'burgundy' : 'dark $base';
  }
  if (lightness > 0.8 && saturation < 0.4) {
    return 'light $base';
  }
  if (saturation < 0.35) {
    return 'muted $base';
  }
  return base;
}