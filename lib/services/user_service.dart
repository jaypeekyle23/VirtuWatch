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

  /// Toggles a watch's saved status for the currently logged-in user.
  Future<void> toggleSavedWatch(String watchId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    final docRef = _users.doc(uid);
    final doc = await docRef.get();
    final saved = (doc.data()?['savedWatches'] as List?)?.cast<String>() ?? [];

    if (saved.contains(watchId)) {
      await docRef.update({
        'savedWatches': FieldValue.arrayRemove([watchId]),
      });
    } else {
      await docRef.update({
        'savedWatches': FieldValue.arrayUnion([watchId]),
      });
    }
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
}