import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'activity_log_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _activityLog = ActivityLogService();

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Stream of all user profiles, for the Admin's Account Management screen.
  Stream<QuerySnapshot<Map<String, dynamic>>> allUsers() {
    return _users.orderBy('createdAt', descending: true).snapshots();
  }

  /// Suspends an account, blocking future logins (handled in AuthService).
  /// [accountLabel] is an optional human-readable identifier (e.g. a name
  /// and email) for the activity log message; falls back to the uid.
  Future<void> suspendAccount(String uid, {String? accountLabel}) async {
    await _users.doc(uid).update({'accountStatus': 'suspended'});
    await _activityLog.log(
      'account_disabled',
      'Account disabled: ${accountLabel ?? uid}',
    );
  }

  /// Reactivates a previously suspended account.
  Future<void> reactivateAccount(String uid, {String? accountLabel}) async {
    await _users.doc(uid).update({'accountStatus': 'active'});
    await _activityLog.log(
      'account_enabled',
      'Account re-enabled: ${accountLabel ?? uid}',
    );
  }

  /// Deletes a user's Firestore profile. Their Firebase Auth login will
  /// still technically exist, but they can no longer use the app since
  /// login requires a matching profile document.
  Future<void> deleteAccountProfile(String uid, {String? accountLabel}) async {
    await _users.doc(uid).delete();
    await _activityLog.log(
      'account_deleted',
      'Account deleted by admin: ${accountLabel ?? uid}',
    );
  }

  /// Updates a user's role. Used by admins to promote/demote accounts
  /// between customer, merchant, and admin.
  Future<void> updateUserRole(
    String uid,
    String newRole, {
    String? accountLabel,
    String? previousRole,
  }) async {
    if (!['customer', 'merchant', 'admin'].contains(newRole)) {
      throw 'Invalid role: $newRole';
    }
    await _users.doc(uid).update({'role': newRole});
    await _activityLog.log(
      'role_changed',
      'Role changed: ${accountLabel ?? uid}'
          '${previousRole != null ? ' from ${previousRole.toUpperCase()}' : ''}'
          ' to ${newRole.toUpperCase()}',
    );
  }

  /// The per-watch engagement summary doc (see [WatchService] and
  /// firestore.rules) that tracks which customers saved/viewed it,
  /// without exposing that on the publicly-readable watch document.
  DocumentReference<Map<String, dynamic>> _engagementRef(String watchId) =>
      _firestore.collection('watches').doc(watchId).collection('engagement').doc('summary');

  /// Toggles a watch's saved status for the currently logged-in user.
  Future<void> toggleSavedWatch(String watchId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    final docRef = _users.doc(uid);
    final doc = await docRef.get();
    final saved = (doc.data()?['savedWatches'] as List?)?.cast<String>() ?? [];
    final nowSaving = !saved.contains(watchId);

    final batch = _firestore.batch();
    batch.update(docRef, {
      'savedWatches': nowSaving
          ? FieldValue.arrayUnion([watchId])
          : FieldValue.arrayRemove([watchId]),
    });
    // set(merge: true) instead of update(), since this summary doc may
    // not exist yet if nobody has saved/viewed this watch before.
    batch.set(
      _engagementRef(watchId),
      {
        'saverIds': nowSaving
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Records that the current user viewed a watch, for the "Recently
  /// Viewed" section on their home tab. Moves the watch to the front if
  /// it's already in the list (most recent first) and caps the list at
  /// [maxEntries] so it doesn't grow unbounded over time.
  ///
  /// Separately, the watch's engagement summary tracks every distinct
  /// viewer with `viewerIds`. Unlike the capped list above, that set is
  /// never trimmed, so it stays an exact unique-viewer count rather than
  /// an approximation of "currently in someone's top 10".
  Future<void> recordRecentlyViewed(String watchId, {int maxEntries = 10}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docRef = _users.doc(uid);
    final doc = await docRef.get();
    final current =
        (doc.data()?['recentlyViewedWatches'] as List?)?.cast<String>() ?? [];

    final updated = [
      watchId,
      ...current.where((id) => id != watchId),
    ].take(maxEntries).toList();

    final batch = _firestore.batch();
    batch.update(docRef, {'recentlyViewedWatches': updated});
    batch.set(
      _engagementRef(watchId),
      {'viewerIds': FieldValue.arrayUnion([uid])},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Stream of the current user's own profile doc, used to reactively
  /// check which watches are saved (e.g. to toggle a heart icon).
  Stream<DocumentSnapshot<Map<String, dynamic>>> currentUserStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _users.doc(uid).snapshots();
  }

  /// Returns how many watches the current user has saved, without
  /// fetching the watch documents themselves. Used by
  /// EngagementNotificationService to decide whether a saved-watches
  /// reminder notification is worth showing.
  Future<int> savedWatchCount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;

    final userDoc = await _users.doc(uid).get();
    final savedIds =
        (userDoc.data()?['savedWatches'] as List?)?.cast<String>() ?? [];
    return savedIds.length;
  }

  /// Fetches brief data (name, brand, price, style) for the current
  /// user's saved/wishlist watches — used to give the AI chat assistant
  /// context on what the customer has already shown interest in,
  /// without pulling in full specs for every saved watch.
  Future<List<Map<String, dynamic>>> fetchSavedWatchesBrief() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final userDoc = await _users.doc(uid).get();
    final savedIds =
        (userDoc.data()?['savedWatches'] as List?)?.cast<String>() ?? [];
    if (savedIds.isEmpty) return [];

    final docs = await Future.wait(
      savedIds.map((id) => _firestore.collection('watches').doc(id).get()),
    );

    return docs
        .where((doc) => doc.exists)
        .map((doc) => {
              'name': doc.data()?['name'],
              'brand': doc.data()?['brand'],
              'price': doc.data()?['price'],
              'styleCategory': doc.data()?['styleCategory'],
            })
        .toList();
  }
}