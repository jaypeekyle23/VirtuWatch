import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_palette.dart';

/// Holds the look the user picked (Default, Dark or Light), remembers it
/// between launches, and tells listeners when it changes.
///
/// The choice is saved on the device, not in the user's account, so each
/// device keeps its own look.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _storageKey = 'app_theme_mode';

  AppThemeMode _mode = AppThemeMode.defaultMode;

  AppThemeMode get mode => _mode;

  AppPalette get palette => _mode.palette;

  /// Reads the saved choice. Call once before the app starts so the first
  /// screen already has the right colors. Falls back to the Default look
  /// if nothing is saved or storage cannot be read.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = AppThemeMode.fromStorage(prefs.getString(_storageKey));
    } catch (_) {
      _mode = AppThemeMode.defaultMode;
    }
  }

  /// Switches the look right away, then saves it. The switch still works
  /// for the current session if saving fails.
  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.storageValue);
    } catch (_) {
      // Not saved, but the look is already applied for this session.
    }
  }
}