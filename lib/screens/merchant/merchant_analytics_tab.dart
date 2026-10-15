import 'dart:math' show max, min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../../utils/ar_readiness.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/luxe.dart';
import '../../widgets/skeleton_box.dart';

TextStyle get _muted =>

    TextStyle(color: AppTheme.textSecondary, fontSize: 13);

/// Serif figures side by side, each with a small label under it. With
/// [band], they are centered in ruled cells, like the dashboard stats.
Widget _figures(List<(String, String)> items, {bool band = false}) {
  final cells = [
    for (final (label, value) in items)
      Column(
        crossAxisAlignment:
            band ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTheme.serif(size: 28)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
  ];
  return band
      ? luxeBand([
          for (final c in cells)
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: c),
        ])
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cells) Expanded(child: c)],
        );
}

class MerchantAnalyticsTab extends StatefulWidget {
  const MerchantAnalyticsTab({super.key});

  @override
  State<MerchantAnalyticsTab> createState() => _MerchantAnalyticsTabState();
}

class _MerchantAnalyticsTabState extends State<MerchantAnalyticsTab> {
  // Created once so tab switches don't re-subscribe and flash the skeleton.
  late final _watches = WatchService().myWatches();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Analytics', style: AppTheme.serif(size: 28))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _watches,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _AnalyticsSkeleton();
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No analytics yet. Add a watch to your catalog to see stats here.',
                  textAlign: TextAlign.center,
                  style: _muted,
                ),
              ),
            );
          }
          return _content(docs);
        },
      ),
    );
  }

  Widget _content(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final data = [for (final d in docs) d.data()];
    final listed = data.where((d) => d['listedInCatalog'] == true).length;
    final arReady = data.where(isArReady).length;

    final prices = [
      for (final d in data)
        if (d['price'] is num) (d['price'] as num).toDouble(),
    ];
    final total = prices.fold(0.0, (a, b) => a + b);
    String peso(double? v) => v == null || prices.isEmpty ? '—' : formatPeso(v);

    final styleCounts = <String, int>{};
    for (final d in data) {
      final style = d['styleCategory'] as String? ?? 'Unspecified';
      styleCounts[style] = (styleCounts[style] ?? 0) + 1;
    }
    final styles = styleCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: _muted)),
              Text(value,
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        children: [
          luxeSection(
            'CATALOG',
            _figures([
              ('Watches', '${docs.length}'),
              ('Listed', '$listed'),
              ('Drafts', '${docs.length - listed}'),
              ('AR ready', '$arReady'),
            ]),
          ),
          luxeSection(
            'PRICING',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peso(total), style: AppTheme.serif(size: 34)),
                const SizedBox(height: 2),
                Text('Total inventory value',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                row('Average price',
                    peso(prices.isEmpty ? null : total / prices.length)),
                row('Lowest price',
                    peso(prices.isEmpty ? null : prices.reduce(min))),
                row('Highest price',
                    peso(prices.isEmpty ? null : prices.reduce(max))),
              ],
            ),
          ),
          luxeSection(
            'STYLES',
            Column(
              children: [
                for (final (i, e) in styles.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(e.key,
                                  style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14)),
                            ),
                            Text(
                                '${e.value}  ·  ${(e.value / docs.length * 100).round()}%',
                                style: _muted),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: e.value / docs.length,
                            minHeight: 3,
                            backgroundColor: AppTheme.outlineSoft,
                            valueColor:
                                AlwaysStoppedAnimation(AppTheme.gold),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          luxeSection('ENGAGEMENT', _Engagement(docs)),
        ],
      ),
    );
  }
}

/// Saves and views per watch. Loaded separately from the watch list, and
/// only re-fetched when the set of watches changes.
class _Engagement extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _Engagement(this.docs);

  @override
  State<_Engagement> createState() => _EngagementState();
}

class _EngagementState extends State<_Engagement> {
  late Future<EngagementStats> _stats = _load();

  List<String> _ids(_Engagement w) => [for (final d in w.docs) d.id];

  Future<EngagementStats> _load() =>
      WatchService().fetchEngagementStats(_ids(widget));

  @override
  void didUpdateWidget(_Engagement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_ids(widget), _ids(oldWidget))) _stats = _load();
  }

  /// A watch's name with its saved and viewed columns, right-aligned.
  Widget _line(Widget name, Widget saved, Widget viewed) => Row(
        children: [
          Expanded(child: name),
          for (final cell in [saved, viewed])
            SizedBox(
                width: 44,
                child: Align(alignment: Alignment.centerRight, child: cell)),
        ],
      );

  Widget _count(int n) => Text('$n', style: _muted);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EngagementStats>(
      future: _stats,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SkeletonBox(width: double.infinity, height: 120);
        }
        final stats = snapshot.data;
        if (stats == null) {
          return Text('Could not load engagement data. Try again in a moment.',
              style: _muted);
        }
        if (stats.totalSaves == 0 &&
            stats.viewedCounts.values.every((v) => v == 0)) {
          return Text(
              'No customer activity yet. Saves and views will appear here '
              'once customers start engaging with your catalog.',
              style: _muted);
        }

        final ranked = [...widget.docs]..sort((a, b) =>
            (stats.savedCounts[b.id] ?? 0)
                .compareTo(stats.savedCounts[a.id] ?? 0));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _figures([
              ('Total saves', '${stats.totalSaves}'),
              ('Customers who saved', '${stats.uniqueSaverCount}'),
            ], band: true),
            const SizedBox(height: 20),
            _line(
              const SizedBox.shrink(),
              Icon(Icons.favorite_border,
                  size: 15, color: AppTheme.textSecondary),
              Icon(Icons.visibility_outlined,
                  size: 15, color: AppTheme.textSecondary),
            ),
            for (final d in ranked)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _line(
                  Text(d.data()['name'] as String? ?? 'Unnamed watch',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13)),
                  _count(stats.savedCounts[d.id] ?? 0),
                  _count(stats.viewedCounts[d.id] ?? 0),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Placeholder with the real section labels and boxes where content goes.
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          for (final (label, height) in const [
            ('CATALOG', 44.0),
            ('PRICING', 110.0),
            ('STYLES', 90.0),
          ])
            luxeSection(
                label, SkeletonBox(width: double.infinity, height: height)),
        ],
      ),
    );
  }
}