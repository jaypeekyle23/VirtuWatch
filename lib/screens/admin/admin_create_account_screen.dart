import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';

class AdminCreateAccountScreen extends StatefulWidget {
  const AdminCreateAccountScreen({super.key});

  @override
  State<AdminCreateAccountScreen> createState() =>
      _AdminCreateAccountScreenState();
}

class _AdminCreateAccountScreenState extends State<AdminCreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  String _selectedRole = 'customer';
  bool _isLoading = false;
  bool _obscure = true;
  String? _errorMessage;

  final List<String> _styleOptions = [
    'Classic',
    'Sport',
    'Luxury',
    'Casual',
    'Minimalist',
    'Dress',
  ];
  final Set<String> _selectedStyles = {'Classic'};

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.createAccountForRole(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        username: _nameController.text.trim(),
        role: _selectedRole,
        stylePreferences:
            _selectedRole == 'customer' ? _selectedStyles.toList() : const [],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully!')),
        );
        Navigator.of(context).pop();
      }
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

  static const _roles = [
    ('customer', 'Regular user',
        'Browse, measure wrist, scan outfit and use AR try-on.'),
    ('merchant', 'Merchant', 'Manage their own watch catalog and 3D assets.'),
    ('admin', 'Admin', 'Full system access. Use with caution.'),
  ];

  /// Label + underline field.
  Widget _field(
    String label,
    TextEditingController controller,
    String hint,
    String? Function(String?) validator, {
    TextInputType? keyboardType,
    bool password = false,
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
              obscureText: password && _obscure,
              style: const TextStyle(fontSize: 15),
              decoration: luxeFieldDecoration(
                hint: hint,
                suffixIcon: password
                    ? IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            size: 18),
                        color: AppTheme.textSecondary,
                        padding: EdgeInsets.zero,
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null,
              ),
              validator: validator,
            ),
          ],
        ),
      );

  Widget _roleRow(String value, String title, String description) {
    final selected = _selectedRole == value;
    return InkWell(
      onTap: () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: kTopRule,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: selected
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppTheme.gold),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add account', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('FULL NAME', _nameController, 'Enter full name',
                  (v) => v == null || v.trim().isEmpty
                      ? 'Please enter a name'
                      : null),
              _field('EMAIL ADDRESS', _emailController, 'Enter email', (v) {
                if (v == null || v.trim().isEmpty) return 'Please enter an email';
                return v.contains('@') ? null : 'Please enter a valid email';
              }, keyboardType: TextInputType.emailAddress),
              _field('TEMPORARY PASSWORD', _passwordController,
                  'Set a temporary password',
                  (v) => v == null || v.length < 6
                      ? 'Password must be at least 6 characters'
                      : null,
                  password: true),
              const Text('They will be asked to change this on first login.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 28),
              const Text('ACCOUNT ROLE', style: kLabelStyle),
              const SizedBox(height: 8),
              for (final (value, title, description) in _roles)
                _roleRow(value, title, description),
              Container(decoration: kTopRule, height: 1),
              if (_selectedRole == 'admin')
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Admin accounts can manage every account and watch.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              if (_selectedRole == 'customer') ...[
                const SizedBox(height: 28),
                const Text('STYLE PREFERENCES', style: kLabelStyle),
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
              ],
              const SizedBox(height: 28),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_errorMessage!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleCreate,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}