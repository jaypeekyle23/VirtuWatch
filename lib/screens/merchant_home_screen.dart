import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class MerchantHomeScreen extends StatelessWidget {
  final String username;
  const MerchantHomeScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Welcome, $username 👋\n(Merchant Dashboard — catalog CRUD coming soon)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
        ),
      ),
    );
  }
}