import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';
import 'verify_email_screen.dart';
import 'terms_of_service_screen.dart';
import 'privacy_policy_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _styleOptions = [
    'Classic',
    'Sport',
    'Luxury',
    'Casual',
    'Minimalist',
    'Dress',
  ];

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();
  final _selectedStyles = <String>{};

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      setState(() => _errorMessage =
          'Please agree to the Terms of Service and Privacy Policy.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.registerWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        username: _usernameController.text.trim(),
        stylePreferences: _selectedStyles.toList(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              email: _emailController.text.trim(),
              username: _usernameController.text.trim(),
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

  void _open(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  /// Label + underline field. Pass [obscure] and [onToggle] for password
  /// fields to get the show/hide eye.
  Widget _field(
    String label,
    TextEditingController controller,
    String hint,
    String? Function(String?) validator, {
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? onToggle,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: kLabelStyle),
            TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscure,
              style: const TextStyle(fontSize: 15),
              decoration: luxeFieldDecoration(
                hint: hint,
                suffixIcon: onToggle == null
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        onPressed: onToggle,
                      ),
              ),
              validator: validator,
            ),
          ],
        ),
      );

  TextSpan _link(String text, Widget screen) => TextSpan(
        text: text,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _open(screen),
      );

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(color: AppTheme.textSecondary, fontSize: 13);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                luxeLogo(),
                const SizedBox(height: 24),
                Text('Create account', style: AppTheme.serif(size: 36)),
                const SizedBox(height: 6),
                const Text('Start your virtual try-on experience',
                    style: small),
                const SizedBox(height: 32),

                _field(
                  'USERNAME',
                  _usernameController,
                  'Enter your username',
                  (v) => v == null || v.trim().isEmpty
                      ? 'Please enter a username'
                      : null,
                ),
                _field(
                  'EMAIL ADDRESS',
                  _emailController,
                  'Enter your email',
                  (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter an email';
                    }
                    return v.contains('@') ? null : 'Please enter a valid email';
                  },
                  keyboardType: TextInputType.emailAddress,
                ),
                _field(
                  'PASSWORD',
                  _passwordController,
                  'Create a password',
                  (v) => v == null || v.length < 6
                      ? 'Password must be at least 6 characters'
                      : null,
                  obscure: _obscurePassword,
                  onToggle: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                _field(
                  'CONFIRM PASSWORD',
                  _confirmController,
                  'Re-enter your password',
                  (v) => v != _passwordController.text
                      ? 'Passwords do not match'
                      : null,
                  obscure: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),

                const Text('STYLE PREFERENCE (OPTIONAL)', style: kLabelStyle),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final style in _styleOptions)
                      luxePill(
                        style,
                        selected: _selectedStyles.contains(style),
                        onTap: () => setState(() {
                          if (!_selectedStyles.remove(style)) {
                            _selectedStyles.add(style);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreedToTerms,
                        activeColor: AppTheme.textPrimary,
                        checkColor: AppTheme.background,
                        side: const BorderSide(color: Colors.white38),
                        onChanged: (v) =>
                            setState(() => _agreedToTerms = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: small,
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            _link('Terms of Service',
                                const TermsOfServiceScreen()),
                            const TextSpan(text: ' and '),
                            _link('Privacy Policy',
                                const PrivacyPolicyScreen()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

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
                  onPressed: _isLoading ? null : _handleRegister,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Account'),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account?  ', style: small),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Log In',
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
        ),
      ),
    );
  }
}