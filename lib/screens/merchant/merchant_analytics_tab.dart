import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeleton_box.dart';

class MerchantAnalyticsTab extends StatelessWidget {
  const MerchantAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final watchService = WatchService();

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: watchService.myWatches(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _AnalyticsSkeleton();
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bar_chart_outlined,
                        size: 48, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      'No analytics yet. Add a watch to your catalog to see stats here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          final total = docs.length;
          final listed =
              docs.where((d) => d.data()['listedInCatalog'] as bool? ?? false).length;
          final draft = total - listed;
          final arReady =
              docs.where((d) => d.data()['has3DModel'] as bool? ?? false).length;

          final prices = docs
              .map((d) => (d.data()['price'] as num?)?.toDouble())
              .whereType<double>()
              .toList();
          final avgPrice = prices.isEmpty
              ? null
              : prices.reduce((a, b) => a + b) / prices.length;
          final totalValue =
              prices.isEmpty ? null : prices.reduce((a, b) => a + b);
          final minPrice = prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
          final maxPrice = prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b);

          final styleCounts = <String, int>{};
          for (final doc in docs) {
            final style = doc.data()['styleCategory'] as String? ?? 'Unspecified';
            styleCounts[style] = (styleCounts[style] ?? 0) + 1;
          }
          final sortedStyles = styleCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          String currencyFormat(double value) =>
              'PHP ${value.toStringAsFixed(0).replaceAllMapped(
                    RegExp(r'\B(?=(\d{3})+(?!\d))'),
                    (m) => ',',
                  )}';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catalog Overview',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        label: 'Total Watches',
                        value: '$total',
                        color: AppTheme.gold,
                        icon: Icons.watch_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        label: 'Listed / Draft',
                        value: '$listed / $draft',
                        color: Colors.greenAccent,
                        icon: Icons.visibility_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        label: 'AR Ready',
                        value: '$arReady',
                        color: AppTheme.gold,
                        icon: Icons.view_in_ar_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        label: 'Total Inventory Value',
                        value: totalValue != null
                            ? currencyFormat(totalValue)
                            : '—',
                        color: Colors.purpleAccent,
                        icon: Icons.payments_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text(
                  'Pricing',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _priceRow('Average Price',
                          avgPrice != null ? currencyFormat(avgPrice) : '—'),
                      _priceRow('Lowest Price',
                          minPrice != null ? currencyFormat(minPrice) : '—'),
                      _priceRow('Highest Price',
                          maxPrice != null ? currencyFormat(maxPrice) : '—',
                          isLast: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Style Breakdown',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: sortedStyles.asMap().entries.map((entry) {
                      final isLast = entry.key == sortedStyles.length - 1;
                      final style = entry.value.key;
                      final count = entry.value.value;
                      final fraction = count / total;
                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  style,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '$count (${(fraction * 100).toStringAsFixed(0)}%)',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 6,
                                backgroundColor: AppTheme.background,
                                valueColor: const AlwaysStoppedAnimation(AppTheme.gold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Customer Engagement',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<EngagementStats>(
                  future: watchService
                      .fetchEngagementStats(docs.map((d) => d.id).toList()),
                  builder: (context, statsSnapshot) {
                    if (statsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const _EngagementSkeleton();
                    }

                    final stats = statsSnapshot.data;
                    if (stats == null) {
                      return _engagementInfoCard(
                        icon: Icons.error_outline,
                        title: 'Could not load engagement data',
                        body: 'Pull to refresh or try again in a moment.',
                      );
                    }

                    if (stats.totalSaves == 0) {
                      return _engagementInfoCard(
                        icon: Icons.info_outline,
                        title: 'No customer activity yet',
                        body:
                            'Saved-watch and recently-viewed counts will '
                            'appear here once customers start engaging '
                            'with your catalog.',
                      );
                    }

                    // Rank the merchant's own watches by saves, most first,
                    // for both the highlight and the breakdown list below.
                    final ranked = [...docs]..sort((a, b) =>
                        (stats.savedCounts[b.id] ?? 0)
                            .compareTo(stats.savedCounts[a.id] ?? 0));
                    final topDoc = ranked.first;
                    final topName =
                        topDoc.data()['name'] as String? ?? 'Unnamed watch';
                    final topSaves = stats.savedCounts[topDoc.id] ?? 0;

                    // Size each count column to its widest number (about
                    // 8px per digit at this font size) so the icons line up
                    // without leaving empty space at the row's right edge.
                    var maxSaved = 0;
                    var maxViewed = 0;
                    for (final d in ranked) {
                      final sv = stats.savedCounts[d.id] ?? 0;
                      final vw = stats.viewedCounts[d.id] ?? 0;
                      if (sv > maxSaved) maxSaved = sv;
                      if (vw > maxViewed) maxViewed = vw;
                    }
                    final savedColWidth = maxSaved.toString().length * 8.0;
                    final viewedColWidth = maxViewed.toString().length * 8.0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _statCard(
                                label: 'Total Saves',
                                value: '${stats.totalSaves}',
                                color: Colors.pinkAccent,
                                icon: Icons.favorite_outline,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _statCard(
                                label: 'Customers Reached',
                                value: '${stats.uniqueSaverCount}',
                                color: Colors.lightBlueAccent,
                                icon: Icons.people_outline,
                              ),
                            ),
                          ],
                        ),
                        if (topSaves > 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star_outline,
                                    color: AppTheme.gold, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 13,
                                      ),
                                      children: [
                                        const TextSpan(text: 'Most saved: '),
                                        TextSpan(
                                          text: topName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        TextSpan(
                                          text:
                                              ' · $topSaves ${topSaves == 1 ? 'save' : 'saves'}',
                                          style: const TextStyle(
                                              color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
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
                              for (final entry in ranked.asMap().entries)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: entry.key == ranked.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  child: _engagementRow(
                                    name: entry.value.data()['name']
                                            as String? ??
                                        'Unnamed watch',
                                    saved: stats.savedCounts[entry.value.id] ??
                                        0,
                                    viewed:
                                        stats.viewedCounts[entry.value.id] ??
                                            0,
                                    savedWidth: savedColWidth,
                                    viewedWidth: viewedColWidth,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Heart = customers who have this saved. Eye = '
                          'distinct customers who have viewed it.',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              height: 1.4),
                        ),
                      ],
                    );
                  },
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
    required IconData icon,
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
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _engagementInfoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
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
          Row(
            children: [
              Icon(icon, color: AppTheme.textSecondary, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Left-aligned count in a column of the given [width], so every row's
  /// icons line up regardless of how many digits the numbers have.
  Widget _countText(String value, double width) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _engagementRow({
    required String name,
    required int saved,
    required int viewed,
    required double savedWidth,
    required double viewedWidth,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(Icons.favorite, color: Colors.pinkAccent.withValues(alpha: 0.8), size: 13),
        const SizedBox(width: 4),
        _countText('$saved', savedWidth),
        const SizedBox(width: 8),
        Icon(Icons.remove_red_eye_outlined,
            color: AppTheme.textSecondary, size: 13),
        const SizedBox(width: 4),
        _countText('$viewed', viewedWidth),
      ],
    );
  }

  Widget _priceRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-page placeholder for the analytics screen: the four sections
/// (overview, pricing, style breakdown, engagement) with the same headings,
/// card surfaces and spacing as the real page.
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  static Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  static Widget _title() => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: SkeletonBox(width: 130, height: 15),
      );

  static Widget _statRow() => const Row(
        children: [
          Expanded(child: _StatCardSkeleton()),
          SizedBox(width: 10),
          Expanded(child: _StatCardSkeleton()),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(),
          _statRow(),
          const SizedBox(height: 10),
          _statRow(),
          const SizedBox(height: 24),
          _title(),
          _card(
            Column(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonBox(width: 90, height: 13),
                      SkeletonBox(width: 70, height: 13),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _title(),
          _card(
            Column(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: EdgeInsets.only(bottom: i == 2 ? 0 : 14),
                  child: const Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SkeletonBox(width: 90, height: 13),
                          SkeletonBox(width: 50, height: 12),
                        ],
                      ),
                      SizedBox(height: 6),
                      SkeletonBox(width: double.infinity, height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _title(),
          const _EngagementSkeleton(),
        ],
      ),
    );
  }
}

/// Placeholder for the "Customer Engagement" content: a pair of stat cards
/// and a card of per-watch rows. Also used on its own while the engagement
/// stats load after the rest of the page is already showing.
class _EngagementSkeleton extends StatelessWidget {
  const _EngagementSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: _StatCardSkeleton()),
            SizedBox(width: 10),
            Expanded(child: _StatCardSkeleton()),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: List.generate(
              3,
              (i) => Padding(
                padding: EdgeInsets.only(bottom: i == 2 ? 0 : 12),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonBox(width: 140, height: 13),
                    SkeletonBox(width: 60, height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Placeholder for [MerchantAnalyticsTab._statCard]: icon, label and value.
class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: 18,
            height: 18,
            borderRadius: BorderRadius.all(Radius.circular(9)),
          ),
          SizedBox(height: 8),
          SkeletonBox(width: 70, height: 11),
          SizedBox(height: 4),
          SkeletonBox(width: 50, height: 16),
        ],
      ),
    );
  }
}