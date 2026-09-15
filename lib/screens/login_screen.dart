import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
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

      final role = profile['role'] as String? ?? 'customer';
      final username = profile['username'] as String? ?? 'User';

      Widget destination;

      switch (role) {
        case 'admin':
          destination = AdminShell(username: username);
          break;
        case 'merchant':
          destination = MerchantShell(username: username);
          break;
        default:
          destination = CustomerShell(username: username);
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      if (e.toString() == 'EMAIL_NOT_VERIFIED') {
        setState(() {
          _errorMessage =
              'Please verify your email before logging in. Check your inbox for the verification link.';
          _showResendVerification = true;
        });
      } else {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

      final role = profile['role'] as String? ?? 'customer';
      final username = profile['username'] as String? ?? 'User';

      Widget destination;

      switch (role) {
        case 'admin':
          destination = AdminShell(username: username);
          break;
        case 'merchant':
          destination = MerchantShell(username: username);
          break;
        default:
          destination = CustomerShell(username: username);
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
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
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                              const SizedBox(height: 0),

                              Text(
                                'Welcome Back.',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),

                              const SizedBox(height: 6),

                              Text(
                                'Sign in to your account',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),

                              const SizedBox(height: 32),

                              _fieldLabel('EMAIL ADDRESS'),

                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: 'Enter your email',
                                ),
                                validator: (value) {
                                  if (value == null ||
                                      value.trim().isEmpty) {
                                    return 'Please enter an email';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              _fieldLabel('PASSWORD'),

                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  hintText: 'Enter your password',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: AppTheme.textSecondary,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword =
                                            !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 8),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _handleForgotPassword,
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: AppTheme.gold,
                                      fontSize: 13,
                                    ),
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
                                      color: Colors.redAccent,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),

                              if (_showResendVerification)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleGoToVerify,
                                    child: const Text(
                                      'Resend verification email',
                                      style: TextStyle(
                                        color: AppTheme.gold,
                                      ),
                                    ),
                                  ),
                                ),

                              ElevatedButton(
                                onPressed:
                                    _isLoading ? null : _handleLogin,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Log In'),
                              ),

                              const SizedBox(height: 20),

                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: AppTheme.textSecondary
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),

                                  Expanded(
                                    child: Divider(
                                      color: AppTheme.textSecondary
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              OutlinedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : _handleGoogleSignIn,
                                icon: SvgPicture.asset(
                                  'assets/icons/google_logo.svg',
                                  width: 20,
                                  height: 20,
                                ),
                                label: const Text(
                                  'Continue with Google',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.textPrimary,
                                  side: const BorderSide(
                                    color: AppTheme.textSecondary,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              Center(
                                child: RichText(
                                  text: TextSpan(
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                    children: [
                                      const TextSpan(
                                        text: "Don't have an account? ",
                                      ),
                                      TextSpan(
                                        text: 'Sign Up',
                                        style: const TextStyle(
                                          color: AppTheme.gold,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const RegisterScreen(),
                                              ),
                                            );
                                          },
                                      ),
                                    ],
                                  ),
                                ),
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