import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/recommendation_service.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/update_available_banner.dart';
import 'customer_catalog_tab.dart';
import 'watch_detail_screen.dart';
import 'ar_try_on_screen.dart';
import 'recommended_for_you_screen.dart';
import 'wrist_measurement_screen.dart';
import 'outfit_scan_screen.dart';
import 'customer_profile_tab.dart';

/// Height of the "Recently Viewed" / "Recommended for You" horizontal
/// card rows. Sized to fit _HomeWatchCard's fixed-height content block
/// (120-wide image at 1.3 aspect ratio + reserved brand line + a
/// reserved 2-line name box) with a small safety margin — every card
/// renders at exactly this content height, so the row is neither
/// clipping cards nor leaving mismatched blank space under them.
const double _kHomeCardRowHeight = 156;

class CustomerHomeTab extends StatefulWidget {
  final String username;
  const CustomerHomeTab({super.key, required this.username});

  @override
  State<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends State<CustomerHomeTab> {
  final _recommendationService = RecommendationService();

  // Loaded once in initState and cached, same pattern as
  // RecommendedForYouScreen, rather than re-scoring the whole catalog
  // on every rebuild of this tab.
  RecommendationResult? _recommendationResult;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    try {
      final result = await _recommendationService.getRecommendations();
      if (!mounted) return;
      setState(() => _recommendationResult = result);
    } catch (_) {
      // Leave _recommendationResult null on failure — the section below
      // just falls back to its empty state, same as an empty catalog.
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchService = WatchService();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null
          ? null
          : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnapshot) {
        final liveUsername =
            userSnapshot.data?.data()?['username'] as String? ?? widget.username;
        final photoUrl =
            userSnapshot.data?.data()?['photoUrl'] as String? ?? '';
        final initials = liveUsername.isNotEmpty
            ? liveUsername.trim().split(' ').map((e) => e[0]).take(2).join()
            : '?';

        return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRecommendations,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CustomerProfileTab(),
                              ),
                            );
                            // Style preferences/budget may have changed
                            // while in there (or further in, on Edit
                            // Profile), so re-score on return.
                            _loadRecommendations();
                          },
                          customBorder: const CircleBorder(),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.gold,
                            backgroundImage: photoUrl.isNotEmpty
                                ? NetworkImage(photoUrl)
                                : null,
                            child: photoUrl.isEmpty
                                ? Text(
                                    initials.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF0E1A2B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_greeting, $liveUsername!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 22,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Find your perfect timepiece today.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              const UpdateAvailableBanner(),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Try On a Watch Now',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ArTryOnScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            child: const Text('Start AR Try-On'),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: AppTheme.gold,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ArTryOnScreen(),
                            ),
                          );
                        },
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(
                            Icons.view_in_ar,
                            color: Color(0xFF0E1A2B),
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: _quickActionCard(
                      context,
                      icon: Icons.straighten_outlined,
                      label: 'Measure Wrist',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WristMeasurementScreen(),
                          ),
                        );
                        // Wrist width feeds the fit score directly.
                        _loadRecommendations();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quickActionCard(
                      context,
                      icon: Icons.checkroom_outlined,
                      label: 'Outfit Scan',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OutfitScanScreen(),
                          ),
                        );
                        // Outfit colors feed the color score directly.
                        _loadRecommendations();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Builder(
                builder: (context) {
                  final recentIds = (userSnapshot.data
                              ?.data()?['recentlyViewedWatches'] as List?)
                          ?.cast<String>() ??
                      [];
                  if (recentIds.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recently Viewed',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        // whereIn tops out at 30 values, well above the 10
                        // entries recordRecentlyViewed ever stores.
                        future: FirebaseFirestore.instance
                            .collection('watches')
                            .where(FieldPath.documentId, whereIn: recentIds)
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox(
                              height: _kHomeCardRowHeight,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          // Firestore's whereIn doesn't preserve the order
                          // of the IDs given, so re-sort by recentIds
                          // (most-recently-viewed first) here on the client.
                          final byId = {
                            for (final doc in snapshot.data!.docs)
                              doc.id: doc,
                          };
                          final ordered = recentIds
                              .where((id) => byId.containsKey(id))
                              .map((id) => byId[id]!)
                              .toList();
                          if (ordered.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return SizedBox(
                            height: _kHomeCardRowHeight,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: ordered.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final doc = ordered[index];
                                // topCenter so each card sizes to its own
                                // content instead of being stretched to
                                // fill the row's fixed height.
                                return Align(
                                  alignment: Alignment.topCenter,
                                  child: _HomeWatchCard(
                                    watchId: doc.id,
                                    data: doc.data(),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recommended for You',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RecommendedForYouScreen(),
                        ),
                      );
                      // That screen lets you edit style/budget prefs and
                      // clear outfit colors in place, so re-score on return.
                      _loadRecommendations();
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('View All',
                        style: TextStyle(color: AppTheme.gold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final result = _recommendationResult;
                  if (result == null) {
                    // Same height and card shape as the real row below
                    // (_HomeWatchCard), so there's no layout jump once
                    // the actual recommendations come in.
                    return SizedBox(
                      height: _kHomeCardRowHeight,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 4,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) => const Align(
                          alignment: Alignment.topCenter,
                          child: _HomeWatchCardSkeleton(),
                        ),
                      ),
                    );
                  }
                  if (result.recommendations.isEmpty) {
                    return Text(
                      'No watches available yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  }

                  // Already ranked best-match-first by RecommendationService.
                  final preview = result.recommendations.take(4).toList();

                  return SizedBox(
                    height: _kHomeCardRowHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: preview.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final rec = preview[index];
                        return Align(
                          alignment: Alignment.topCenter,
                          child: _HomeWatchCard(
                            watchId: rec.watchId,
                            data: rec.data,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Browse All Watches',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerCatalogTab(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('See All',
                        style: TextStyle(color: AppTheme.gold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: watchService.allListedWatches(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Text(
                      'No watches available yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  }

                  final preview = docs.take(4).toList();
                  // Built row-by-row instead of GridView + a fixed
                  // childAspectRatio: a hardcoded ratio has to guess a
                  // worst-case cell height for the narrowest phone this
                  // app supports, which leaves leftover blank space under
                  // every card on a normal-width phone. Since
                  // _BrowseWatchCard already sizes itself to exactly what
                  // its content needs (mainAxisSize.min throughout),
                  // putting two cards in a Row and letting the Row size
                  // itself to them gives every row its exact natural
                  // height, on any screen width, with no guessing and no
                  // leftover space.
                  final rowCount = (preview.length / 2).ceil();

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rowCount,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, rowIndex) {
                      final firstIndex = rowIndex * 2;
                      final secondIndex = firstIndex + 1;
                      final firstDoc = preview[firstIndex];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _BrowseWatchCard(
                              watchId: firstDoc.id,
                              data: firstDoc.data(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: secondIndex < preview.length
                                ? _BrowseWatchCard(
                                    watchId: preview[secondIndex].id,
                                    data: preview[secondIndex].data(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        ),
      ),
    );
      },
    );
  }

  Widget _quickActionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.gold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeWatchCard extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _HomeWatchCard({required this.watchId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchDetailScreen(watchId: watchId, data: data),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  color: AppTheme.background,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Icon(Icons.watch,
                                size: 30, color: AppTheme.gold),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child:
                              Icon(Icons.watch, size: 30, color: AppTheme.gold),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Always rendered (not `if brand.isNotEmpty`) so this
                  // line's height is reserved consistently — see the
                  // matching comment in customer_catalog_tab.dart's
                  // _WatchCard for why conditionally-included widgets are
                  // what makes cards in the same row end up different
                  // heights.
                  Text(
                    brand.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Fixed-height box sized for 2 lines, so a short 1-line
                  // name doesn't leave this card shorter than its
                  // neighbors.
                  SizedBox(
                    height: 30,
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for [_HomeWatchCard], matching its exact dimensions
/// (120 width, 1.3 aspect-ratio image block, brand + name text lines)
/// so the "Recommended for You" row keeps its shape while
/// [RecommendationResult] is still loading.
class _HomeWatchCardSkeleton extends StatelessWidget {
  const _HomeWatchCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.3,
            child: SkeletonBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 32, height: 8),
                SizedBox(height: 5),
                SkeletonBox(width: 72, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseWatchCard extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _BrowseWatchCard({required this.watchId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final style = data['styleCategory'] as String? ?? '';
    final caseDiameter = data['caseDiameterMm'];
    final imageUrl = data['imageUrl'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchDetailScreen(watchId: watchId, data: data),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  color: AppTheme.background,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Icon(Icons.watch,
                                size: 40, color: AppTheme.gold),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child:
                              Icon(Icons.watch, size: 40, color: AppTheme.gold),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Always rendered so this line's height is reserved
                  // consistently regardless of whether style is set —
                  // see _WatchCard in customer_catalog_tab.dart for why
                  // conditionally-included widgets make cards in the
                  // same grid row end up different heights.
                  Text(
                    style.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  // Fixed-height box sized for 2 lines, so a short name
                  // doesn't leave this card shorter than its neighbors.
                  SizedBox(
                    height: 32,
                    child: Text(
                      brand.isNotEmpty ? '$brand $name' : name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caseDiameter != null ? '${caseDiameter}mm' : '',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 16,
                    child: price != null
                        ? Text(
                            'PHP $price',
                            style: const TextStyle(
                              color: AppTheme.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}