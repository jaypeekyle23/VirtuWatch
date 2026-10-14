import 'package:flutter/material.dart';
import '../constants/app_version.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';

/// Details about the running build: version, build number and what this
/// release includes. Version numbers come from [AppVersion], the same
/// constants the update checker reads, so the two never disagree.
class VersionInfoScreen extends StatelessWidget {
  const VersionInfoScreen({super.key});

  static const _details = [
    ('Version', AppVersion.versionName),
    ('Build Number', AppVersion.buildNumber),
    ('Release', 'Initial Capstone Release'),
  ];

  static const _included = [
    (
      'For Shoppers',
      [
        'AR virtual try-on with screen-calibrated wrist measurement',
        'Outfit color scanning and fit/style/color-based watch recommendations',
        'Ask VirtuWatch AI in-app chat assistant',
        'Full watch catalog with search, filters, sorting, and grid/list view',
        'Multi-photo and multi-color watch listings',
        'Save and revisit favorite watches',
      ],
    ),
    (
      'For Merchants & Admins',
      [
        'Customer, Merchant, and Admin accounts with role-based access',
        'Merchant tools to list, edit, and manage watches, including 3D models for AR',
        'Admin dashboard for account, role, and catalog oversight',
      ],
    ),
  ];

  static TextStyle get _body =>

      TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Version Info', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            luxeLogo(alignment: Alignment.center),
            const SizedBox(height: 16),
            Text(
              'Version ${AppVersion.versionName} (${AppVersion.buildNumber})',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),
            luxeSection(
              'BUILD DETAILS',
              Column(
                spacing: 12,
                children: [
                  for (final (label, value) in _details)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(value,
                              textAlign: TextAlign.right, style: _body),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("What's Included", style: AppTheme.serif(size: 24)),
            const SizedBox(height: 16),
            for (final (title, notes) in _included)
              luxeSection(
                title.toUpperCase(),
                Column(
                  spacing: 12,
                  children: [
                    for (final note in notes)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check,
                              color: AppTheme.textSecondary, size: 16),
                          const SizedBox(width: 12),
                          Expanded(child: Text(note, style: _body)),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
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
}