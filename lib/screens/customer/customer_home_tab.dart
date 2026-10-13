import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/recommendation_service.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/update_available_banner.dart';
import '../../widgets/watch_tile.dart';
import 'ar_try_on_screen.dart';
import 'customer_catalog_tab.dart';
import 'customer_profile_tab.dart';
import 'outfit_scan_screen.dart';
import 'recommended_for_you_screen.dart';
import 'wrist_measurement_screen.dart';

/// Size of the horizontal watch rows ("Recently viewed" and "Recommended
/// for you"). Each tile is a card: a square photo, then padded brand and
/// reserved 2-line name lines (about 198 tall), plus a small safety margin,
/// so the row neither clips tiles nor leaves uneven blank space under them.
const double _kHomeCardWidth = 132;
const double _kHomeCardRowHeight = 204;

class CustomerHomeTab extends StatefulWidget {
  final String username;
  const CustomerHomeTab({super.key, required this.username});

  @override
  State<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends State<CustomerHomeTab> {
  final _recommendationService = RecommendationService();
  final _watchService = WatchService();

  // Kept up to date by a live listener (see initState), so it re-scores by
  // itself whenever wrist width, outfit colors, style or budget change,
  // instead of re-scoring the whole catalog on every rebuild.
  RecommendationResult? _recommendationResult;
  StreamSubscription<RecommendationResult>? _recommendationSub;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void initState() {
    super.initState();
    _recommendationSub =
        _recommendationService.watchRecommendations().listen(
      (result) {
        if (!mounted) return;
        setState(() => _recommendationResult = result);
      },
      // Leave the last good result in place on error. The section falls
      // back to its empty state if there never was one.
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _recommendationSub?.cancel();
    super.dispose();
  }

  /// Manual one-time refresh, used by pull to refresh as a backup to the
  /// live listener.
  Future<void> _loadRecommendations() async {
    try {
      final result = await _recommendationService.getRecommendations();
      if (!mounted) return;
      setState(() => _recommendationResult = result);
    } catch (_) {
      // Leave the result null on failure. The section falls back to its
      // empty state, same as an empty catalog.
    }
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null
          ? null
          : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data();
        final username = userData?['username'] as String? ?? widget.username;
        final photoUrl = userData?['photoUrl'] as String? ?? '';
        final recentIds =
            (userData?['recentlyViewedWatches'] as List?)?.cast<String>() ?? [];
        final initials = username
            .trim()
            .split(' ')
            .where((e) => e.isNotEmpty)
            .map((e) => e[0])
            .take(2)
            .join()
            .toUpperCase();

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadRecommendations,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                child: Column(
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
                              child: InkWell(
                                onTap: () =>
                                    _open(const CustomerProfileTab()),
                                customBorder: const CircleBorder(),
                                child: Container(
                                  padding: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: CircleAvatar(
                                    radius: 17,
                                    backgroundColor: AppTheme.surface,
                                    backgroundImage: photoUrl.isNotEmpty
                                        ? NetworkPhoto.provider(photoUrl)
                                        : null,
                                    child: photoUrl.isEmpty
                                        ? Text(initials.isEmpty ? '?' : initials,
                                            style: AppTheme.serif(size: 16))
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('$_greeting,\n$username',
                        style: AppTheme.serif(size: 32).copyWith(height: 1.1)),
                    const SizedBox(height: 8),
                    const Text('Find your perfect timepiece today.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 24),
                    const UpdateAvailableBanner(),

                    Container(
                      decoration: kTopRule,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Try on a watch',
                                    style: AppTheme.serif(size: 22)),
                                const SizedBox(height: 4),
                                const Text('See how a watch looks on your wrist.',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _open(const ArTryOnScreen()),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                            child: const Text('Start AR'),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: AppTheme.hairline),
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _action(
                                'MEASURE WRIST',
                                () => _open(
                                    const WristMeasurementScreen()),
                              ),
                            ),
                            const VerticalDivider(
                                width: 1, color: AppTheme.hairline),
                            Expanded(
                              child: _action(
                                'OUTFIT SCAN',
                                () =>
                                    _open(const OutfitScanScreen()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (recentIds.isNotEmpty) ...[
                      _header('Recently viewed'),
                      _recentRow(recentIds),
                      const SizedBox(height: 32),
                    ],

                    _header(
                      'Recommended for you',
                      action: 'VIEW ALL',
                      onTap: () =>
                          _open(const RecommendedForYouScreen()),
                    ),
                    _recommendedRow(),
                    const SizedBox(height: 32),

                    _header(
                      'Browse all watches',
                      action: 'SEE ALL',
                      onTap: () => _open(const CustomerCatalogTab()),
                    ),
                    _browseGrid(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(String title, {String? action, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: AppTheme.serif(size: 24)),
          const Spacer(),
          if (action != null)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(action,
                    style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(label,
                style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
          ),
        ),
      );

  Widget _emptyText() => const Text('No watches available yet.',
      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13));

  /// A horizontally scrolling row of tiles. While [loading] it shows
  /// skeletons of the same shape and doesn't scroll.
  Widget _tileRow(List<Widget> tiles, {bool loading = false}) => SizedBox(
        height: _kHomeCardRowHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: loading ? const NeverScrollableScrollPhysics() : null,
          itemCount: tiles.length,
          separatorBuilder: (context, index) => const SizedBox(width: 14),
          // topCenter so each tile sizes to its own content instead of
          // stretching to the row's fixed height.
          itemBuilder: (context, index) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: _kHomeCardWidth, child: tiles[index]),
          ),
        ),
      );

  Widget _grid(List<Widget> tiles) => Column(children: watchGridRows(tiles));

  Widget _recentRow(List<String> recentIds) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // whereIn tops out at 30 values, well above the 10 entries
      // recordRecentlyViewed ever stores.
      future: FirebaseFirestore.instance
          .collection('watches')
          .where(FieldPath.documentId, whereIn: recentIds)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _tileRow([
            for (var i = 0; i < (recentIds.length < 4 ? recentIds.length : 4); i++)
              const WatchTileSkeleton(),
          ], loading: true);
        }
        // whereIn doesn't preserve the order of the IDs given, so re-sort
        // by recentIds (most recently viewed first) on the client.
        final byId = {for (final doc in snapshot.data!.docs) doc.id: doc.data()};
        final ordered = [
          for (final id in recentIds)
            if (byId.containsKey(id)) id,
        ];
        if (ordered.isEmpty) return const SizedBox.shrink();
        return _tileRow([
          for (final id in ordered)
            WatchTile(watchId: id, data: byId[id]!, heroScope: 'home-recent'),
        ]);
      },
    );
  }

  Widget _recommendedRow() {
    final result = _recommendationResult;
    if (result == null) {
      return _tileRow(List<Widget>.filled(4, const WatchTileSkeleton()),
          loading: true);
    }
    if (result.recommendations.isEmpty) return _emptyText();
    // Already ranked best match first by RecommendationService.
    return _tileRow([
      for (final rec in result.recommendations.take(4))
        WatchTile(
            watchId: rec.watchId, data: rec.data, heroScope: 'home-recommended'),
    ]);
  }

  Widget _browseGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _watchService.allListedWatches(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _grid(
              List<Widget>.filled(4, const WatchTileSkeleton(showPrice: true)));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _emptyText();
        return _grid([
          for (final doc in docs.take(4))
            WatchTile(
              watchId: doc.id,
              data: doc.data(),
              heroScope: 'home-browse',
              showPrice: true,
            ),
        ]);
      },
    );
  }
}