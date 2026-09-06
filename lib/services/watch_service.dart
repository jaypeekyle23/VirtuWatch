import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WatchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  }

  /// Updates an existing watch listing.
  Future<void> updateWatch(String watchId, Map<String, dynamic> data) async {
    await _watches.doc(watchId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a watch listing.
  Future<void> deleteWatch(String watchId) async {
    await _watches.doc(watchId).delete();
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