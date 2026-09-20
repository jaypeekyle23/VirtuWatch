import 'package:flutter/material.dart';
import '../constants/app_version.dart';
import '../theme/app_theme.dart';

/// Shows details about the current app build — version number, build
/// metadata, and what's actually included in this release. Distinct
/// from [AboutScreen], which covers what the app is and who built it
/// rather than which specific build someone is running.
///
/// The version/build numbers below come from [AppVersion], which is
/// read from pubspec.yaml's `version:` line by hand rather than via a
/// package like package_info_plus — a deliberate tradeoff to avoid
/// adding a new dependency for a couple of static strings. The update
/// checker (see UpdateCheckerService) reads the same constants, so this
/// screen and the "update available" check never disagree about what
/// version is currently installed.
class VersionInfoScreen extends StatelessWidget {
  const VersionInfoScreen({super.key});

  static const _versionName = AppVersion.versionName;
  static const _buildNumber = AppVersion.buildNumber;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Version Info'),
      ),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo (cropped to just its visible mark — the source asset has
            // large transparent bands above/below it that would otherwise
            // reserve blank space at the bottom of this page).
            Center(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.center,
                  heightFactor: 0.34,
                  child: Image.asset(
                    'assets/images/branding/logo.png',
                    width: 300,
                    fit: BoxFit.fitWidth,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: Text(
                'Version $_versionName ($_buildNumber)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 28),

            _sectionCard(
              title: 'Build Details',
              child: Column(
                children: const [
                  _InfoRow(
                    label: 'Version',
                    value: _versionName,
                  ),
                  _InfoRow(
                    label: 'Build Number',
                    value: _buildNumber,
                  ),
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
              title: "What's Included — For Shoppers",
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReleaseNote(
                    text:
                        'AR virtual try-on with screen-calibrated wrist measurement',
                  ),
                  _ReleaseNote(
                    text:
                        'Outfit color scanning and fit/style/color-based watch recommendations',
                  ),
                  _ReleaseNote(
                    text: 'Ask VirtuWatch AI in-app chat assistant',
                  ),
                  _ReleaseNote(
                    text:
                        'Full watch catalog with search, filters, sorting, and grid/list view',
                  ),
                  _ReleaseNote(
                    text: 'Multi-photo and multi-color watch listings',
                  ),
                  _ReleaseNote(
                    text: 'Save and revisit favorite watches',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              title: "What's Included — For Merchants & Admins",
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReleaseNote(
                    text:
                        'Customer, Merchant, and Admin accounts with role-based access',
                  ),
                  _ReleaseNote(
                    text:
                        'Merchant tools to list, edit, and manage watches, including 3D models for AR',
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
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
  }) {
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
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
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

  const _ReleaseNote({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppTheme.gold,
            size: 18,
          ),
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