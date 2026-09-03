import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'admin_create_account_screen.dart';
import 'admin_account_management_screen.dart';
import 'admin_watch_management_tab.dart';

class AdminDashboardTab extends StatelessWidget {
  final String username;
  const AdminDashboardTab({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final usersStream = FirebaseFirestore.instance.collection('users').snapshots();
    final watchesStream =
        FirebaseFirestore.instance.collection('watches').snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Row(
              children: [
                Expanded(
                  child: _quickAction(
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickAction(
                    context,
                    icon: Icons.people_outline,
                    label: 'Manage Accounts',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AdminAccountManagementScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.gold),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}