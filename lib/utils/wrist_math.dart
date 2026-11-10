/// Pure math behind screen calibration and on-screen wrist measurement, kept
/// out of the screens so it can be unit tested against known reference
/// objects.
library;

/// Plausible adult wrist width range in millimeters. Mirrors the manual entry
/// validation range, and bounds the step control and the default guess.
const double minPlausibleWristMm = 30;
const double maxPlausibleWristMm = 120;

/// ISO/IEC 7810 ID-1 card, short edge, in millimeters.
const double cardReferenceMm = 53.98;

/// PHP 20 coin diameter in millimeters.
const double php20CoinReferenceMm = 30.0;

/// Millimeters per logical pixel, from a real object of known size
/// ([referenceMm]) that the user lined up against [offsetPx] logical pixels
/// on screen. Throws [ArgumentError] if either value is not positive, since a
/// zero or negative ratio would silently corrupt every later measurement.
double mmPerPixelFromReference({
  required double referenceMm,
  required double offsetPx,
}) {
  if (referenceMm <= 0 || offsetPx <= 0) {
    throw ArgumentError('referenceMm and offsetPx must be greater than 0');
  }
  return referenceMm / offsetPx;
}

/// Converts an on-screen distance in logical pixels to millimeters.
double pxToMm(double px, double mmPerPixel) => px * mmPerPixel;

/// Converts millimeters to the on-screen distance in logical pixels.
double mmToPx(double mm, double mmPerPixel) => mm / mmPerPixel;

/// Whether [mm] is a believable adult wrist width (inclusive range).
bool isPlausibleWristMm(double mm) =>
    mm >= minPlausibleWristMm && mm <= maxPlausibleWristMm;
