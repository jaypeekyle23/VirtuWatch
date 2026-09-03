import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Stream of all user profiles, for the Admin's Account Management screen.
  Stream<QuerySnapshot<Map<String, dynamic>>> allUsers() {
    return _users.orderBy('createdAt', descending: true).snapshots();
  }

  /// Suspends an account, blocking future logins (handled in AuthService).
  Future<void> suspendAccount(String uid) async {
    await _users.doc(uid).update({'accountStatus': 'suspended'});
  }

  /// Reactivates a previously suspended account.
  Future<void> reactivateAccount(String uid) async {
    await _users.doc(uid).update({'accountStatus': 'active'});
  }

  /// Deletes a user's Firestore profile. Their Firebase Auth login will
  /// still technically exist, but they can no longer use the app since
  /// login requires a matching profile document.
  Future<void> deleteAccountProfile(String uid) async {
    await _users.doc(uid).delete();
  }
}