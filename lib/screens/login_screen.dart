import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';
import 'forgot_password_screen.dart';
import 'customer/customer_shell.dart';
import 'merchant/merchant_shell.dart';
import 'admin/admin_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showResendVerification = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Opens the right home screen for the signed-in user's role. Shared by
  /// email and Google sign-in.
  void _goToHome(Map<String, dynamic> profile) {
    final role = profile['role'] as String? ?? 'customer';
    final username = profile['username'] as String? ?? 'User';

    final Widget destination = switch (role) {
      'admin' => AdminShell(username: username),
      'merchant' => MerchantShell(username: username),
      _ => CustomerShell(username: username),
    };

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showResendVerification = false;
    });

    try {
      final profile = await _authService.loginWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (profile == null || !mounted) return;
      _goToHome(profile);
    } catch (e) {
      if (e.toString() == 'EMAIL_NOT_VERIFIED') {
        setState(() {
          _errorMessage =
              'Please verify your email before logging in. Check your inbox for the verification link.';
          _showResendVerification = true;
        });
      } else {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoToVerify() async {
    setState(() => _isLoading = true);

    try {
      await _authService.signInWithoutVerificationCheck(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              email: _emailController.text.trim(),
              username: 'User',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim().isNotEmpty
              ? _emailController.text.trim()
              : null,
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showResendVerification = false;
    });

    try {
      final profile = await _authService.signInWithGoogle();
      if (profile == null || !mounted) return;
      _goToHome(profile);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.only(
                left: 24,
                right: 24,
                top: 10,
                bottom: 54,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),

                        Transform.translate(
                          offset: const Offset(-90, -50),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Image.asset(
                              'assets/images/branding/logo.png',
                              height: 350,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // Everything below the logo is moved upward
                        Transform.translate(
                          offset: const Offset(0, -140),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Welcome back',
                                  style: AppTheme.serif(size: 36)),
                              const SizedBox(height: 6),
                              const Text(
                                'Sign in to your account',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 32),

                              const Text('EMAIL ADDRESS', style: kLabelStyle),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 15),
                                decoration: luxeFieldDecoration(
                                    hint: 'Enter your email'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Please enter an email'
                                        : null,
                              ),
                              const SizedBox(height: 20),

                              const Text('PASSWORD', style: kLabelStyle),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(fontSize: 15),
                                decoration: luxeFieldDecoration(
                                  hint: 'Enter your password',
                                  suffixIcon: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: AppTheme.textSecondary,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                        ? 'Please enter your password'
                                        : null,
                              ),
                              const SizedBox(height: 12),

                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  onTap: _handleForgotPassword,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    child: Text('FORGOT PASSWORD?',
                                        style: kLabelStyle),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

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

                              if (_showResendVerification)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Center(
                                    child: InkWell(
                                      onTap:
                                          _isLoading ? null : _handleGoToVerify,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Text(
                                          'RESEND VERIFICATION EMAIL',
                                          style: kLabelStyle.copyWith(
                                              color: AppTheme.textPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Log In'),
                              ),
                              const SizedBox(height: 24),

                              const Row(
                                children: [
                                  Expanded(
                                      child: Divider(color: AppTheme.hairline)),
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
                                    child: Text('OR', style: kLabelStyle),
                                  ),
                                  Expanded(
                                      child: Divider(color: AppTheme.hairline)),
                                ],
                              ),
                              const SizedBox(height: 24),

                              OutlinedButton.icon(
                                onPressed:
                                    _isLoading ? null : _handleGoogleSignIn,
                                icon: SvgPicture.asset(
                                  'assets/icons/google_logo.svg',
                                  width: 20,
                                  height: 20,
                                ),
                                label: const Text('Continue with Google'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.textPrimary,
                                  side: const BorderSide(color: Colors.white24),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Don't have an account?  ",
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13),
                                  ),
                                  InkWell(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    ),
                                    child: const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 4),
                                      child: Text(
                                        'Sign Up',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}