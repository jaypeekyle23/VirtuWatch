import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About VirtuWatch')),
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
            const SizedBox(height: 6),
            Center(
              child: Text(
                'AI-Based Virtual Watch Try-On &\nWrist Size Suggestion App',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 28),

            _sectionCard(
              title: 'About the App',
              child: Text(
                'VirtuWatch is a mobile platform that helps online shoppers find the '
                'right watch with confidence. By combining computer vision-based wrist '
                'measurement with a virtual try-on experience, VirtuWatch aims to close '
                'the gap between browsing and buying a watch online, where sizing and '
                'fit are usually the biggest sources of doubt.\n\n'
                'The app is being developed in partnership with Urbane Time, and serves '
                'three types of users: customers looking to shop and try on watches, '
                'merchants managing their own watch catalogs, and administrators '
                'overseeing the platform as a whole.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              title: 'Key Features',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _FeatureItem(
                    icon: Icons.view_in_ar_outlined,
                    label: 'AI-powered virtual try-on and wrist size recommendation',
                  ),
                  _FeatureItem(
                    icon: Icons.storefront_outlined,
                    label: 'Full watch catalog with search, filters, and sorting',
                  ),
                  _FeatureItem(
                    icon: Icons.favorite_border,
                    label: 'Save and revisit your favorite watches',
                  ),
                  _FeatureItem(
                    icon: Icons.storefront,
                    label: 'Merchant tools to list, edit, and manage watch listings',
                  ),
                  _FeatureItem(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Admin dashboard for accounts, roles, and catalog oversight',
                  ),
                  _FeatureItem(
                    icon: Icons.g_mobiledata,
                    label: 'Secure sign-in with email/password or Google',
                  ),
                  _FeatureItem(
                    icon: Icons.verified_user_outlined,
                    label: 'Email verification and account protection',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              title: 'Capstone Project',
              child: Text(
                'VirtuWatch is developed as a Capstone Project at the National '
                'Teachers College, Manila, Philippines.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              title: 'Proponents',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _ProponentItem(name: 'Jaypee Kyle Alsagon'),
                  _ProponentItem(name: 'Maverick Intong'),
                  _ProponentItem(name: 'Deivid Yap'),
                  _ProponentItem(name: 'Carla Angeline Gahol'),
                  _ProponentItem(name: 'Argene Jay Acebes'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: Text(
                'VirtuWatch v1.0.0',
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

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
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

class _ProponentItem extends StatelessWidget {
  final String name;

  const _ProponentItem({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: AppTheme.textSecondary, size: 16),
          const SizedBox(width: 10),
          Text(
            name,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}