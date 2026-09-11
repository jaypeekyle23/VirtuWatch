import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows details about the current app build — version number, build
/// metadata, and what's actually included in this release. Distinct
/// from [AboutScreen], which covers what the app is and who built it
/// rather than which specific build someone is running.
///
/// The version/build numbers below are read from pubspec.yaml's
/// `version:` line by hand rather than via a package like
/// package_info_plus, so they need to be kept in sync manually if that
/// value changes — a deliberate tradeoff to avoid adding a new
/// dependency for a single static string.
class VersionInfoScreen extends StatelessWidget {
  const VersionInfoScreen({super.key});

  static const _versionName = '1.0.0';
  static const _buildNumber = '1';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Version Info')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.gold, width: 1.5),
                ),
                child: const Icon(
                  Icons.watch_outlined,
                  color: AppTheme.gold,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'VirtuWatch',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Version $_versionName ($_buildNumber)',
                style:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 28),

            _sectionCard(
              title: 'Build Details',
              child: Column(
                children: const [
                  _InfoRow(label: 'Version', value: _versionName),
                  _InfoRow(label: 'Build Number', value: _buildNumber),
                  _InfoRow(
                    label: 'Release',
                    value: 'Initial Capstone Release',
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              title: "What's Included",
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReleaseNote(
                    text:
                        'Customer, Merchant, and Admin accounts with role-based access',
                  ),
                  _ReleaseNote(
                    text: 'Full watch catalog with search, filters, and sorting',
                  ),
                  _ReleaseNote(
                    text:
                        'Outfit color scanning and fit/color/style-based watch recommendations',
                  ),
                  _ReleaseNote(
                    text: 'Merchant tools to list, edit, and manage watches',
                  ),
                  _ReleaseNote(
                    text:
                        'Admin dashboard for account, role, and catalog oversight',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: Text(
                '© 2026 VirtuWatch. All rights reserved.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.gold,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNote extends StatelessWidget {
  final String text;

  const _ReleaseNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}