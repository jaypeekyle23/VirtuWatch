import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'chat_sheet.dart';

/// Opens the "Ask about this watch" chat, scoped to one watch's data
/// plus the current user's profile (wrist width, style, budget).
Future<void> showWatchChatSheet(
  BuildContext context, {
  required String watchId,
  required Map<String, dynamic> watchData,
}) {
  final name = watchData['name'] as String? ?? 'this watch';

  return showChatSheet(
    context,
    title: 'Ask about $name',
    emptyStateHint: 'Ask anything about $name — fit, materials, style, or '
        'how to wear it.',
    threadKey: 'watch_$watchId',
    createChatService: () async {
      // Load the current user's profile so the assistant can answer
      // fit/style questions using data the user already saved, instead
      // of asking for it again.
      Map<String, dynamic>? userProfile;
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          userProfile = doc.data();
        }
      } catch (_) {
        // Fall back to chatting without profile context rather than
        // blocking the whole feature.
      }
      return ChatService.forWatch(watchData: watchData, userProfile: userProfile);
    },
  );
}