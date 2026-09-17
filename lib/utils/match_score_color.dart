import 'package:flutter/material.dart';

/// Score thresholds for the 5-tier match scale. Shared by every helper in
/// this file so the badge color a customer sees on screen and the tone
/// the AI uses to talk about that same watch never disagree — a watch
/// badged red/orange should never get talked up by the chatbot as a good
/// pick.
const int greatMatchThreshold = 80;
const int goodMatchThreshold = 60;
const int fairMatchThreshold = 40;
const int weakMatchThreshold = 20;

/// The 5 tiers, worst to best, as a single ordered list — index doubles
/// as a comparable "how good" rank so capping (see [_cappedTierIndex]) is
/// just a min() over indices instead of re-deriving bands per helper.
const List<String> _tierLabels = [
  'Poor match',
  'Weak match',
  'Fair match',
  'Good match',
  'Great match',
];

const List<Color> _tierColors = [
  Color(0xFFE5544C), // red
  Color(0xFFE5924C), // orange
  Color(0xFFE5C84C), // yellow
  Color(0xFF9BE564), // yellow-green
  Color(0xFF4CD964), // green
];

/// Which of the 5 tiers a raw percentage falls into, ignoring confidence.
int _rawTierIndex(int matchPercent) {
  if (matchPercent >= greatMatchThreshold) return 4;
  if (matchPercent >= goodMatchThreshold) return 3;
  if (matchPercent >= fairMatchThreshold) return 2;
  if (matchPercent >= weakMatchThreshold) return 1;
  return 0;
}

/// The tier to actually show, after capping for low confidence. A score
/// built from only 1 or 2 signals (see [WatchRecommendation.signalCount])
/// is a much weaker claim than the same percentage built from all three —
/// without this, a watch scored on style alone could still show "Great
/// match" in bold green, which overstates how much the app actually knows.
/// [signalCount] defaults to 3 (full confidence, no cap) for call sites
/// that don't have a [WatchRecommendation] on hand.
int _cappedTierIndex(int matchPercent, int signalCount) {
  final raw = _rawTierIndex(matchPercent);
  if (signalCount >= 3) return raw;
  final cap = signalCount == 2 ? 3 : 2; // 2 signals -> max "Good"; ≤1 -> max "Fair"
  return raw < cap ? raw : cap;
}

/// Maps a recommendation match percentage (0–100) to the color used for
/// its badge, on a 5-tier scale from red (poor match) to green (strong
/// match), capped by [signalCount] as described on [_cappedTierIndex].
/// Shared by the recommendations list and the watch detail screen's
/// match card so the two stay visually consistent.
///
/// Uses a custom palette (rather than Material's greenAccent/yellowAccent/
/// etc.) because those swatches vary wildly in saturation and brightness —
/// yellowAccent in particular is near-neon and would visually outshine the
/// "best match" green tier. These five colors share consistent saturation
/// and brightness so the scale reads as a smooth gradient.
Color matchScoreColor(int matchPercent, {int signalCount = 3}) {
  return _tierColors[_cappedTierIndex(matchPercent, signalCount)];
}

/// Short label for a match percentage, capped by [signalCount] as
/// described on [_cappedTierIndex] — e.g. a watch labeled "Poor match"
/// here is the same watch showing a red badge on screen. Used in the chat
/// assistant's system prompt so it has a plain-language verdict for each
/// watch instead of just a bare number it might otherwise talk up
/// regardless of score or confidence.
String matchVerdictLabel(int matchPercent, {int signalCount = 3}) {
  return _tierLabels[_cappedTierIndex(matchPercent, signalCount)];
}

/// Tells the chat assistant how honestly/critically to talk about a SINGLE
/// watch at this match percentage. A match score alone doesn't tell a
/// language model whether that number is actually good, so without this a
/// low score (e.g. 17%) could still get talked up as "good for you" — this
/// makes the required tone explicit and non-negotiable per band. Also
/// capped by [signalCount], so a high score built on one shaky signal
/// doesn't get the same confident "recommend it" instruction as one built
/// on all three.
String matchVerdictGuidance(int matchPercent, {int signalCount = 3}) {
  final tier = _cappedTierIndex(matchPercent, signalCount);
  final label = _tierLabels[tier];
  final wasCapped = tier < _rawTierIndex(matchPercent);
  final capNote = wasCapped
      ? ' (treat it as this lower tier, not the raw number, since it\'s '
          'based on only $signalCount signal${signalCount == 1 ? '' : 's'})'
      : '';

  switch (tier) {
    case 4:
      return '$label ($matchPercent%)$capNote — recommend it confidently.';
    case 3:
      return '$label ($matchPercent%)$capNote — recommend it, but mention '
          'whatever is holding it back from a great match.';
    case 2:
      return '$label ($matchPercent%)$capNote — do not call this a good '
          'pick outright. Be upfront that it only partially suits the '
          'customer and name the weak signal(s) (fit, color, or style).';
    case 1:
      return '$label ($matchPercent%)$capNote — this is a poor match. Say '
          'so plainly and explain what is dragging the score down instead '
          'of softening it into a recommendation.';
    default:
      return '$label ($matchPercent%)$capNote — do NOT tell the customer '
          'this would be good for them. State plainly that it is a poor '
          'match for their profile, explain why (fit/color/style), and '
          'suggest they look at higher-scoring options instead.';
  }
}