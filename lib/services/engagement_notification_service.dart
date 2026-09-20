import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'user_service.dart';

/// Runs the two customer re-engagement checks — email verification and
/// saved/wishlist watches — once per app open. Both are throttled via
/// SharedPreferences so a customer who opens the app daily doesn't get
/// the same nudge every single time.
class EngagementNotificationService {
  EngagementNotificationService._();
  static final EngagementNotificationService instance =
      EngagementNotificationService._();

  static const _lastVerifyReminderKey = 'engagement_last_verify_reminder';
  static const _lastWishlistReminderKey = 'engagement_last_wishlist_reminder';

  static const _verifyReminderInterval = Duration(days: 1);
  static const _wishlistReminderInterval = Duration(days: 3);

  final _userService = UserService();

  /// Runs both checks. Safe to call every time a customer's AuthGate
  /// resolves (app open/resume) — each check decides for itself whether
  /// it's actually due, so calling this often is fine.
  Future<void> runChecks() async {
    await _checkEmailVerification();
    await _checkWishlist();
  }

  Future<void> _checkEmailVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.emailVerified) return;

    final prefs = await SharedPreferences.getInstance();
    if (!_dueFor(prefs, _lastVerifyReminderKey, _verifyReminderInterval)) {
      return;
    }

    await NotificationService.instance.showVerifyEmailReminder();
    await prefs.setString(
      _lastVerifyReminderKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> _checkWishlist() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_dueFor(prefs, _lastWishlistReminderKey, _wishlistReminderInterval)) {
      return;
    }

    final count = await _userService.savedWatchCount();
    if (count == 0) return;

    await NotificationService.instance.showWishlistReminder(count);
    await prefs.setString(
      _lastWishlistReminderKey,
      DateTime.now().toIso8601String(),
    );
  }

  bool _dueFor(SharedPreferences prefs, String key, Duration interval) {
    final lastRaw = prefs.getString(key);
    if (lastRaw == null) return true;
    final last = DateTime.tryParse(lastRaw);
    if (last == null) return true;
    return DateTime.now().difference(last) >= interval;
  }
}