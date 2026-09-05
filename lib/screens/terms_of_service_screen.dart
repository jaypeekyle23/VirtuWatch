import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last updated: September 2026',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 20),

            _section(
              '1. Acceptance of Terms',
              'By creating an account or using VirtuWatch, you agree to be bound by '
                  'these Terms of Service. VirtuWatch is developed as a Capstone Project '
                  'at the National Teachers College, Manila, Philippines, in partnership '
                  'with Urbane Time, and is intended for demonstration and academic '
                  'evaluation purposes.',
            ),
            _section(
              '2. Description of Service',
              'VirtuWatch is a mobile platform that allows users to browse a catalog of '
                  'watches, receive AI-assisted wrist size recommendations, and preview '
                  'how a watch may look through a virtual try-on feature. VirtuWatch does '
                  'not process payments or facilitate purchases directly; any purchase '
                  'intent is redirected to Urbane Time\'s own storefront or official pages.',
            ),
            _section(
              '3. User Accounts',
              'You are responsible for maintaining the confidentiality of your account '
                  'credentials and for all activity under your account. You must provide '
                  'accurate information when registering, and email/password accounts must '
                  'verify their email address before the account can be used. VirtuWatch '
                  'supports three account roles: Customer, Merchant, and Administrator, '
                  'each with different levels of access appropriate to their role.',
            ),
            _section(
              '4. Acceptable Use',
              'You agree not to misuse the platform, including but not limited to: '
                  'attempting to access accounts or data that do not belong to you, '
                  'uploading false or misleading watch listings, interfering with the '
                  'normal operation of the app, or using the platform for any unlawful '
                  'purpose.',
            ),
            _section(
              '5. Merchant Listings',
              'Merchants are responsible for the accuracy of the watch listings they '
                  'create, including pricing, specifications, and imagery. VirtuWatch and '
                  'its administrators reserve the right to edit, unlist, or remove '
                  'listings that are inaccurate, inappropriate, or in violation of these '
                  'Terms.',
            ),
            _section(
              '6. Intellectual Property',
              'The VirtuWatch app, its design, and its underlying technology are the '
                  'intellectual property of its student proponents and are provided for '
                  'academic and demonstration purposes. Watch brand names, images, and '
                  'trademarks remain the property of their respective owners.',
            ),
            _section(
              '7. Disclaimer',
              'VirtuWatch is a capstone/proof-of-concept application. AI-generated wrist '
                  'measurements and fit recommendations are estimates intended to assist '
                  'decision-making and should not be treated as exact or guaranteed. '
                  'VirtuWatch is provided "as is" without warranties of any kind.',
            ),
            _section(
              '8. Changes to These Terms',
              'These Terms may be updated as the project evolves. Continued use of the '
                  'app after changes are made constitutes acceptance of the revised Terms.',
            ),
            _section(
              '9. Contact',
              'For questions regarding these Terms, please reach out to the VirtuWatch '
                  'project proponents through the National Teachers College.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.gold,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}