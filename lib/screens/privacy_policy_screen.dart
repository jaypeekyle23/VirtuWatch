import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = [
    (
      '1. Introduction',
      'This Privacy Policy explains how VirtuWatch collects, uses, and protects '
          'your personal information. VirtuWatch is developed as a Capstone '
          'Project at the National Teachers College, Manila, Philippines, and '
          'this policy is intended to comply with the principles of the Data '
          'Privacy Act of 2012 (Republic Act No. 10173).',
    ),
    (
      '2. Information We Collect',
      'Depending on how you use VirtuWatch, we may collect:\n\n'
          '• Account information: your name, email address, and password (or '
          'Google account information if you sign in with Google)\n'
          '• Profile preferences: your style preferences, preferred brands, and '
          'budget range\n'
          "• Usage data: watches you've saved or favorited, and your account "
          'role and status\n'
          '• Merchant data: watch listings, pricing, and specifications you '
          'submit if you are a merchant\n'
          '• In future versions, wrist measurement data derived from images you '
          'submit, used solely to recommend appropriately sized watches',
    ),
    (
      '3. How We Use Your Information',
      'We use the information we collect to: create and manage your account, '
          'personalize your catalog browsing and recommendations, allow you to '
          'save and revisit favorite watches, allow merchants to manage their '
          'listings, and allow administrators to maintain the security and '
          'integrity of the platform. We do not sell your personal information '
          'to third parties.',
    ),
    (
      '4. Wrist Measurement & Biometric Data',
      'A future feature of VirtuWatch will estimate wrist dimensions from an '
          'image you provide, using computer vision techniques, in order to '
          'recommend well-fitting watches. This type of data is treated with '
          'heightened care as sensitive personal information. It will only be '
          'used for the stated fit-recommendation purpose, will be handled '
          'according to applicable Firestore Security Rules restricting access '
          'to your own account, and will not be shared with merchants or other '
          'users.',
    ),
    (
      '5. Data Storage & Security',
      'Your data is stored using Firebase Authentication and Cloud Firestore, '
          'services provided by Google. Access to personal data is restricted by '
          'security rules so that, in general, only you and platform '
          'administrators can access your own profile information.',
    ),
    (
      '6. Your Rights',
      'Under the Data Privacy Act (RA 10173), you have the right to be informed '
          'about how your data is processed, to access and correct your personal '
          'information (via the Edit Profile screen), and to request the deletion '
          'of your account and associated data by contacting an administrator.',
    ),
    (
      '7. Data Sharing',
      'Merchant account holders can view the watch listings they manage. '
          'Administrators may access account information as needed to maintain '
          'the platform (for example, to review reports of misuse). We do not '
          'share your personal information with third-party advertisers.',
    ),
    (
      "8. Children's Privacy",
      'VirtuWatch is not directed at children and is not knowingly used to '
          'collect personal information from children.',
    ),
    (
      '9. Changes to This Policy',
      'This Privacy Policy may be updated as the VirtuWatch project evolves, '
          'particularly as new features such as wrist measurement and AI-based '
          'recommendations are implemented.',
    ),
    (
      '10. Contact',
      'For questions regarding this Privacy Policy or your personal data, please '
          'reach out to the VirtuWatch project proponents through the National '
          'Teachers College.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Privacy Policy', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LAST UPDATED: SEPTEMBER 2026', style: kLabelStyle),
            const SizedBox(height: 16),
            for (final (title, body) in _sections)
              luxeSection(
                title.toUpperCase(),
                Text(
                  body,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}