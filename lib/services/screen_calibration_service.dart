import 'package:shared_preferences/shared_preferences.dart';

/// Stores this device's actual screen calibration — millimeters per
/// logical pixel — captured once by having the user hold a real ID/ATM/
/// credit card flush against the screen and adjust a guide until it
/// matches the card exactly.
///
/// WHY THIS EXISTS (documented here for the capstone writeup):
/// Flutter's `MediaQuery.devicePixelRatio` is the ratio between logical
/// and physical pixels — it says nothing about the screen's true physical
/// size, so it can't give an accurate mm-per-pixel value on its own.
/// Android's own reported density (`DisplayMetrics.xdpi`/`ydpi`) is meant
/// to answer that, but many OEMs — especially budget/mid-range Android
/// brands — don't report the true measured density; they often just round
/// to the nearest standard density bucket (mdpi/hdpi/xhdpi/...), which can
/// silently be off by 10-15%+ on a real device. iOS doesn't expose true
/// physical screen dimensions through public APIs at all.
///
/// The fix: measure the actual screen empirically, once, against a
/// known-size real-world object (a card, ISO/IEC 7810 ID-1: 53.98mm on
/// its short edge — the dimension used here since it fits within any
/// phone screen regardless of orientation). That one action reveals the
/// true pixel-to-mm ratio for this specific device directly, with no
/// trust placed in any reported device spec. Store it locally and reuse
/// it until the user recalibrates.
class ScreenCalibrationService {
  static const String _mmPerPixelKey = 'screen_calibration_mm_per_pixel';
  static const String _calibratedAtKey = 'screen_calibration_at';

  /// A rough, NOT-to-be-trusted starting guess for mm-per-logical-pixel,
  /// used only to size the calibration guide sensibly before the user has
  /// calibrated — never used to save an actual wrist measurement.
  ///
  /// This is deliberately a *constant*, not scaled by `devicePixelRatio`.
  /// Logical pixels ("dp") are designed to stay a roughly constant
  /// physical size (~1/160 inch) across devices regardless of pixel
  /// density — that's the entire point of device-independent pixels.
  /// devicePixelRatio only says how many *physical* pixels make up one
  /// logical pixel; it says nothing about the logical pixel's real-world
  /// size, so scaling by it (an earlier version of this method did) only
  /// throws the guess off by that same factor. In practice this nominal
  /// value can still be off by 10-15%+ on devices that misreport density
  /// (see class doc) — it's a starting point for the slider, nothing more.
  static double roughGuessMmPerPixel() {
    const nominalLogicalPixelsPerInch = 160.0;
    return 25.4 / nominalLogicalPixelsPerInch;
  }

  /// The saved, calibrated mm-per-pixel ratio for this device, or null if
  /// this device hasn't been calibrated yet.
  static Future<double?> getMmPerPixel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_mmPerPixelKey);
  }

  static Future<bool> isCalibrated() async {
    final value = await getMmPerPixel();
    return value != null && value > 0;
  }

  static Future<void> saveMmPerPixel(double mmPerPixel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_mmPerPixelKey, mmPerPixel);
    await prefs.setString(_calibratedAtKey, DateTime.now().toIso8601String());
  }

  static Future<DateTime?> getCalibratedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_calibratedAtKey);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  /// Clears calibration, e.g. before walking the user through it again.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mmPerPixelKey);
    await prefs.remove(_calibratedAtKey);
  }
}