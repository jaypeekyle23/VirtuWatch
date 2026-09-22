import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'admin_create_account_screen.dart';
import 'admin_account_management_screen.dart';
import 'admin_watch_management_tab.dart';
import 'admin_profile_tab.dart';
import '../merchant/merchant_add_watch_screen.dart';
import '../../services/activity_log_service.dart';

class AdminDashboardTab extends StatelessWidget {
  final String username;
  const AdminDashboardTab({super.key, required this.username});

  String _relativeTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}hr ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.toDate().month}/${timestamp.toDate().day}/${timestamp.toDate().year}';
  }

  @override
  Widget build(BuildContext context) {
    final usersStream = FirebaseFirestore.instance.collection('users').snapshots();
    final watchesStream =
        FirebaseFirestore.instance.collection('watches').snapshots();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseAuth.instance.currentUser == null
                    ? null
                    : FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .snapshots(),
                builder: (context, selfSnapshot) {
                  final liveUsername =
                      selfSnapshot.data?.data()?['username'] as String? ??
                          username;
                  final livePhotoUrl =
                      selfSnapshot.data?.data()?['photoUrl'] as String? ?? '';
                  final liveInitials = liveUsername.isEmpty
                      ? '?'
                      : liveUsername
                          .trim()
                          .split(' ')
                          .map((e) => e[0])
                          .take(2)
                          .join()
                          .toUpperCase();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 84,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: -48,
                              top: -48,
                              child: Image.asset(
                                'assets/images/branding/logo.png',
                                height: 180,
                                fit: BoxFit.contain,
                              ),
                            ),
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'ADMIN',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AdminProfileTab(),
                                          ),
                                        );
                                      },
                                      customBorder: const CircleBorder(),
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.redAccent
                                            .withValues(alpha: 0.2),
                                        backgroundImage:
                                            livePhotoUrl.isNotEmpty
                                                ? NetworkImage(livePhotoUrl)
                                                : null,
                                        child: livePhotoUrl.isEmpty
                                            ? Text(
                                                liveInitials,
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'ADMIN PANEL',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Welcome, $liveUsername!',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 22),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'VirtuWatch Administration',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: usersStream,
                builder: (context, userSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: watchesStream,
                    builder: (context, watchSnap) {
                      final users = userSnap.data?.docs ?? [];
                      final watches = watchSnap.data?.docs ?? [];
                      final activeUsers = users
                          .where((d) => d.data()['accountStatus'] == 'active')
                          .length;
                      final merchants = users
                          .where((d) => d.data()['role'] == 'merchant')
                          .length;
                      final savedWatches = users.fold<int>(
                        0,
                        (total, d) =>
                            total +
                            ((d.data()['savedWatches'] as List?)?.length ??
                                0),
                      );

                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  icon: Icons.watch_outlined,
                                  label: 'Total Watches',
                                  value: '${watches.length}',
                                  color: AppTheme.gold,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminWatchManagementTab(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  icon: Icons.person_outline,
                                  label: 'Active Users',
                                  value: '$activeUsers',
                                  color: Colors.greenAccent,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminAccountManagementScreen(
                                          initialFilter: 'Active',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  icon: Icons.storefront_outlined,
                                  label: 'Merchants',
                                  value: '$merchants',
                                  color: Colors.purpleAccent,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminAccountManagementScreen(
                                          initialFilter: 'Merchant',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  icon: Icons.favorite_border,
                                  label: 'Saved Watches',
                                  value: '$savedWatches',
                                  color: Colors.pinkAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _quickAction(
                    context,
                    icon: Icons.add_circle_outline,
                    label: 'Add New Watch',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MerchantAddWatchScreen(),
                        ),
                      );
                    },
                  ),
                  _quickAction(
                    context,
                    icon: Icons.person_add_outlined,
                    label: 'Add Account',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminCreateAccountScreen(),
                        ),
                      );
                    },
                  ),
                  _quickAction(
                    context,
                    icon: Icons.watch_outlined,
                    label: 'Manage Watches',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminWatchManagementTab(),
                        ),
                      );
                    },
                  ),
                  _quickAction(
                    context,
                    icon: Icons.people_outline,
                    label: 'Manage Accounts',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminAccountManagementScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ActivityLogService().recentActivity(limit: 8),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Could not load activity: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'No recent activity yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: docs.asMap().entries.map((entry) {
                        final isLast = entry.key == docs.length - 1;
                        final data = entry.value.data();
                        final type = data['type'] as String? ?? '';
                        final message =
                            data['message'] as String? ?? 'Unknown activity';
                        final timestamp = data['timestamp'] as Timestamp?;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: isLast
                                ? null
                                : const Border(
                                    bottom: BorderSide(color: Color(0x1AFFFFFF)),
                                  ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(_iconForActivityType(type),
                                  color: AppTheme.textSecondary, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  message,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _relativeTime(timestamp),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForActivityType(String type) {
    switch (type) {
      case 'user_registered':
        return Icons.person_add_alt_outlined;
      case 'account_created':
        return Icons.person_add_outlined;
      case 'account_disabled':
        return Icons.block_outlined;
      case 'account_enabled':
        return Icons.check_circle_outline;
      case 'account_deleted':
      case 'account_self_deleted':
        return Icons.person_remove_outlined;
      case 'role_changed':
        return Icons.swap_horiz;
      case 'watch_added':
        return Icons.watch_outlined;
      case 'watch_deleted':
        return Icons.delete_outline;
      default:
        return Icons.circle_notifications_outlined;
    }
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
            ),
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.gold, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}