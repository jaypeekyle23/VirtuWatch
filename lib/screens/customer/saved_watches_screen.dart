import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';
import '../../widgets/watch_tile.dart';

class SavedWatchesScreen extends StatefulWidget {
  const SavedWatchesScreen({super.key});

  @override
  State<SavedWatchesScreen> createState() => _SavedWatchesScreenState();
}

class _SavedWatchesScreenState extends State<SavedWatchesScreen> {
  final _userService = UserService();

  // Created once. A new stream on every build made the StreamBuilder
  // resubscribe and flash placeholders over the grid, which also removed
  // the photos a Hero animation needs to return to.
  late final _userStream = _userService.currentUserStream();

  // Keeps photo Hero tags unique to this copy of the screen.
  late final String _heroScope = 'saved-$hashCode';

  // Rebuilding creates a fresh Future.wait(...) below, which re-fetches the
  // latest watch data (price, listing status, etc.) for everything saved.
  Future<void> _handleRefresh() async => setState(() {});

  Widget _list(List<Widget> children, {bool loading = false}) => ListView(
        physics: loading
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: children,
      );

  Widget _message(String title, String text, {bool error = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            Text(title,
                textAlign: TextAlign.center, style: AppTheme.serif(size: 26)),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: error ? Colors.redAccent : AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

  List<Widget> _skeletonRows(int count) => watchGridRows(
      List<Widget>.filled(count, const WatchTileSkeleton(showPrice: true)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Watches', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userStream,
          builder: (context, userSnapshot) {
            if (userSnapshot.hasError) {
              return _list([
                _message('Something went wrong',
                    'Error loading saved watches: ${userSnapshot.error}',
                    error: true),
              ]);
            }
            if (!userSnapshot.hasData) {
              // The saved count isn't known yet, so show a typical screenful.
              return _list(_skeletonRows(6), loading: true);
            }

            final savedIds =
                (userSnapshot.data?.data()?['savedWatches'] as List?)
                        ?.cast<String>() ??
                    [];
            if (savedIds.isEmpty) {
              return _list([
                _message('No saved watches yet',
                    'Tap the heart on a watch to save it here.'),
              ]);
            }

            return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
              future: Future.wait([
                for (final id in savedIds)
                  FirebaseFirestore.instance.collection('watches').doc(id).get(),
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _list([
                    _message('Something went wrong',
                        'Error loading saved watches: ${snapshot.error}',
                        error: true),
                  ]);
                }
                // Only show placeholders when there is nothing to show yet.
                // A refetch keeps the current grid on screen instead of
                // flashing it away.
                if (!snapshot.hasData) {
                  return _list(
                    _skeletonRows(savedIds.length < 8 ? savedIds.length : 8),
                    loading: true,
                  );
                }

                final docs = snapshot.data!.where((d) => d.exists).toList();
                if (docs.isEmpty) {
                  return _list([
                    _message('Nothing here',
                        'Your saved watches are no longer available.'),
                  ]);
                }

                return _list([
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${docs.length} ${docs.length == 1 ? 'WATCH' : 'WATCHES'}',
                      style: kLabelStyle,
                    ),
                  ),
                  ...watchGridRows([
                    for (final doc in docs)
                      WatchTile(
                        watchId: doc.id,
                        data: doc.data()!,
                        heroScope: _heroScope,
                        showPrice: true,
                      ),
                  ]),
                ]);
              },
            );
          },
        ),
      ),
    );
  }
}