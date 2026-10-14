import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/app_version.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/theme_mode_picker.dart';
import '../about_screen.dart';
import '../change_password_screen.dart';
import '../delete_account_screen.dart';
import '../privacy_policy_screen.dart';
import '../terms_of_service_screen.dart';
import '../update_screen.dart';
import '../version_info_screen.dart';
import 'edit_profile_screen.dart';
import 'saved_watches_screen.dart';
import 'wrist_measurement_screen.dart';

void _go(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

/// Small letter-spaced text button. Gold only when it is the main action.
Widget _link(String label, VoidCallback onTap, {bool accent = false}) =>
    InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: kLabelStyle.copyWith(
            color: accent ? AppTheme.gold : AppTheme.textPrimary,
          ),
        ),
      ),
    );

class CustomerProfileTab extends StatelessWidget {
  const CustomerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile', style: AppTheme.serif(size: 28)),
        actions: [
          TextButton(
            onPressed: () => _confirmLogout(context),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: const Text('Log out'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) => snapshot.hasData
                  ? _content(context, snapshot.data!.data() ?? {})
                  : const _ProfileSkeleton(),
            ),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> data) {
    final username = data['username'] as String? ?? 'User';
    final email = data['email'] as String? ?? '';
    final styles = (data['stylePreferences'] as List?)?.cast<String>() ?? [];
    final wrist = (data['wristWidthMm'] as num?)?.toDouble();
    final photoUrl = data['photoUrl'] as String? ?? '';
    final initials = username
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((e) => e[0])
        .take(2)
        .join()
        .toUpperCase();

    final menu = <(String, Widget, String?)>[
      ('Change Password', const ChangePasswordScreen(), null),
      ('About VirtuWatch', const AboutScreen(), null),
      ('Version', const VersionInfoScreen(), 'v${AppVersion.versionName}'),
      ('Check for Updates', const UpdateScreen(), null),
      ('Terms of Service', const TermsOfServiceScreen(), null),
      ('Privacy Policy', const PrivacyPolicyScreen(), null),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppTheme.surface,
                backgroundImage:
                    photoUrl.isNotEmpty ? NetworkPhoto.provider(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? Text(initials.isEmpty ? '?' : initials,
                        style: AppTheme.serif(size: 24))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(size: 26)),
                    Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 6),
                    _link(
                      'EDIT PROFILE',
                      () => _go(
                        context,
                        EditProfileScreen(
                          currentUsername: username,
                          currentEmail: email,
                          currentStylePreferences: styles,
                          currentPreferredBrands:
                              (data['preferredBrands'] as List?)
                                      ?.cast<String>() ??
                                  [],
                          currentBudgetMin:
                              (data['budgetMin'] as num?)?.toDouble() ?? 0,
                          currentBudgetMax:
                              (data['budgetMax'] as num?)?.toDouble() ?? 50000,
                          currentPhotoUrl: photoUrl,
                          currentGender: data['gender'] as String?,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          luxeSection(
            'WRIST MEASUREMENT',
            Text(
              wrist != null ? '${wrist.toStringAsFixed(1)}mm' : 'Not measured yet',
              style: AppTheme.serif(
                size: wrist != null ? 34 : 20,
                color: wrist != null
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
            trailing: _link(
              wrist != null ? 'RETAKE' : 'MEASURE',
              () => _go(context, const WristMeasurementScreen()),
              accent: wrist == null,
            ),
          ),
          if (styles.isNotEmpty)
            luxeSection(
              'STYLE',
              Text(styles.join('  ·  '),
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15)),
            ),
          luxeSection('APPEARANCE', const ThemeModePicker()),
          _SavedWatches(savedWatchIds: (data['savedWatches'] as List?)?.cast<String>() ?? []),
          const SizedBox(height: 8),
          for (final (title, screen, trailing) in menu)
            InkWell(
              onTap: () => _go(context, screen),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: kTopRule,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 14)),
                    ),
                    if (trailing != null)
                      Text(trailing,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => _go(context, const DeleteAccountScreen()),
            child: Text('Delete account',
                style: TextStyle(
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Log out?', style: AppTheme.serif(size: 22)),
        content: Text(
          'Are you sure you want to log out of your VirtuWatch account?',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
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

/// Saved-watches preview strip. Saved IDs can point at watches a merchant
/// has since deleted, so the docs are fetched to show and count only the
/// ones that still exist.
class _SavedWatches extends StatelessWidget {
  final List<String> savedWatchIds;

  const _SavedWatches({required this.savedWatchIds});

  @override
  Widget build(BuildContext context) {
    if (savedWatchIds.isEmpty) return _view(context, const [], const {});
    return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
      future: Future.wait(savedWatchIds.map(
          (id) => FirebaseFirestore.instance.collection('watches').doc(id).get())),
      builder: (context, snapshot) {
        final docs = snapshot.data?.where((d) => d.exists).toList();
        // Until the docs load, show the saved IDs with placeholder photos
        // rather than a false "No saved watches" message.
        return _view(
          context,
          docs?.map((d) => d.id).toList() ?? savedWatchIds,
          {
            for (final d in docs ?? <DocumentSnapshot<Map<String, dynamic>>>[])
              d.id: d.data()?['imageUrl'] as String? ?? '',
          },
        );
      },
    );
  }

  Widget _view(
      BuildContext context, List<String> ids, Map<String, String> images) {
    const size = 48.0;
    return InkWell(
      onTap: () => _go(context, const SavedWatchesScreen()),
      child: luxeSection(
        'SAVED WATCHES (${ids.length})',
        trailing: Icon(Icons.chevron_right,
            size: 18, color: AppTheme.textSecondary),
        ids.isEmpty
            ? Text(
                'No saved watches yet. Tap the heart on a watch to save it.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              )
            : Row(
                children: [
                  for (final id in ids.take(4))
                    Container(
                      width: size,
                      height: size,
                      margin: const EdgeInsets.only(right: 10),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: (images[id] ?? '').isEmpty
                          ? Icon(Icons.watch,
                              size: 20, color: AppTheme.textSecondary)
                          : NetworkPhoto(
                              url: images[id]!,
                              errorWidget: Icon(Icons.watch,
                                  size: 20, color: AppTheme.textSecondary),
                            ),
                    ),
                  if (ids.length > 4)
                    Text('+${ids.length - 4}',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
      ),
    );
  }
}

/// Loading placeholder shaped like the profile above. The shared
/// ProfileSkeleton still serves the merchant and admin profiles.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          const Row(
            children: [
              SkeletonBox(
                  width: 68,
                  height: 68,
                  borderRadius: BorderRadius.all(Radius.circular(34))),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 22),
                  SizedBox(height: 8),
                  SkeletonBox(width: 180, height: 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < 3; i++)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: kTopRule,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 110, height: 10),
                  SizedBox(height: 12),
                  SkeletonBox(width: 90, height: 28),
                ],
              ),
            ),
        ],
      ),
    );
  }
}