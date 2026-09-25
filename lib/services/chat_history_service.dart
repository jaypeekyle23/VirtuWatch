import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'chat_service.dart';

/// Persists chat threads per user so reopening a chat (watch-specific or
/// the recommendations-wide one) continues where it left off, instead of
/// starting over every time the sheet is closed.
///
/// Stored at users/{uid}/chatThreads/{threadKey}. Best-effort throughout:
/// a save/load failure degrades to "chat just doesn't persist this time"
/// rather than breaking the chat itself.
class ChatHistoryService {
  // Cap how many messages we keep. Every stored message gets replayed as
  // conversation context on every future request, so an unbounded
  // history would quietly grow the token cost (and free-tier quota
  // usage) of every single message over time.
  static const int maxStoredMessages = 30;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>>? _threadDoc(String threadKey) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('chatThreads')
        .doc(threadKey);
  }

  Future<List<ChatMessage>> load(String threadKey) async {
    final doc = _threadDoc(threadKey);
    if (doc == null) return [];
    try {
      final snapshot = await doc.get();
      final raw = snapshot.data()?['messages'] as List?;
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((e) => ChatMessage(
                role: e['role'] as String? ?? 'user',
                text: e['text'] as String? ?? '',
              ))
          .where((m) => m.text.isNotEmpty)
          .toList();
    } catch (e) {
      // ignore: avoid_print
      debugPrint('ChatHistoryService.load error for "$threadKey": $e');
      return [];
    }
  }

  /// Fire-and-forget save — callers should not await this on the UI
  /// thread, so a slow/failed write never blocks the chat from feeling
  /// responsive.
  Future<void> save(String threadKey, List<ChatMessage> messages) async {
    final doc = _threadDoc(threadKey);
    if (doc == null) return;
    try {
      final trimmed = messages.length > maxStoredMessages
          ? messages.sublist(messages.length - maxStoredMessages)
          : messages;
      await doc.set({
        'messages':
            trimmed.map((m) => {'role': m.role, 'text': m.text}).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      debugPrint('ChatHistoryService.save error for "$threadKey": $e');
    }
  }

  Future<void> clear(String threadKey) async {
    final doc = _threadDoc(threadKey);
    if (doc == null) return;
    try {
      await doc.delete();
    } catch (_) {
      // Best-effort.
    }
  }
}