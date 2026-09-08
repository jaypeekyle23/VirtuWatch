import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'edit_profile_screen.dart';
import 'saved_watches_screen.dart';
import 'wrist_measurement_screen.dart';
import '../change_password_screen.dart';
import '../about_screen.dart';
import '../delete_account_screen.dart';
import '../terms_of_service_screen.dart';
import '../privacy_policy_screen.dart';

class CustomerProfileTab extends StatelessWidget {
  const CustomerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: uid == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!.data() ?? {};
                final username = data['username'] as String? ?? 'User';
                final email = data['email'] as String? ?? '';
                final stylePreferences =
                    (data['stylePreferences'] as List?)?.cast<String>() ?? [];
                final preferredBrands =
                    (data['preferredBrands'] as List?)?.cast<String>() ?? [];
                final budgetMin =
                    (data['budgetMin'] as num?)?.toDouble() ?? 5000;
                final budgetMax =
                    (data['budgetMax'] as num?)?.toDouble() ?? 50000;
                final wristWidthMm = (data['wristWidthMm'] as num?)?.toDouble();
                final savedWatchIds =
                    (data['savedWatches'] as List?)?.cast<String>() ?? [];
                final photoUrl = data['photoUrl'] as String? ?? '';
                final initials = username.isNotEmpty
                    ? username.trim().split(' ').map((e) => e[0]).take(2).join()
                    : '?';

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: AppTheme.gold,
                        backgroundImage: photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                initials.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF0E1A2B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        username,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 18),
                      ),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.gold,
                          side: const BorderSide(color: AppTheme.gold),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(
                                currentUsername: username,
                                currentEmail: email,
                                currentStylePreferences: stylePreferences,
                                currentPreferredBrands: preferredBrands,
                                currentBudgetMin: budgetMin,
                                currentBudgetMax: budgetMax,
                                currentPhotoUrl: photoUrl,
                              ),
                            ),
                          );
                        },
                        child: const Text('Edit Profile'),
                      ),
                      const SizedBox(height: 20),

                      if (stylePreferences.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'MY STYLE PREFERENCES',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: stylePreferences.map((style) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.gold),
                              ),
                              child: Text(
                                style,
                                style: const TextStyle(
                                  color: AppTheme.gold,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'MY WRIST MEASUREMENT',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  wristWidthMm != null
                                      ? '${wristWidthMm}mm'
                                      : '— mm',
                                  style: const TextStyle(
                                    color: AppTheme.gold,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (wristWidthMm == null) ...[
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    margin: const EdgeInsets.only(bottom: 5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.textSecondary
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'NOT MEASURED YET',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.gold,
                                  side: const BorderSide(color: AppTheme.gold),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const WristMeasurementScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  wristWidthMm != null
                                      ? 'Retake Measurement'
                                      : 'Take Measurement',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      _SavedWatchesPreviewCard(savedWatchIds: savedWatchIds),
                      const SizedBox(height: 10),

                      _menuTile(context, 'Change Password', Icons.lock_outline,
                          () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen(),
                          ),
                        );
                      }),
                      _menuTile(context, 'About VirtuWatch', Icons.info_outline,
                          () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(),
                          ),
                        );
                      }),
                      _menuTile(context, 'Terms of Service',
                          Icons.description_outlined, () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TermsOfServiceScreen(),
                          ),
                        );
                      }),
                      _menuTile(context, 'Privacy Policy',
                          Icons.privacy_tip_outlined, () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PrivacyPolicyScreen(),
                          ),
                        );
                      }),
                      _menuTile(
                          context, 'Delete Account', Icons.delete_outline, () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DeleteAccountScreen(),
                          ),
                        );
                      }),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: () => _confirmLogout(context),
                          child: const Text('Log Out'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _menuTile(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Log Out?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Are you sure you want to log out of your VirtuWatch account?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await AuthService().logout();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    }
  }
}

class _SavedWatchesPreviewCard extends StatelessWidget {
  final List<String> savedWatchIds;

  const _SavedWatchesPreviewCard({required this.savedWatchIds});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SavedWatchesScreen(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Saved Watches (${savedWatchIds.length})',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Text(
                  'View All',
                  style: TextStyle(color: AppTheme.gold, fontSize: 12),
                ),
              ],
            ),
            if (savedWatchIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < savedWatchIds.length && i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _SavedWatchThumbnail(watchId: savedWatchIds[i]),
                  ],
                  if (savedWatchIds.length > 4) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '+${savedWatchIds.length - 4}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'No saved watches yet. Tap the heart on a watch to save it here.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single circular thumbnail for the saved-watches preview strip. Looks
/// up its own watch document by ID so it can show the real photo, falling
/// back to the generic watch icon while loading, on error, or if the watch
/// has no photo yet.
class _SavedWatchThumbnail extends StatelessWidget {
  final String watchId;

  const _SavedWatchThumbnail({required this.watchId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('watches')
          .doc(watchId)
          .get(),
      builder: (context, snapshot) {
        final imageUrl =
            snapshot.data?.data()?['imageUrl'] as String? ?? '';

        return Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppTheme.background,
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.watch,
                      color: AppTheme.gold,
                      size: 20),
                )
              : const Icon(Icons.watch, color: AppTheme.gold, size: 20),
        );
      },
    );
  }
}