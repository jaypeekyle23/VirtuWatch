import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

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
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
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
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleOpenEmailApp() async {
    final uri = Uri(scheme: 'mailto');
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open an email app on this device.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open an email app on this device.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _emailSent ? _buildSentState(context) : _buildFormState(context),
        ),
      ),
    );
  }

  Widget _buildFormState(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.gold, width: 1.5),
              ),
              child: const Icon(Icons.lock_reset_outlined,
                  color: AppTheme.gold, size: 28),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Forgot Password?',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the email associated with your account and we\'ll send you a link to reset your password.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          _fieldLabel('EMAIL ADDRESS'),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'Enter your email'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),

          ElevatedButton(
            onPressed: _isLoading ? null : _handleSendResetLink,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send Reset Link'),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Back to Login',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.gold, width: 1.5),
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              color: AppTheme.gold, size: 28),
        ),
        const SizedBox(height: 20),
        Text(
          'Check Your Email',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a password reset link to\n${_emailController.text.trim()}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Click the link in the email to choose a new password, then come back and log in.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          ),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _handleOpenEmailApp,
            icon: const Icon(Icons.email_outlined),
            label: const Text('Open Email App'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.gold,
              side: const BorderSide(color: AppTheme.gold),
            ),
            onPressed: (_isLoading || _resendCooldown > 0)
                ? null
                : _handleSendResetLink,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _resendCooldown > 0
                        ? 'Resend in ${_resendCooldown}s'
                        : 'Resend Email',
                  ),
          ),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Back to Login',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}