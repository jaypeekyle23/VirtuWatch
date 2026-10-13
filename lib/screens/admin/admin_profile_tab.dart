import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/app_version.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/luxe.dart';
import '../../widgets/profile_parts.dart';
import '../../widgets/profile_skeleton.dart';
import '../about_screen.dart';
import '../change_password_screen.dart';
import '../delete_account_screen.dart';
import '../edit_account_name_screen.dart';
import '../privacy_policy_screen.dart';
import '../terms_of_service_screen.dart';
import '../update_screen.dart';
import '../version_info_screen.dart';

class AdminProfileTab extends StatelessWidget {
  const AdminProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: profileAppBar(context),
      body: uid == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) => snapshot.hasData
                  ? _content(context, snapshot.data!.data() ?? {})
                  : const ProfileSkeleton(menuItems: 6),
            ),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> data) {
    final username = data['username'] as String? ?? 'Admin';
    final photoUrl = data['photoUrl'] as String? ?? '';
    final created = (data['createdAt'] as Timestamp?)?.toDate();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                ProfileHeader(
                  username: username,
                  email: data['email'] as String? ?? '',
                  photoUrl: photoUrl,
                  onEdit: () => pushScreen(
                    context,
                    EditAccountNameScreen(
                        currentUsername: username, currentPhotoUrl: photoUrl),
                  ),
                ),
                const SizedBox(height: 24),
                luxeSection(
                  'ACCOUNT',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Administrator', style: AppTheme.serif(size: 28)),
                      if (created != null) ...[
                        const SizedBox(height: 4),
                        Text('Member since ${formatDate(created)}',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                profileMenu(context, [
                  ('Change Password', const ChangePasswordScreen(), null),
                  ('About VirtuWatch', const AboutScreen(), null),
                  ('Version', const VersionInfoScreen(),
                      'v${AppVersion.versionName}'),
                  ('Check for Updates', const UpdateScreen(), null),
                  ('Terms of Service', const TermsOfServiceScreen(), null),
                  ('Privacy Policy', const PrivacyPolicyScreen(), null),
                ]),
              ],
            ),
          ),
        ),
        // Pinned to the bottom so short content doesn't leave it floating.
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 16),
              child: TextButton(
                onPressed: () =>
                    pushScreen(context, const DeleteAccountScreen()),
                child: Text('Delete account',
                    style: TextStyle(
                        color: Colors.redAccent.withValues(alpha: 0.8),
                        fontSize: 12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}