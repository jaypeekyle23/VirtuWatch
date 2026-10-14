import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';

const _spinner = SizedBox(
  height: 20,
  width: 20,
  child: CircularProgressIndicator(strokeWidth: 2),
);

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final _emailController =
      TextEditingController(text: widget.initialEmail ?? '');

  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) timer.cancel();
      setState(() => _resendCooldown--);
    });
  }

  Future<void> _handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPassword(_emailController.text.trim());
      if (mounted) {
        setState(() => _emailSent = true);
        _startCooldown();
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOpenEmailApp() async {
    var launched = false;
    try {
      launched = await launchUrl(Uri(scheme: 'mailto'));
    } catch (_) {}
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open an email app on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(color: AppTheme.textSecondary, fontSize: 13);
    final email = _emailController.text.trim();

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Center(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      luxeLogo(),
                      const SizedBox(height: 24),
                      Text(_emailSent ? 'Check your email' : 'Forgot password?',
                          style: AppTheme.serif(size: 36)),
                      const SizedBox(height: 6),
                      if (_emailSent)
                        Text.rich(
                          TextSpan(style: small, children: [
                            const TextSpan(text: 'We sent a password reset link to '),
                            TextSpan(
                              text: email,
                              style: TextStyle(color: AppTheme.textPrimary),
                            ),
                            const TextSpan(
                                text: '. Open it to choose a new password, then '
                                    'come back and log in.'),
                          ]),
                        )
                      else
                        Text(
                          "Enter the email associated with your account and we'll "
                          'send you a link to reset your password.',
                          style: small,
                        ),
                      const SizedBox(height: 32),

                      if (!_emailSent) ...[
                        Text('EMAIL ADDRESS', style: kLabelStyle),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 15),
                          decoration: luxeFieldDecoration(hint: 'Enter your email'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            return v.contains('@')
                                ? null
                                : 'Please enter a valid email';
                          },
                        ),
                        const SizedBox(height: 32),
                      ],

                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      ElevatedButton(
                        onPressed: _emailSent
                            ? _handleOpenEmailApp
                            : _isLoading
                                ? null
                                : _handleSendResetLink,
                        child: _isLoading && !_emailSent
                            ? _spinner
                            : Text(_emailSent ? 'Open Email App' : 'Send Reset Link'),
                      ),

                      if (_emailSent) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _isLoading || _resendCooldown > 0
                              ? null
                              : _handleSendResetLink,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: BorderSide(color: AppTheme.outline),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? _spinner
                              : Text(_resendCooldown > 0
                                  ? 'Resend in ${_resendCooldown}s'
                                  : 'Resend Email'),
                        ),
                      ],
                      const SizedBox(height: 24),

                      Center(
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}