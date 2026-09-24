import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import 'watch_detail_screen.dart';

class SavedWatchesScreen extends StatefulWidget {
  const SavedWatchesScreen({super.key});

  @override
  State<SavedWatchesScreen> createState() => _SavedWatchesScreenState();
}

class _SavedWatchesScreenState extends State<SavedWatchesScreen> {
  final _userService = UserService();

  Future<void> _handleRefresh() async {
    // Rebuilding creates a fresh Future.wait(...) call below, which
    // re-fetches the latest watch data (price, listing status, etc.)
    // for everything currently saved.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Watches')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userService.currentUserStream(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final savedIds = (userSnapshot.data?.data()?['savedWatches']
                      as List?)
                  ?.cast<String>() ??
              [];

          if (savedIds.isEmpty) {
            return RefreshIndicator(
              color: AppTheme.gold,
              onRefresh: _handleRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite_border,
                            size: 48, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'No saved watches yet.\nTap the heart on a watch to save it here.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
            future: Future.wait(
              savedIds.map(
                (id) => FirebaseFirestore.instance
                    .collection('watches')
                    .doc(id)
                    .get(),
              ),
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return RefreshIndicator(
                  color: AppTheme.gold,
                  onRefresh: _handleRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: Text(
                          'Error loading saved watches: ${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final docs = (snapshot.data ?? [])
                  .where((doc) => doc.exists)
                  .toList();

              if (docs.isEmpty) {
                return RefreshIndicator(
                  color: AppTheme.gold,
                  onRefresh: _handleRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: Text(
                          'Your saved watches are no longer available.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Built row-by-row instead of GridView + a fixed
              // childAspectRatio: a hardcoded ratio has to guess a
              // worst-case cell height for the narrowest phone this app
              // supports, which leaves leftover blank space under every
              // card on a normal-width phone. Since _SavedWatchCard
              // already sizes itself to exactly what its content needs
              // (mainAxisSize.min throughout), putting two cards in a Row
              // and letting the Row size itself to them gives every row
              // its exact natural height, on any screen width, with no
              // guessing and no leftover space.
              final rowCount = (docs.length / 2).ceil();

              return RefreshIndicator(
                color: AppTheme.gold,
                onRefresh: _handleRefresh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16, top: 12),
                    itemCount: rowCount,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, rowIndex) {
                      final firstIndex = rowIndex * 2;
                      final secondIndex = firstIndex + 1;
                      final firstDoc = docs[firstIndex];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _SavedWatchCard(
                              watchId: firstDoc.id,
                              data: firstDoc.data()!,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: secondIndex < docs.length
                                ? _SavedWatchCard(
                                    watchId: docs[secondIndex].id,
                                    data: docs[secondIndex].data()!,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SavedWatchCard extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _SavedWatchCard({required this.watchId, required this.data});

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
                  // consistently regardless of whether brand is set —
                  // see _WatchCard in customer_catalog_tab.dart for why
                  // conditionally-included widgets make cards in the
                  // same grid row end up different heights.
                  Text(
                    brand.toUpperCase(),
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
                      name,
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
                    [
                      if (caseDiameter != null) '${caseDiameter}mm',
                      if (style.isNotEmpty) style,
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
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