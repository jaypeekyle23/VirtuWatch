import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/engagement_notification_service.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'customer/customer_shell.dart';
import 'merchant/merchant_shell.dart';
import 'admin/admin_shell.dart';

/// The app's actual startup screen (used as [MaterialApp.home] instead
/// of [LoginScreen] directly). Firebase Auth persists a signed-in
/// session across app restarts by default on mobile, but nothing was
/// checking for that — the app always opened on the login form
/// regardless, forcing a fresh login every launch even with a perfectly
/// valid session sitting there. This checks for one via
/// [AuthService.fetchCurrentUserProfile] and routes straight to the
/// right role's shell when it finds one, falling back to [LoginScreen]
/// otherwise (no session, or the session failed re-validation).
///
/// On a genuine first launch (before that check even runs) it shows
/// [OnboardingScreen] instead — a one-time, on-device flag (see
/// [onboardingSeenPrefsKey]) tracks whether that's already happened,
/// independent of whether anyone is signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();
  late final Future<Map<String, dynamic>?> _profileFuture;
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.fetchCurrentUserProfile();
    _profileFuture.then(_runPostLoginChecks);
    _loadOnboardingFlag();
  }

  /// Runs once, right after a signed-in profile is found — this is the
  /// app's "open/resume" moment. The update check applies to every
  /// role; the email-verification and saved-watches reminders are
  /// customer-only concepts, so they're skipped for merchant/admin
  /// accounts. Both are fire-and-forget: neither should block or affect
  /// what AuthGate renders.
  void _runPostLoginChecks(Map<String, dynamic>? profile) {
    if (profile == null) return;
    UpdateCheckerService.instance.checkForUpdate();
    final role = profile['role'] as String? ?? 'customer';
    if (role == 'customer') {
      EngagementNotificationService.instance.runChecks();
    }
  }

  Future<void> _loadOnboardingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hasSeenOnboarding = prefs.getBool(onboardingSeenPrefsKey) ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
      );
    }

    if (!_hasSeenOnboarding!) {
      return OnboardingScreen(
        onDone: () => setState(() => _hasSeenOnboarding = true),
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.gold),
            ),
          );
        }

        final profile = snapshot.data;
        if (profile == null) {
          return const LoginScreen();
        }

        final role = profile['role'] as String? ?? 'customer';
        final username = profile['username'] as String? ?? 'User';
        switch (role) {
          case 'admin':
            return AdminShell(username: username);
          case 'merchant':
            return MerchantShell(username: username);
          default:
            return CustomerShell(username: username);
        }
      },
    );
  }
}