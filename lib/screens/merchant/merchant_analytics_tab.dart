import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';

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
            return const Center(child: CircularProgressIndicator());
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
                      Row(
                        children: const [
                          Icon(Icons.info_outline,
                              color: AppTheme.textSecondary, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Coming soon',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Try-on counts, catalog views, and saved-watch counts '
                        'per listing will appear here once AR try-on session '
                        'tracking is built.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                      ),
                    ],
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
