import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'admin_create_account_screen.dart';
import 'admin_account_management_screen.dart';
import 'admin_watch_management_tab.dart';
import '../merchant/merchant_add_watch_screen.dart';

class AdminDashboardTab extends StatelessWidget {
  final String username;
  const AdminDashboardTab({super.key, required this.username});

  String get _initials {
    if (username.isEmpty) return '?';
    return username.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase();
  }

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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VirtuWatch',
                        style: TextStyle(
                          color: AppTheme.gold,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Text(
                        'ADMIN PANEL',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
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
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                        child: Text(
                          _initials,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Text(
                'Welcome, $username!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 22,
                    ),
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  icon: Icons.person_outline,
                                  label: 'Active Users',
                                  value: '$activeUsers',
                                  color: Colors.greenAccent,
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  icon: Icons.straighten,
                                  label: 'Wrist Scans',
                                  value: '—',
                                  color: AppTheme.textSecondary,
                                  subtitle: 'Coming soon',
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
                stream: usersStream,
                builder: (context, userSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: watchesStream,
                    builder: (context, watchSnap) {
                      if (userSnap.connectionState == ConnectionState.waiting ||
                          watchSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final activities = <_ActivityEntry>[];

                      for (final doc in userSnap.data?.docs ?? []) {
                        final data = doc.data();
                        final createdAt = data['createdAt'] as Timestamp?;
                        if (createdAt == null) continue;
                        final isSelf =
                            doc.id == FirebaseAuth.instance.currentUser?.uid;
                        activities.add(_ActivityEntry(
                          icon: Icons.person_add_alt_outlined,
                          text: isSelf
                              ? 'Your admin account was created'
                              : 'New user registered: ${data['email'] ?? 'unknown'}',
                          timestamp: createdAt,
                        ));
                      }

                      for (final doc in watchSnap.data?.docs ?? []) {
                        final data = doc.data();
                        final createdAt = data['createdAt'] as Timestamp?;
                        if (createdAt == null) continue;
                        final name = data['name'] as String? ?? 'Unnamed Watch';
                        activities.add(_ActivityEntry(
                          icon: Icons.watch_outlined,
                          text: 'Watch added: $name',
                          timestamp: createdAt,
                        ));
                      }

                      activities.sort(
                          (a, b) => b.timestamp.compareTo(a.timestamp));
                      final recent = activities.take(6).toList();

                      if (recent.isEmpty) {
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
                          children: recent.asMap().entries.map((entry) {
                            final isLast = entry.key == recent.length - 1;
                            final activity = entry.value;
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: isLast
                                    ? null
                                    : const Border(
                                        bottom: BorderSide(
                                          color: Color(0x1AFFFFFF),
                                        ),
                                      ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(activity.icon,
                                      color: AppTheme.textSecondary, size: 16),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      activity.text,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _relativeTime(activity.timestamp),
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
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
  }) {
    return Container(
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

class _ActivityEntry {
  final IconData icon;
  final String text;
  final Timestamp timestamp;

  _ActivityEntry({
    required this.icon,
    required this.text,
    required this.timestamp,
  });
}