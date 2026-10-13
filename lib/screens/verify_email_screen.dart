import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';
import 'customer/customer_shell.dart';
import 'login_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String username;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.username,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _authService = AuthService();

  bool _isResending = false;
  bool _hasNavigated = false;
  String? _message;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null &&
          refreshedUser.emailVerified &&
          !_hasNavigated &&
          mounted) {
        _hasNavigated = true;
        timer.cancel();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => CustomerShell(username: widget.username),
          ),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _handleResend() async {
    setState(() {
      _isResending = true;
      _message = null;
    });

    try {
      await _authService.resendVerificationEmail();
      if (mounted) {
        setState(() {
          _message = 'Verification email sent to ${widget.email}.';
        });
        _startCooldown();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _handleBackToLogin() async {
    _pollTimer?.cancel();
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(color: AppTheme.textSecondary, fontSize: 13);

    return Scaffold(
      body: luxeCenteredPage(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            luxeLogo(),
            const SizedBox(height: 24),
            Text('Verify your email', style: AppTheme.serif(size: 36)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(style: small, children: [
                const TextSpan(text: 'We sent a verification link to '),
                TextSpan(
                  text: widget.email,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                const TextSpan(
                  text: ". Click the link in your email — you'll be signed "
                      "in automatically once it's verified.",
                ),
              ]),
            ),
            const SizedBox(height: 32),
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.textSecondary),
                ),
                SizedBox(width: 12),
                Text('Waiting for verification...', style: small),
              ],
            ),
            const SizedBox(height: 32),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _message!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _message!.contains('sent to')
                        ? AppTheme.textPrimary
                        : Colors.redAccent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            OutlinedButton(
              onPressed:
                  _isResending || _resendCooldown > 0 ? null : _handleResend,
              style: luxeOutlinedStyle,
              child: _isResending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_resendCooldown > 0
                      ? 'Resend in ${_resendCooldown}s'
                      : 'Resend Verification Email'),
            ),
            const SizedBox(height: 24),
            Center(
              child: InkWell(
                onTap: _handleBackToLogin,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('BACK TO LOGIN',
                      style:
                          kLabelStyle.copyWith(color: AppTheme.textPrimary)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}