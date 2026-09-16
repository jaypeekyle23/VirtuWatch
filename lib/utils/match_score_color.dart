import 'package:flutter/material.dart';

/// Maps a recommendation match percentage (0–100) to the color used for
/// its badge, on a 5-tier scale from red (poor match) to green (strong
/// match). Shared by the recommendations list and the watch detail
/// screen's match card so the two stay visually consistent.
///
/// Uses a custom palette (rather than Material's greenAccent/yellowAccent/
/// etc.) because those swatches vary wildly in saturation and brightness —
/// yellowAccent in particular is near-neon and would visually outshine the
/// "best match" green tier. These five colors share consistent saturation
/// and brightness so the scale reads as a smooth gradient.
Color matchScoreColor(int matchPercent) {
  if (matchPercent >= 80) return const Color(0xFF4CD964); // green
  if (matchPercent >= 60) return const Color(0xFF9BE564); // yellow-green
  if (matchPercent >= 40) return const Color(0xFFE5C84C); // yellow
  if (matchPercent >= 20) return const Color(0xFFE5924C); // orange
  return const Color(0xFFE5544C); // red
}