import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Account'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _handleCreate,
            child: Text(
              'Save',
              style: TextStyle(
                color: _isLoading ? AppTheme.textSecondary : AppTheme.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fieldLabel('FULL NAME *'),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: 'Enter full name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _fieldLabel('EMAIL ADDRESS *'),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'Enter email'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _fieldLabel('TEMPORARY PASSWORD'),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration:
                    const InputDecoration(hintText: 'Set a temporary password'),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                '⚠ User will be prompted to change this on first login',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 24),

              _fieldLabel('ACCOUNT ROLE'),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _selectedRole,
                onChanged: (value) => setState(() => _selectedRole = value!),
                child: Column(
                  children: [
                    _roleCard(
                      value: 'customer',
                      title: 'Regular User',
                      description:
                          'Can browse, measure wrist, scan outfit, and use AR try-on',
                      color: AppTheme.gold,
                    ),
                    const SizedBox(height: 10),
                    _roleCard(
                      value: 'merchant',
                      title: 'Merchant',
                      description:
                          'Can manage their own watch catalog and 3D assets',
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(height: 10),
                    _roleCard(
                      value: 'admin',
                      title: 'Admin',
                      description: 'Full system access — use with caution',
                      color: Colors.redAccent,
                      warning: 'Admin accounts have full system access.',
                    ),
                  ],
                ),
              ),

              if (_selectedRole == 'customer') ...[
                const SizedBox(height: 24),
                _fieldLabel('STYLE PREFERENCES (USER)'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _styleOptions.map((style) {
                    final isSelected = _selectedStyles.contains(style);
                    return ChoiceChip(
                      label: Text(style),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedStyles.add(style);
                          } else {
                            _selectedStyles.remove(style);
                          }
                        });
                      },
                      backgroundColor: AppTheme.surface,
                      selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppTheme.gold : Colors.transparent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 24),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
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

  Widget _roleCard({
    required String value,
    required String title,
    required String description,
    required Color color,
    String? warning,
  }) {
    final isSelected = _selectedRole == value;
    return InkWell(
      onTap: () => setState(() => _selectedRole = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<String>(
              value: value,
              activeColor: color,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (warning != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '⚠ $warning',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
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