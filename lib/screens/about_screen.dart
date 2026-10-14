import 'package:flutter/material.dart';
import '../constants/app_version.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    (
      'For Shoppers',
      [
        (
          Icons.view_in_ar_outlined,
          'AR virtual try-on — see a watch rendered on your own wrist through the camera',
        ),
        (
          Icons.straighten,
          'Screen-calibrated wrist measurement — no camera or tape measure needed',
        ),
        (
          Icons.checkroom_outlined,
          "Outfit color scanning to match watches against what you're wearing",
        ),
        (
          Icons.auto_awesome,
          'Personalized "For You" recommendations blending wrist fit, style, and outfit color match',
        ),
        (
          Icons.chat_bubble_outline,
          'Ask VirtuWatch AI, an in-app assistant for fit and style questions',
        ),
        (
          Icons.storefront_outlined,
          'Full watch catalog with search, filters, sorting, and a grid/list view toggle',
        ),
        (
          Icons.photo_library_outlined,
          'Multi-photo and multi-color watch listings for a fuller look at each piece',
        ),
        (Icons.favorite_border, 'Save and revisit your favorite watches'),
      ],
    ),
    (
      'For Merchants & Admins',
      [
        (
          Icons.storefront,
          'Merchant tools to list, edit, and manage watch listings, including 3D models for AR',
        ),
        (
          Icons.admin_panel_settings_outlined,
          'Admin dashboard for accounts, roles, and catalog oversight',
        ),
      ],
    ),
    (
      'Account & Security',
      [
        (Icons.login, 'Secure sign-in with email/password or Google'),
        (
          Icons.verified_user_outlined,
          'Email verification and account protection',
        ),
      ],
    ),
  ];

  static const _proponents = [
    'Jaypee Kyle Alsagon',
    'Maverick Intong',
    'Deivid Yap',
    'Carla Angeline Gahol',
    'Argene Jay Acebes',
  ];

  static TextStyle get _body =>

      TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('About VirtuWatch', style: AppTheme.serif(size: 28)),
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
              'AI-Based Virtual Watch Try-On &\nWrist Size Suggestion App',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            luxeSection(
              'ABOUT THE APP',
              Text(
                'VirtuWatch is a mobile platform that helps online shoppers find the '
                'right watch with confidence. By combining an AR virtual try-on '
                'experience with screen-calibrated wrist measurement, VirtuWatch '
                'aims to close the gap between browsing and buying a watch online, '
                'where sizing and fit are usually the biggest sources of doubt.\n\n'
                'The app is being developed in partnership with Urbane Time, and serves '
                'three types of users: customers looking to shop and try on watches, '
                'merchants managing their own watch catalogs, and administrators '
                'overseeing the platform as a whole.',
                style: _body,
              ),
            ),
            for (final (title, items) in _features)
              luxeSection(
                title.toUpperCase(),
                Column(
                  spacing: 12,
                  children: [
                    for (final (icon, label) in items)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: AppTheme.textSecondary, size: 18),
                          const SizedBox(width: 12),
                          Expanded(child: Text(label, style: _body)),
                        ],
                      ),
                  ],
                ),
              ),
            luxeSection(
              'CAPSTONE PROJECT',
              Text(
                'VirtuWatch is developed as a Capstone Project at the National '
                'Teachers College, Manila, Philippines.',
                style: _body,
              ),
            ),
            luxeSection(
              'PROPONENTS',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [for (final n in _proponents) Text(n, style: _body)],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('VirtuWatch v${AppVersion.versionName}',
                  style: kLabelStyle),
            ),
          ],
        ),
      ),
    );
  }
}