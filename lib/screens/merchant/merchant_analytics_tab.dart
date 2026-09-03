import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class MerchantAnalyticsTab extends StatelessWidget {
  const MerchantAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: const Center(
        child: Text(
          'Analytics coming soon\n(needs AR try-on session data)',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}