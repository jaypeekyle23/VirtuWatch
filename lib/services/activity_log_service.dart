import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Writes and reads entries in the `activityLog` collection, used to power
/// the admin dashboard's "Recent Activity" feed with real, specific events
/// (not just inferred from document timestamps).
class ActivityLogService {
  final _logs = FirebaseFirestore.instance.collection('activityLog');

  /// Records an activity log entry. Failures are swallowed on purpose —
  /// logging should never block or break the actual action it's describing
  /// (e.g. an account deletion should still succeed even if the log write
  /// fails for some reason).
  Future<void> log(String type, String message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _logs.add({
        'type': type,
        'message': message,
        'actorUid': user?.uid,
        'actorEmail': user?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Intentionally ignored — see doc comment above.
    }
  }

  /// Stream of the most recent activity log entries, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> recentActivity({int limit = 20}) {
    return _logs
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }
}