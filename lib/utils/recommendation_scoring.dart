/// Pure scoring core for [RecommendationService], pulled out into its own
/// file (same reason as [scoreFit] living in fit_scoring.dart) so the
/// actual match-score algorithm can be unit tested directly, without
/// spinning up Firestore/FirebaseAuth just to exercise arithmetic.
///
/// [RecommendationService] is the only caller — it supplies watchId/data
/// bookkeeping and builds the final [WatchRecommendation] from
/// [ScoringResult] below; every actual scoring decision lives here.
library;

import 'dart:math' show sqrt;

import '../constants/watch_colors.dart';
import 'fit_scoring.dart';

// Base weights, out of 1.0, when all three signals are available. Fit is
// weighted highest since it's the one hard physical constraint (an
// ill-fitting watch is a worse recommendation than an off-style or
// off-color one). Color is weighted lightest since it comes from a single
// outfit scan — one snapshot of what the user happened to wear once — so
// it's a noisier signal than style, which is an explicit, stated
// preference.
const double fitWeight = 0.55;
const double colorWeight = 0.15;
const double styleWeight = 0.30;

// Euclidean distance between pure black and pure white in RGB space — the
// maximum possible distance between two colors, used to normalize color
// distance into a 0.0–1.0 similarity score.
const double maxRgbDistance = 441.67; // sqrt(255^2 * 3)

// Color-match thresholds for when a colorNote is worth surfacing at all —
// left null for middling matches so the UI isn't cluttered with a note
// for every watch.
const double _colorNoteGoodThreshold = 0.65;
const double _colorNoteBadThreshold = 0.3;

/// The three raw signals plus the blended result for one watch scored
/// against one profile. [RecommendationService] wraps this in a
/// [WatchRecommendation] alongside the watch's id/data.
class ScoringResult {
  /// 0.0–1.0, or null if the user hasn't saved a wrist measurement, or the
  /// watch has no lugToLugMm on file, so fit can't be evaluated.
  final double? fitScore;

  /// 0.0–1.0, or null if the user hasn't set any style preferences.
  final double? styleScore;

  /// 0.0–1.0, or null if the user hasn't scanned an outfit yet, or the
  /// watch has no color on file, so color can't be evaluated.
  final double? colorScore;

  /// 0.0–1.0. Combines whichever of [fitScore]/[styleScore]/[colorScore]
  /// are available, re-weighted so missing signals don't drag the score
  /// down unfairly. Defaults to 0.5 (a neutral, neither-good-nor-bad
  /// score) if every signal is missing.
  final double combinedScore;

  final String fitNote;

  /// Set only when the color match is notably good or notably poor.
  final String? colorNote;

  const ScoringResult({
    required this.fitScore,
    required this.styleScore,
    required this.colorScore,
    required this.combinedScore,
    required this.fitNote,
    required this.colorNote,
  });
}

/// Scores a single watch's [watchData] against a customer profile.
///
/// Mirrors exactly what [RecommendationService]'s private `_score` used to
/// do inline — see that class's doc comment for the FR-09 rationale
/// (fit/color/style blend, missing-signal re-normalization, budget kept
/// as a separate hard affordability check rather than part of the score).
ScoringResult scoreWatchAgainstProfile({
  required Map<String, dynamic> watchData,
  required double? wristWidthMm,
  required List<String> stylePreferences,
  required List<Map<String, dynamic>> outfitColors,
}) {
  final lugToLugMm = (watchData['lugToLugMm'] as num?)?.toDouble();
  final styleCategory = watchData['styleCategory'] as String?;
  final colorHex = watchData['colorHex'] as String?;
  // Watches saved before multi-color support only have a single
  // `colorHex` — fall back to that as a 1-color list so the blended
  // scoring below still works unchanged for them.
  final colorHexesRaw = (watchData['colorHexes'] as List?)?.cast<String>();
  final colorHexes = (colorHexesRaw != null && colorHexesRaw.isNotEmpty)
      ? colorHexesRaw
      : (colorHex != null ? [colorHex] : const <String>[]);

  double? fitScore;
  String fitNote;
  if (wristWidthMm == null) {
    fitNote = 'Add your wrist measurement for fit-based ranking';
  } else if (lugToLugMm == null) {
    fitNote = 'Fit info unavailable for this watch';
  } else {
    final fit = scoreFit(wristWidthMm: wristWidthMm, lugToLugMm: lugToLugMm);
    fitScore = fit.score;
    fitNote = fit.note;
  }

  double? styleScore;
  if (stylePreferences.isNotEmpty && styleCategory != null) {
    styleScore = stylePreferences
            .any((s) => s.toLowerCase() == styleCategory.toLowerCase())
        ? 1.0
        : 0.0;
  }

  double? colorScore;
  String? colorNote;
  if (outfitColors.isNotEmpty && colorHexes.isNotEmpty) {
    // Blend each of the watch's colors' own outfit-match score, weighted
    // by that color's prominence (colorProminenceWeights — primary counts
    // fully, later colors count for less). For a single-color watch this
    // collapses to exactly the old formula: one color at weight 1.0,
    // nothing else to blend.
    double weightedSum = 0;
    double weightTotal = 0;
    for (var i = 0; i < colorHexes.length; i++) {
      final prominence = i < colorProminenceWeights.length
          ? colorProminenceWeights[i]
          : colorProminenceWeights.last;
      final (watchR, watchG, watchB) = hexToRgb(colorHexes[i]);

      double weightedSimilarity = 0;
      double outfitWeightTotal = 0;
      for (final entry in outfitColors) {
        final hex = entry['hex'] as String?;
        final percentage = (entry['percentage'] as num?)?.toDouble();
        if (hex == null || percentage == null || percentage <= 0) continue;

        final (r, g, b) = hexToRgb(hex);
        final dr = (watchR - r).toDouble();
        final dg = (watchG - g).toDouble();
        final db = (watchB - b).toDouble();
        final distance = sqrt(dr * dr + dg * dg + db * db);
        final similarity = (1 - distance / maxRgbDistance).clamp(0.0, 1.0);

        weightedSimilarity += similarity * percentage;
        outfitWeightTotal += percentage;
      }

      if (outfitWeightTotal > 0) {
        final perColorSimilarity = weightedSimilarity / outfitWeightTotal;
        weightedSum += perColorSimilarity * prominence;
        weightTotal += prominence;
      }
    }
    if (weightTotal > 0) {
      colorScore = weightedSum / weightTotal;
      if (colorScore >= _colorNoteGoodThreshold) {
        colorNote = 'Matches your outfit colors';
      } else if (colorScore <= _colorNoteBadThreshold) {
        colorNote = "Doesn't match your outfit colors";
      }
    }
  }

  // Weighted average over whichever signals are actually available,
  // re-normalized so a missing signal doesn't just get treated as a zero
  // (which would unfairly tank every score while a user's
  // wrist/style/outfit data is still incomplete).
  double weightedSum = 0;
  double totalWeight = 0;
  if (fitScore != null) {
    weightedSum += fitScore * fitWeight;
    totalWeight += fitWeight;
  }
  if (colorScore != null) {
    weightedSum += colorScore * colorWeight;
    totalWeight += colorWeight;
  }
  if (styleScore != null) {
    weightedSum += styleScore * styleWeight;
    totalWeight += styleWeight;
  }
  final combinedScore = totalWeight == 0 ? 0.5 : weightedSum / totalWeight;

  return ScoringResult(
    fitScore: fitScore,
    styleScore: styleScore,
    colorScore: colorScore,
    combinedScore: combinedScore,
    fitNote: fitNote,
    colorNote: colorNote,
  );
}