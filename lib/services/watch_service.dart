import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'activity_log_service.dart';

class WatchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _activityLog = ActivityLogService();

  CollectionReference<Map<String, dynamic>> get _watches =>
      _firestore.collection('watches');

  /// Creates a new watch listing. Normally owned by the currently logged-in
  /// merchant; an admin can pass [merchantIdOverride] to assign the new
  /// listing to a specific merchant account instead of themselves.
  Future<void> addWatch(Map<String, dynamic> data, {String? merchantIdOverride}) async {
    final uid = merchantIdOverride ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'You must be logged in to add a watch.';

    await _watches.add({
      ...data,
      'merchantId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final name = data['name'] as String? ?? 'Unnamed watch';
    final brand = data['brand'] as String? ?? '';
    await _activityLog.log(
      'watch_added',
      'Watch added: ${brand.isNotEmpty ? '$brand $name' : name}',
    );
  }

  /// Updates an existing watch listing.
  Future<void> updateWatch(String watchId, Map<String, dynamic> data) async {
    await _watches.doc(watchId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a watch listing. [watchLabel] is an optional human-readable
  /// name for the activity log message; falls back to the watch's ID.
  ///
  /// Also strips the watch's ID out of every customer's `savedWatches` and
  /// `recentlyViewedWatches` lists, so a deleted watch doesn't linger as a
  /// dangling reference (e.g. a photo-less thumbnail on the profile tab).
  Future<void> deleteWatch(String watchId, {String? watchLabel}) async {
    final engagementRef = _watches.doc(watchId).collection('engagement').doc('summary');
    // Read this BEFORE deleting anything: it's the only place a merchant
    // (not just an admin) is allowed to learn which customers reference
    // this watch — see firestore.rules. Firestore doesn't cascade-delete
    // subcollections, so the summary doc is removed explicitly below too.
    final engagementDoc = await engagementRef.get();
    final saverIds = (engagementDoc.data()?['saverIds'] as List?)?.cast<String>() ?? const [];
    final viewerIds = (engagementDoc.data()?['viewerIds'] as List?)?.cast<String>() ?? const [];
    final affectedUserIds = {...saverIds, ...viewerIds};

    await _watches.doc(watchId).delete();
    await engagementRef.delete();
    await _removeWatchReferences(watchId, affectedUserIds);
    await _activityLog.log(
      'watch_deleted',
      'Watch deleted: ${watchLabel ?? watchId}',
    );
  }

  /// Removes [watchId] from the listed users' `savedWatches` and
  /// `recentlyViewedWatches`. [affectedUserIds] only covers customers who
  /// saved/viewed this watch after the engagement summary was introduced —
  /// any older, pre-existing references won't be caught here.
  Future<void> _removeWatchReferences(String watchId, Set<String> affectedUserIds) async {
    if (affectedUserIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final uid in affectedUserIds) {
      batch.update(_firestore.collection('users').doc(uid), {
        'savedWatches': FieldValue.arrayRemove([watchId]),
        'recentlyViewedWatches': FieldValue.arrayRemove([watchId]),
      });
    }
    await batch.commit();
  }

  /// Stream of watches belonging to the currently logged-in merchant.
  Stream<QuerySnapshot<Map<String, dynamic>>> myWatches() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _watches
        .where('merchantId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream of all watches listed in the catalog (for customers to browse).
  Stream<QuerySnapshot<Map<String, dynamic>>> allListedWatches() {
    return _watches
        .where('listedInCatalog', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Fetches customer-engagement stats for a merchant's own catalog,
  /// keyed by watch ID, from each watch's engagement summary doc (see
  /// firestore.rules — this is the only place that data is readable by
  /// the owning merchant, since a bulk query across the `users`
  /// collection itself is blocked for non-admins).
  ///
  /// Both `saverIds` and `viewerIds` are exact, not approximations:
  /// saves are a real wishlist signal, and views accumulate every
  /// distinct viewer permanently, unlike the customer's own capped
  /// `recentlyViewedWatches` list. A watch that predates this feature
  /// (or has never been saved/viewed since) simply has no summary doc
  /// yet, which reads back as all-zero counts, not an error.
  Future<EngagementStats> fetchEngagementStats(List<String> watchIds) async {
    if (watchIds.isEmpty) {
      return const EngagementStats(
        savedCounts: {},
        viewedCounts: {},
        uniqueSaverCount: 0,
      );
    }

    final summaries = await Future.wait([
      for (final id in watchIds) _watches.doc(id).collection('engagement').doc('summary').get(),
    ]);

    final savedCounts = <String, int>{};
    final viewedCounts = <String, int>{};
    final uniqueSavers = <String>{};

    for (var i = 0; i < watchIds.length; i++) {
      final data = summaries[i].data();
      final saverIds = (data?['saverIds'] as List?)?.cast<String>() ?? const [];
      final viewerIds = (data?['viewerIds'] as List?)?.cast<String>() ?? const [];
      savedCounts[watchIds[i]] = saverIds.length;
      viewedCounts[watchIds[i]] = viewerIds.length;
      uniqueSavers.addAll(saverIds);
    }

    return EngagementStats(
      savedCounts: savedCounts,
      viewedCounts: viewedCounts,
      uniqueSaverCount: uniqueSavers.length,
    );
  }
}

/// Result of [WatchService.fetchEngagementStats]. Not a Firestore
/// document, just an in-memory bundle of the computed counts, so a plain
/// class (rather than the raw-map style used for Firestore data
/// elsewhere in this app) is fine here.
class EngagementStats {
  const EngagementStats({
    required this.savedCounts,
    required this.viewedCounts,
    required this.uniqueSaverCount,
  });

  /// Watch ID -> number of customers who currently have it saved.
  final Map<String, int> savedCounts;

  /// Watch ID -> number of distinct customers who have ever viewed it.
  final Map<String, int> viewedCounts;

  /// Number of distinct customers who have saved at least one of this
  /// merchant's watches.
  final int uniqueSaverCount;

  int get totalSaves => savedCounts.values.fold(0, (a, b) => a + b);
}