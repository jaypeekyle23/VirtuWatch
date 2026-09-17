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
/// wrist width is a great fit; the further past that (up to
/// [fitToleranceMm] and beyond), the more the wording escalates from "a
/// bit" to "quite" to "way too" — a 54mm mismatch and an 8mm mismatch are
/// both a bad fit, but they shouldn't read as the same "runs a bit small"
/// note.
FitResult scoreFit({
  required double wristWidthMm,
  required double lugToLugMm,
}) {
  final diff = lugToLugMm - wristWidthMm;
  final absDiff = diff.abs();
  final score = (1 - (absDiff / fitToleranceMm)).clamp(0.0, 1.0);
  final wrist = wristWidthMm.toStringAsFixed(0);
  final direction = diff > 0 ? 'large' : 'small';

  final String note;
  if (absDiff <= 3) {
    note = 'Great fit for your ${wrist}mm wrist';
  } else if (absDiff <= 8) {
    note = 'Runs a bit $direction for your ${wrist}mm wrist';
  } else if (absDiff <= fitToleranceMm) {
    note = 'Runs quite $direction for your ${wrist}mm wrist';
  } else {
    note = 'Way too $direction for your ${wrist}mm wrist';
  }
  return FitResult(score: score, note: note);
}