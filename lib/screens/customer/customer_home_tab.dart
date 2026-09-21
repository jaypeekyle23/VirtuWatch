import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/recommendation_service.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import 'customer_catalog_tab.dart';
import 'watch_detail_screen.dart';
import 'ar_try_on_screen.dart';
import 'recommended_for_you_screen.dart';
import 'wrist_measurement_screen.dart';
import 'outfit_scan_screen.dart';
import 'customer_profile_tab.dart';

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
                              height: 180,
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
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: ordered.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final doc = ordered[index];
                                return _HomeWatchCard(
                                  watchId: doc.id,
                                  data: doc.data(),
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
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
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
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: preview.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final rec = preview[index];
                        return _HomeWatchCard(
                          watchId: rec.watchId,
                          data: rec.data,
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

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.6,
                    ),
                    itemCount: preview.length,
                    itemBuilder: (context, index) {
                      final doc = preview[index];
                      final data = doc.data();
                      return _BrowseWatchCard(watchId: doc.id, data: data);
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
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  if (style.isNotEmpty)
                    Text(
                      style.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 1),
                  Text(
                    brand.isNotEmpty ? '$brand $name' : name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (caseDiameter != null)
                    Text(
                      '${caseDiameter}mm',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (price != null)
                    Text(
                      'PHP $price',
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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