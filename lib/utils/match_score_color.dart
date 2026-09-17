import 'package:flutter/material.dart';

/// Score thresholds for the 5-tier match scale. Shared by [matchScoreColor]
/// (the UI badge) and the chat-assistant verdict helpers below
/// ([matchVerdictLabel], [matchVerdictGuidance]) so the badge color a
/// customer sees on screen and the tone the AI uses to talk about that same
/// watch never disagree — a watch badged red/orange should never get
/// talked up by the chatbot as a good pick.
const int greatMatchThreshold = 80;
const int goodMatchThreshold = 60;
const int fairMatchThreshold = 40;
const int weakMatchThreshold = 20;

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
  if (matchPercent >= greatMatchThreshold) return const Color(0xFF4CD964); // green
  if (matchPercent >= goodMatchThreshold) return const Color(0xFF9BE564); // yellow-green
  if (matchPercent >= fairMatchThreshold) return const Color(0xFFE5C84C); // yellow
  if (matchPercent >= weakMatchThreshold) return const Color(0xFFE5924C); // orange
  return const Color(0xFFE5544C); // red
}

/// Short label for a match percentage, using the exact same bands as
/// [matchScoreColor] — e.g. a watch labeled "Poor match" here is the same
/// watch showing a red badge on screen. Used in the chat assistant's
/// system prompt so it has a plain-language verdict for each watch instead
/// of just a bare number it might otherwise talk up regardless of score.
String matchVerdictLabel(int matchPercent) {
  if (matchPercent >= greatMatchThreshold) return 'Great match';
  if (matchPercent >= goodMatchThreshold) return 'Good match';
  if (matchPercent >= fairMatchThreshold) return 'Fair match';
  if (matchPercent >= weakMatchThreshold) return 'Weak match';
  return 'Poor match';
}

/// Tells the chat assistant how honestly/critically to talk about a SINGLE
/// watch at this match percentage. A match score alone doesn't tell a
/// language model whether that number is actually good, so without this a
/// low score (e.g. 17%) could still get talked up as "good for you" — this
/// makes the required tone explicit and non-negotiable per band.
String matchVerdictGuidance(int matchPercent) {
  final label = matchVerdictLabel(matchPercent);
  if (matchPercent >= greatMatchThreshold) {
    return '$label ($matchPercent%) — recommend it confidently.';
  } else if (matchPercent >= goodMatchThreshold) {
    return '$label ($matchPercent%) — recommend it, but mention whatever '
        'is holding it back from a great match.';
  } else if (matchPercent >= fairMatchThreshold) {
    return '$label ($matchPercent%) — do not call this a good pick '
        'outright. Be upfront that it only partially suits the customer '
        'and name the weak signal(s) (fit, color, or style).';
  } else if (matchPercent >= weakMatchThreshold) {
    return '$label ($matchPercent%) — this is a poor match. Say so '
        'plainly and explain what is dragging the score down instead of '
        'softening it into a recommendation.';
  } else {
    return '$label ($matchPercent%) — do NOT tell the customer this would '
        'be good for them. State plainly that it is a poor match for '
        'their profile, explain why (fit/color/style), and suggest they '
        'look at higher-scoring options instead.';
  }
}