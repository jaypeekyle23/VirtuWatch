import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import 'merchant_add_watch_screen.dart';
import 'merchant_catalog_tab.dart';
import 'merchant_analytics_tab.dart';
import 'merchant_edit_watch_screen.dart';
import 'merchant_profile_tab.dart';

class MerchantDashboardTab extends StatelessWidget {
  final String username;
  const MerchantDashboardTab({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final watchService = WatchService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseAuth.instance.currentUser == null
                    ? null
                    : FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .snapshots(),
                builder: (context, userSnapshot) {
                  final liveUsername =
                      userSnapshot.data?.data()?['username'] as String? ??
                          username;
                  final initials = liveUsername.isEmpty
                      ? '?'
                      : liveUsername
                          .trim()
                          .split(' ')
                          .map((e) => e[0])
                          .take(2)
                          .join()
                          .toUpperCase();

                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MerchantProfileTab(),
                        ),
                      );
                    },
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.greenAccent.withValues(alpha: 0.2),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: watchService.myWatches(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final totalWatches = docs.length;
          final arReadyCount =
              docs.where((d) => d.data()['has3DModel'] as bool? ?? false).length;
          final latestWatches = docs.take(3).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
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
                  builder: (context, userSnapshot) {
                    final liveUsername =
                        userSnapshot.data?.data()?['username'] as String? ??
                            username;
                    return Text(
                      'Welcome, $liveUsername!',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontSize: 22),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your VirtuWatch catalog',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        label: 'Watches',
                        value: '$totalWatches',
                        color: AppTheme.gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        label: 'AR Ready',
                        value: '$arReadyCount',
                        color: Colors.greenAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        label: 'Try-Ons',
                        value: '—',
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
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
                    _quickActionButton(
                      context,
                      icon: Icons.add_circle_outline,
                      label: 'Add Watch',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MerchantAddWatchScreen(),
                          ),
                        );
                      },
                    ),
                    _quickActionButton(
                      context,
                      icon: Icons.view_in_ar_outlined,
                      label: 'Upload 3D Model',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('3D model upload coming soon'),
                          ),
                        );
                      },
                    ),
                    _quickActionButton(
                      context,
                      icon: Icons.list_alt_outlined,
                      label: 'My Catalog',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MerchantCatalogTab(),
                          ),
                        );
                      },
                    ),
                    _quickActionButton(
                      context,
                      icon: Icons.bar_chart_outlined,
                      label: 'Analytics',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MerchantAnalyticsTab(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text(
                  'My Latest Watches',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (latestWatches.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'No watches yet. Tap "Add Watch" to list your first one.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  ...latestWatches.map((doc) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _latestWatchTile(context, doc.id, doc.data()),
                    );
                  }),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gold,
                      side: const BorderSide(color: AppTheme.gold),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MerchantCatalogTab(),
                        ),
                      );
                    },
                    child: const Text('View Full Catalog'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton(
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

  Widget _latestWatchTile(
      BuildContext context, String watchId, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final listed = data['listedInCatalog'] as bool? ?? false;
    final caseDiameter = data['caseDiameterMm'];
    final bandWidth = data['bandWidthMm'];

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MerchantEditWatchScreen(watchId: watchId, data: data),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.watch, color: AppTheme.gold, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _miniBadge(
                        listed ? 'ACTIVE' : 'DRAFT',
                        listed ? Colors.greenAccent : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      if (bandWidth != null || caseDiameter != null)
                        Text(
                          '${caseDiameter ?? '—'}mm lug',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}