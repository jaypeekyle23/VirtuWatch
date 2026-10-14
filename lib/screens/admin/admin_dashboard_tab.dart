import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/activity_log_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home_header.dart';
import '../../widgets/luxe.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/update_available_banner.dart';
import '../merchant/merchant_add_watch_screen.dart';
import 'admin_create_account_screen.dart';
import 'admin_profile_tab.dart';

class AdminDashboardTab extends StatefulWidget {
  final String username;

  /// Switches the shell to another tab (1 = watches, 2 = accounts) instead of
  /// pushing a second copy of it.
  final ValueChanged<int> onSelectTab;

  const AdminDashboardTab({
    super.key,
    required this.username,
    required this.onSelectTab,
  });

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  // Created once so rebuilds don't re-subscribe and flash the skeletons.
  late final _user = UserService().currentUserStream();
  late final _users = FirebaseFirestore.instance.collection('users').snapshots();
  late final _watches =
      FirebaseFirestore.instance.collection('watches').snapshots();
  late final _activity = ActivityLogService().recentActivity(limit: 8);

  static const _icons = {
    'user_registered': Icons.person_add_alt_outlined,
    'account_created': Icons.person_add_outlined,
    'account_disabled': Icons.block_outlined,
    'account_enabled': Icons.check_circle_outline,
    'account_deleted': Icons.person_remove_outlined,
    'account_self_deleted': Icons.person_remove_outlined,
    'role_changed': Icons.swap_horiz,
    'watch_added': Icons.watch_outlined,
    'watch_deleted': Icons.delete_outline,
  };

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  String _ago(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}hr ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    final t = ts.toDate();
    return '${t.month}/${t.day}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _user,
          builder: (context, userSnap) {
            final user = userSnap.data?.data();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HomeHeader(
                    username: user?['username'] as String? ?? widget.username,
                    photoUrl: user?['photoUrl'] as String? ?? '',
                    subtitle: 'Manage VirtuWatch.',
                    onAvatarTap: () => _open(const AdminProfileTab()),
                  ),
                  const UpdateAvailableBanner(),
                  _stats(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('List a new watch',
                                  style: AppTheme.serif(size: 22)),
                              const SizedBox(height: 4),
                              Text('Add photos, specs and a 3D model.',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => _open(const MerchantAddWatchScreen()),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12)),
                          child: const Text('Add watch'),
                        ),
                      ],
                    ),
                  ),
                  luxeBand([
                    _action('WATCHES', () => widget.onSelectTab(1)),
                    _action('ACCOUNTS', () => widget.onSelectTab(2)),
                    _action('ADD ACCOUNT',
                        () => _open(const AdminCreateAccountScreen())),
                  ]),
                  const SizedBox(height: 32),
                  luxeHeader('Recent activity'),
                  _feed(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stats() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _users,
        builder: (context, userSnap) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _watches,
          builder: (context, watchSnap) {
            final loading = !userSnap.hasData || !watchSnap.hasData;
            final users = userSnap.data?.docs ?? [];
            String count(Iterable list) => loading ? '–' : '${list.length}';
            return luxeBand([
              _stat('WATCHES', count(watchSnap.data?.docs ?? [])),
              _stat(
                  'ACTIVE USERS',
                  count(users
                      .where((d) => d.data()['accountStatus'] == 'active'))),
              _stat('MERCHANTS',
                  count(users.where((d) => d.data()['role'] == 'merchant'))),
            ]);
          },
        ),
      );

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: AppTheme.serif(size: 28)),
            const SizedBox(height: 2),
            Text(label, style: kLabelStyle.copyWith(fontSize: 10)),
          ],
        ),
      );

  Widget _action(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(label,
                style: kLabelStyle.copyWith(
                    color: AppTheme.textPrimary, fontSize: 10)),
          ),
        ),
      );

  Widget _feed() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _activity,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Column(children: [
              for (var i = 0; i < 5; i++) const _RowSkeleton(),
            ]);
          }
          if (snap.hasError) {
            return Text('Could not load activity.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Text('No recent activity yet.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13));
          }
          return Column(children: [
            for (final doc in docs) _row(doc.data()),
          ]);
        },
      );

  Widget _row(Map<String, dynamic> data) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icons[data['type']] ?? Icons.notifications_none,
                color: AppTheme.textSecondary, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(data['message'] as String? ?? 'Unknown activity',
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Text(_ago(data['timestamp'] as Timestamp?),
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      );
}

/// Placeholder shaped like a row in "Recent activity".
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            SkeletonBox(
              width: 16,
              height: 16,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            SizedBox(width: 12),
            SkeletonBox(width: 180, height: 12),
          ],
        ),
      );
}