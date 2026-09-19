/// Single source of truth for "does this watch fit this wrist" — used by
/// both [RecommendationService] (to rank/label watches in the catalog)
/// and [ChatService] (so the AI's fit answers always agree with what the
/// rest of the app already told the user).
///
/// THE MODEL: fit isn't about lug-to-lug matching wrist width 1:1 — it's
/// about lug-to-lug as a *proportion* of the wrist's flat width. This
/// mirrors how watch sizing guides actually reason about fit: a
/// well-proportioned "classic" fit sits with lug-to-lug at roughly
/// 75-95% of the wrist's flat width, not equal to it. A lug-to-lug that
/// *equals or exceeds* wrist width is what actually causes the lugs to
/// overhang the edge of the wrist — that's the real failure mode, not a
/// smaller lug-to-lug relative to the wrist.
library;

class FitResult {
  /// 0.0-1.0.
  final double score;
  final String note;

  const FitResult({required this.score, required this.note});
}

/// Ratio bands (lugToLugMm / wristWidthMm), calibrated against widely
/// cited watch-sizing guidance (e.g. "look for a lug-to-lug distance
/// that's about 75-95% of wrist width" — a rule of thumb repeated across
/// watch retailers and sizing tools):
///   < 0.60          watch reads small/dainty on this wrist
///   0.60 - 0.75     "snug", clean fit
///   0.75 - 0.95     the classic, well-proportioned sweet spot — full score
///   0.95 - 1.05     "bold" fit, fills the wrist with minimal overhang
///   1.05 - 1.20     lugs start to overhang the wrist edge
///   > 1.20          lugs clearly overhang
const double _smallCutoff = 0.60;
const double _classicMin = 0.75;
const double _classicMax = 0.95;
const double _boldMax = 1.05;
const double _overhangCutoff = 1.20;

// How far outside the classic band a ratio can drift before the score
// bottoms out at 0. Deliberately asymmetric: running small is just a
// look, while running large means the lugs are physically overhanging
// the wrist — sizing guides treat that as the harder failure, so there's
// less tolerance on that side.
const double _toleranceBelow = 0.35;
const double _toleranceAbove = 0.25;

/// Scores how well a watch with [lugToLugMm] fits a [wristWidthMm] wrist,
/// based on the lug-to-lug-to-wrist-width ratio rather than the raw
/// millimeter gap between them.
FitResult scoreFit({
  required double wristWidthMm,
  required double lugToLugMm,
}) {
  final ratio = lugToLugMm / wristWidthMm;
  final wrist = wristWidthMm.toStringAsFixed(0);

  final double score;
  if (ratio >= _classicMin && ratio <= _classicMax) {
    score = 1.0;
  } else if (ratio < _classicMin) {
    score = (1 - ((_classicMin - ratio) / _toleranceBelow)).clamp(0.0, 1.0);
  } else {
    score = (1 - ((ratio - _classicMax) / _toleranceAbove)).clamp(0.0, 1.0);
  }

  final String note;
  if (ratio < _smallCutoff) {
    note = 'Runs small on your ${wrist}mm wrist';
  } else if (ratio < _classicMin) {
    note = 'Snug, clean fit for your ${wrist}mm wrist';
  } else if (ratio <= _classicMax) {
    note = 'Great, well-proportioned fit for your ${wrist}mm wrist';
  } else if (ratio <= _boldMax) {
    note = 'Bold fit for your ${wrist}mm wrist — fills it with barely any overhang';
  } else if (ratio <= _overhangCutoff) {
    note = 'Runs a bit large for your ${wrist}mm wrist — slight lug overhang';
  } else {
    note = 'Runs too large for your ${wrist}mm wrist — the lugs will overhang';
  }

  return FitResult(score: score, note: note);
}