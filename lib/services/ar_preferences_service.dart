import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small AR try-on settings remembered on this device, separately for each
/// signed-in account (so two people sharing a phone don't share a size
/// setting). Stored locally on purpose: it needs no network and no Firestore
/// rules, and the value is only a few bytes.
class ArPreferences {
  ArPreferences._();

  static const double sizeAdjustMin = -20;
  static const double sizeAdjustMax = 20;

  /// How far the watch can be moved from its default spot on the forearm,
  /// in centimetres. Negative = toward the hand, positive = toward the elbow.
  static const double positionAdjustMin = -1.5;
  static const double positionAdjustMax = 3.0;

  static String get _who => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  static String get _sizeKey => 'ar_size_adjust_$_who';
  static String get _positionKey => 'ar_position_adjust_$_who';
  static String get _tipsKey => 'ar_tips_seen_$_who';

  /// The size correction (percent, -20..20) this person last chose; 0 if none.
  static Future<double> loadSizeAdjust() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_sizeKey);
      if (v == null || !v.isFinite) return 0;
      return v.clamp(sizeAdjustMin, sizeAdjustMax).toDouble();
    } catch (_) {
      return 0; // a settings problem must never block the camera
    }
  }

  static Future<void> saveSizeAdjust(double percent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_sizeKey, percent);
    } catch (_) {}
  }

  /// The position correction (cm along the forearm) this person last chose; 0 if none.
  static Future<double> loadPositionAdjust() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_positionKey);
      if (v == null || !v.isFinite) return 0;
      return v.clamp(positionAdjustMin, positionAdjustMax).toDouble();
    } catch (_) {
      return 0;
    }
  }

  static Future<void> savePositionAdjust(double cm) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_positionKey, cm);
    } catch (_) {}
  }

  /// Whether the first-time "how to hold your hand" tips were already shown.
  static Future<bool> hasSeenTips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_tipsKey) ?? false;
    } catch (_) {
      return true; // if storage is broken, don't nag on every visit
    }
  }

  static Future<void> markTipsSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tipsKey, true);
    } catch (_) {}
  }
}
