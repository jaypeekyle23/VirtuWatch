/// Single source of truth for "does this watch fit this wrist" — used by
/// both [RecommendationService] (to rank/label watches in the catalog)
/// and [ChatService] (so the AI's fit answers always agree with what the
/// rest of the app already told the user).
library;

/// How many mm of lug-to-lug vs wrist-width difference is treated as the
/// edge of "still fits reasonably" before the fit score hits zero.
const double fitToleranceMm = 15;

class FitResult {
  /// 0.0-1.0.
  final double score;
  final String note;

  const FitResult({required this.score, required this.note});
}

/// Scores how well a watch with [lugToLugMm] fits a [wristWidthMm] wrist.
/// Mirrors the exact rule used across the app: lug-to-lug within 3mm of
/// wrist width is a great fit; a larger lug-to-lug runs large; a smaller
/// one runs small.
FitResult scoreFit({
  required double wristWidthMm,
  required double lugToLugMm,
}) {
  final diff = lugToLugMm - wristWidthMm;
  final score = (1 - (diff.abs() / fitToleranceMm)).clamp(0.0, 1.0);

  final String note;
  if (diff.abs() <= 3) {
    note = 'Great fit for your ${wristWidthMm.toStringAsFixed(0)}mm wrist';
  } else if (diff > 0) {
    note = 'Runs a bit large for your ${wristWidthMm.toStringAsFixed(0)}mm wrist';
  } else {
    note = 'Runs a bit small for your ${wristWidthMm.toStringAsFixed(0)}mm wrist';
  }
  return FitResult(score: score, note: note);
}