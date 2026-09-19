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
    await _watches.doc(watchId).delete();
    await _removeWatchReferences(watchId);
    await _activityLog.log(
      'watch_deleted',
      'Watch deleted: ${watchLabel ?? watchId}',
    );
  }

  /// Removes [watchId] from any user documents that still reference it in
  /// `savedWatches` or `recentlyViewedWatches`.
  Future<void> _removeWatchReferences(String watchId) async {
    final users = _firestore.collection('users');
    final affected = await Future.wait([
      users.where('savedWatches', arrayContains: watchId).get(),
      users.where('recentlyViewedWatches', arrayContains: watchId).get(),
    ]);

    final docsToUpdate = {
      for (final snapshot in affected) for (final doc in snapshot.docs) doc.id: doc.reference,
    };
    if (docsToUpdate.isEmpty) return;

    final batch = _firestore.batch();
    for (final ref in docsToUpdate.values) {
      batch.update(ref, {
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
}