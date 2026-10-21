import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../utils/ar_readiness.dart';
import '../../services/user_service.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/stock.dart';
import '../../widgets/home_header.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/stock_badge.dart';
import '../../widgets/update_available_banner.dart';
import 'merchant_add_watch_screen.dart';
import 'merchant_edit_watch_screen.dart';
import 'merchant_profile_tab.dart';

class MerchantDashboardTab extends StatefulWidget {
  final String username;

  /// Switches the shell to another tab (1 = catalog, 2 = analytics) instead of
  /// pushing a second copy of it, which would duplicate that tab's Hero photos.
  final ValueChanged<int> onSelectTab;

  const MerchantDashboardTab({
    super.key,
    required this.username,
    required this.onSelectTab,
  });

  @override
  State<MerchantDashboardTab> createState() => _MerchantDashboardTabState();
}

class _MerchantDashboardTabState extends State<MerchantDashboardTab> {
  // Created once so rebuilds don't re-subscribe and flash the skeletons.
  late final _watches = WatchService().myWatches();
  late final _user = UserService().currentUserStream();

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

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
                    subtitle: 'Manage your catalog.',
                    onAvatarTap: () => _open(const MerchantProfileTab()),
                  ),
                  const UpdateAvailableBanner(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _watches,
                    builder: (context, snap) => _content(snap),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _content(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
    final loading = snap.connectionState == ConnectionState.waiting;
    final docs = snap.data?.docs ?? [];
    String count(bool Function(Map<String, dynamic>) test) =>
        loading ? '–' : '${docs.where((d) => test(d.data())).length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        luxeBand([
          _stat('WATCHES', count((_) => true)),
          _stat('LISTED', count((d) => d['listedInCatalog'] == true)),
          _stat('AR READY', count(isArReady)),
        ]),
        if (!loading) _stockAlerts(docs),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('List a new watch', style: AppTheme.serif(size: 22)),
                    const SizedBox(height: 4),
                    Text('Add photos, specs and a 3D model.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _open(const MerchantAddWatchScreen()),
                style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                child: const Text('Add watch'),
              ),
            ],
          ),
        ),
        luxeBand([
          _action('MY CATALOG', 1),
          _action('ANALYTICS', 2),
        ]),
        const SizedBox(height: 32),
        luxeHeader('Latest watches',
            action: 'VIEW ALL', onTap: () => widget.onSelectTab(1)),
        if (loading)
          for (var i = 0; i < 3; i++) const _RowSkeleton()
        else if (docs.isEmpty)
          Text('No watches yet. Add your first listing above.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
        else
          for (final doc in docs.take(3)) _row(doc.id, doc.data()),
      ],
    );
  }

  /// Stock alerts: shown only while some watch is out of stock or running
  /// low. Lists the most urgent few; tapping one opens the stock dialog so a
  /// restock is two taps. VIEW ALL goes to the catalog tab.
  Widget _stockAlerts(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final flagged = docs.where((d) => needsStockAttention(d.data())).toList()
      ..sort((a, b) => compareByStockUrgency(a.data(), b.data()));
    if (flagged.isEmpty) return const SizedBox.shrink();
    final counts = stockAlertCounts(flagged.map((d) => d.data()));
    const maxShown = 4;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          luxeHeader('Stock alerts',
              action: 'VIEW ALL', onTap: () => widget.onSelectTab(1)),
          Text(
            [
              if (counts.out > 0) '${counts.out} out of stock',
              if (counts.low > 0) '${counts.low} running low',
            ].join(', '),
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final doc in flagged.take(maxShown))
            _alertRow(doc.id, doc.data()),
          if (flagged.length > maxShown)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('+ ${flagged.length - maxShown} more in My Catalog',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _alertRow(String watchId, Map<String, dynamic> data) {
    final out = isOutOfStock(data);
    final color = out ? Colors.redAccent : Colors.orangeAccent;
    return InkWell(
      onTap: () => showStockDialog(context, watchId: watchId, data: data),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.hairline)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(data['name'] as String? ?? 'Unnamed Watch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 12),
            Text(merchantStockLabel(data) ?? '',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('UPDATE',
                style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: AppTheme.serif(size: 28)),
            const SizedBox(height: 2),
            Text(label, style: kLabelStyle),
          ],
        ),
      );

  Widget _action(String label, int tab) => InkWell(
        onTap: () => widget.onSelectTab(tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(label,
                style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
          ),
        ),
      );

  Widget _row(String watchId, Map<String, dynamic> data) {
    final imageUrl = data['imageUrl'] as String? ?? '';
    final brand = data['brand'] as String? ?? '';
    final listed = data['listedInCatalog'] as bool? ?? false;
    final price = data['price'];
    final size = data['caseDiameterMm'];
    final details = [
      if (price is num) formatPeso(price),
      if (size != null) '${size}mm',
    ].join('  ·  ');
    final fallback = Center(
      child: Icon(Icons.watch, size: 22, color: AppTheme.textSecondary),
    );

    return InkWell(
      onTap: () =>
          _open(MerchantEditWatchScreen(watchId: watchId, data: data)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.hairline)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: imageUrl.isEmpty
                  ? fallback
                  : NetworkPhoto(url: imageUrl, errorWidget: fallback),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(brand.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                            letterSpacing: 1.2)),
                  Text(data['name'] as String? ?? 'Unnamed Watch',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  if (details.isNotEmpty)
                    Text(details,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(listed ? 'LISTED' : 'DRAFT',
                style: kLabelStyle.copyWith(
                    color: listed
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like a row in "Latest watches".
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SkeletonBox(
              width: 52,
              height: 52,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 50, height: 9),
                SizedBox(height: 6),
                SkeletonBox(width: 130, height: 13),
              ],
            ),
          ],
        ),
      );
}